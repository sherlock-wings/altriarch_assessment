"""
Pydantic request and response models, which are also what FastAPI renders as the
OpenAPI schema at /docs. The enums double as input validation: they accept any
casing but only the values the marts actually hold.
"""

from datetime import date
from decimal import Decimal
from enum import Enum

from pydantic import BaseModel


class CaseInsensitiveEnum(str, Enum):
    @classmethod
    def _missing_(cls, value):
        if isinstance(value, str):
            for member in cls:
                if member.value.upper() == value.upper():
                    return member
        return None


class LoanStatus(CaseInsensitiveEnum):
    ACTIVE = "ACTIVE"
    WATCH_LIST = "WATCH-LIST"
    CLOSED = "CLOSED"
    PAID_OFF = "PAID-OFF"


class ShareClass(CaseInsensitiveEnum):
    CLASS_A = "Class A"
    CLASS_B = "Class B"


class Loan(BaseModel):
    facility_id: str
    organization_id: str | None
    organization_name: str | None
    industry: str | None
    fund_description: str | None
    product_type: str | None
    status: str | None
    net_funds_employed: float | None
    facility_funding_limit: float | None
    discount_rate: float | None
    funding_date: date | None
    maturity_date: date | None


class LoanPage(BaseModel):
    limit: int
    offset: int
    total: int
    items: list[Loan]


class Borrower(BaseModel):
    organization_id: str
    organization_name: str | None
    industry: str | None
    state: str | None
    relationship_owner: str | None


class BorrowerLoans(BaseModel):
    borrower: Borrower
    loans: list[Loan]


class StatusBucket(BaseModel):
    status: str | None
    count: int
    outstanding: float


class BorrowerExposure(BaseModel):
    organization_id: str | None
    organization_name: str | None
    outstanding: float
    share_of_total: float


class PortfolioSummary(BaseModel):
    total_outstanding: float
    loan_count: int
    facilities_missing_balance: int
    loans_by_status: list[StatusBucket]
    top_borrowers: list[BorrowerExposure]


class RemittanceIn(BaseModel):
    facility_id: str
    amount: Decimal
    transaction_date: date
    share_class: ShareClass | None = None


class RemittanceOut(BaseModel):
    transaction_id: str
    facility_id: str
    amount: float
    transaction_date: date
    transaction_type: str
    status: str
    detail: str


class ErrorBody(BaseModel):
    code: str
    message: str
    detail: object | None = None


class ErrorResponse(BaseModel):
    error: ErrorBody
