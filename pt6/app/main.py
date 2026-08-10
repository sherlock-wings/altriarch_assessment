"""
The FastAPI app: four endpoints, plus the handlers that put every failure into one
error envelope. Reads go through the two MARTS views from 00-api-views.sql, which
already handle SCD filtering and guard rows; writes land in RAW for the Part 3
pipeline to process.
"""

import uuid
from contextlib import asynccontextmanager
from datetime import date

from fastapi import FastAPI, Query
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app import db
from app.models import (
    Borrower,
    BorrowerExposure,
    BorrowerLoans,
    ErrorResponse,
    Loan,
    LoanPage,
    LoanStatus,
    PortfolioSummary,
    RemittanceIn,
    RemittanceOut,
    StatusBucket,
)

LOAN_COLUMNS = """
       facility_id
      ,organization_id
      ,organization_name
      ,industry
      ,fund_description
      ,product_type
      ,status
      ,net_funds_employed
      ,facility_funding_limit
      ,discount_rate
      ,funding_date
      ,maturity_date
"""

ERROR_RESPONSES = {
    400: {"model": ErrorResponse},
    404: {"model": ErrorResponse},
    422: {"model": ErrorResponse},
}


class APIError(Exception):
    def __init__(self, status_code: int, code: str, message: str, detail=None):
        self.status_code = status_code
        self.code = code
        self.message = message
        self.detail = detail


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.get_connection()
    yield
    db.close_connection()


app = FastAPI(
    title="Callahan Private Credit API",
    version="1.0.0",
    description="Read-only reporting over CALLAHAN_DB.MARTS, plus remittance capture into RAW.",
    lifespan=lifespan,
)


def error_response(status_code: int, code: str, message: str, detail=None) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message, "detail": detail}},
    )


@app.exception_handler(APIError)
async def handle_api_error(_, exc: APIError) -> JSONResponse:
    return error_response(exc.status_code, exc.code, exc.message, exc.detail)


@app.exception_handler(RequestValidationError)
async def handle_validation_error(_, exc: RequestValidationError) -> JSONResponse:
    return error_response(
        422,
        "VALIDATION_ERROR",
        "The request did not match the expected schema.",
        jsonable_encoder(exc.errors()),
    )


@app.exception_handler(StarletteHTTPException)
async def handle_http_error(_, exc: StarletteHTTPException) -> JSONResponse:
    return error_response(exc.status_code, "HTTP_ERROR", str(exc.detail))


@app.get("/loans", response_model=LoanPage, responses=ERROR_RESPONSES)
def list_loans(
    status: LoanStatus | None = Query(None, description="Facility status, case-insensitive."),
    fund: str | None = Query(None, description="Fund description, case-insensitive exact match."),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> LoanPage:
    predicates, binds = [], []
    if status is not None:
        predicates.append("status = %s")
        binds.append(status.value)
    if fund is not None:
        predicates.append("upper(fund_description) = upper(%s)")
        binds.append(fund)

    where = f"where {' and '.join(predicates)}" if predicates else ""
    rows = db.run_query(
        f"select {LOAN_COLUMNS}, count(*) over () as total "
        f"from marts.v_api_loan {where} order by facility_id limit %s offset %s",
        (*binds, limit, offset),
    )

    if rows:
        total = rows[0]["total"]
    else:
        total = db.run_query(
            f"select count(*) as total from marts.v_api_loan {where}", tuple(binds)
        )[0]["total"]

    return LoanPage(
        limit=limit,
        offset=offset,
        total=total,
        items=[Loan(**{k: v for k, v in row.items() if k != "total"}) for row in rows],
    )


@app.get("/borrowers/{organization_id}/loans", response_model=BorrowerLoans, responses=ERROR_RESPONSES)
def list_borrower_loans(organization_id: str) -> BorrowerLoans:
    borrowers = db.run_query(
        "select organization_id, organization_name, industry, state, relationship_owner "
        "from marts.v_api_borrower where upper(organization_id) = upper(%s)",
        (organization_id,),
    )
    if not borrowers:
        raise APIError(
            404,
            "BORROWER_NOT_FOUND",
            f"No borrower with organization_id '{organization_id}'.",
        )

    loans = db.run_query(
        f"select {LOAN_COLUMNS} from marts.v_api_loan "
        "where upper(organization_id) = upper(%s) order by facility_id",
        (organization_id,),
    )
    return BorrowerLoans(
        borrower=Borrower(**borrowers[0]), loans=[Loan(**row) for row in loans]
    )


@app.get("/portfolio/summary", response_model=PortfolioSummary)
def portfolio_summary() -> PortfolioSummary:
    totals = db.run_query(
        "select coalesce(sum(net_funds_employed), 0) as total_outstanding "
        "      ,count(*) as loan_count "
        "      ,count_if(net_funds_employed is null) as facilities_missing_balance "
        "from marts.v_api_loan"
    )[0]

    by_status = db.run_query(
        "select status "
        "      ,count(*) as facility_count "
        "      ,coalesce(sum(net_funds_employed), 0) as outstanding "
        "from marts.v_api_loan group by status order by outstanding desc"
    )

    top = db.run_query(
        "select organization_id "
        "      ,organization_name "
        "      ,coalesce(sum(net_funds_employed), 0) as outstanding "
        "from marts.v_api_loan group by organization_id, organization_name "
        "order by outstanding desc limit 5"
    )

    total_outstanding = float(totals["total_outstanding"])
    return PortfolioSummary(
        total_outstanding=total_outstanding,
        loan_count=totals["loan_count"],
        facilities_missing_balance=totals["facilities_missing_balance"],
        loans_by_status=[
            StatusBucket(
                status=row["status"],
                count=row["facility_count"],
                outstanding=float(row["outstanding"]),
            )
            for row in by_status
        ],
        top_borrowers=[
            BorrowerExposure(
                organization_id=row["organization_id"],
                organization_name=row["organization_name"],
                outstanding=float(row["outstanding"]),
                share_of_total=(
                    float(row["outstanding"]) / total_outstanding if total_outstanding else 0.0
                ),
            )
            for row in top
        ],
    )


@app.post("/remittances", response_model=RemittanceOut, status_code=201, responses=ERROR_RESPONSES)
def create_remittance(remittance: RemittanceIn) -> RemittanceOut:
    if remittance.amount <= 0:
        raise APIError(
            400, "AMOUNT_NOT_POSITIVE", f"amount must be greater than 0, got {remittance.amount}."
        )
    if remittance.transaction_date > date.today():
        raise APIError(
            400,
            "TRANSACTION_DATE_IN_FUTURE",
            f"transaction_date must not be in the future, got {remittance.transaction_date}.",
        )

    facilities = db.run_query(
        "select facility_id, fund_description from marts.v_api_loan where upper(facility_id) = upper(%s)",
        (remittance.facility_id,),
    )
    if not facilities:
        raise APIError(
            404, "FACILITY_NOT_FOUND", f"No facility with id '{remittance.facility_id}'."
        )

    facility_id = facilities[0]["facility_id"]
    transaction_id = f"API-{uuid.uuid4().hex[:8]}"

    # DD-MON-YY, because STAGING parses this column with try_to_date(..., 'dd-mon-yy').
    # An ISO date lands as null there and the row is quarantined instead of loaded.
    db.run_write(
        "insert into raw.tenor_transactions_export "
        "     (transaction_id, transaction_date, fund, share_class, investment_ref "
        "     ,transaction_type, amount, file_name, file_row_number, file_last_modified) "
        "select %s, %s, %s, %s, %s, %s, %s, %s, %s, current_timestamp()::varchar",
        (
            transaction_id,
            remittance.transaction_date.strftime("%d-%b-%y"),
            facilities[0]["fund_description"],
            remittance.share_class.value if remittance.share_class else None,
            facility_id,
            "Remittance",
            format(remittance.amount, "f"),
            "api://remittances",
            "1",
        ),
    )

    return RemittanceOut(
        transaction_id=transaction_id,
        facility_id=facility_id,
        amount=float(remittance.amount),
        transaction_date=remittance.transaction_date,
        transaction_type="Remittance",
        status="accepted",
        detail=(
            "Queued for the Part 3 pipeline; visible in MARTS.FACT_TRANSACTION within ~30s."
        ),
    )
