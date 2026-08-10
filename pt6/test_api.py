"""
End-to-end tests against the live Snowflake account, no mocking.

Every case here is read-only. The POST /remittances success path is deliberately
absent: it moves a real facility balance, so it is exercised by hand rather than on
every test run.
"""

import sys
from datetime import date, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as test_client:
        yield test_client


def test_loans_filter_is_case_insensitive(client):
    lower = client.get("/loans", params={"status": "active", "limit": 200})
    upper = client.get("/loans", params={"status": "ACTIVE", "limit": 200})
    assert lower.status_code == 200
    assert lower.json()["total"] == upper.json()["total"]
    assert {item["status"] for item in lower.json()["items"]} == {"ACTIVE"}


def test_loans_pagination_reports_full_total(client):
    page = client.get("/loans", params={"limit": 5, "offset": 0}).json()
    assert len(page["items"]) == 5
    assert page["total"] > 5


def test_unknown_borrower_returns_404(client):
    response = client.get("/borrowers/AFF-9999/loans")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "BORROWER_NOT_FOUND"


def test_borrower_without_facilities_returns_empty_list(client):
    response = client.get("/borrowers/AFF-2029/loans")
    assert response.status_code == 200
    assert response.json()["loans"] == []


def test_summary_status_buckets_reconcile_to_total(client):
    summary = client.get("/portfolio/summary").json()
    assert sum(bucket["count"] for bucket in summary["loans_by_status"]) == summary["loan_count"]
    assert round(sum(b["outstanding"] for b in summary["loans_by_status"]), 2) == round(
        summary["total_outstanding"], 2
    )


@pytest.mark.parametrize(
    "body,code",
    [
        ({"facility_id": "FV-1001", "amount": 0, "transaction_date": "2026-01-01"},
         "AMOUNT_NOT_POSITIVE"),
        ({"facility_id": "FV-1001", "amount": -1, "transaction_date": "2026-01-01"},
         "AMOUNT_NOT_POSITIVE"),
        ({"facility_id": "FV-1001", "amount": 100,
          "transaction_date": str(date.today() + timedelta(days=1))},
         "TRANSACTION_DATE_IN_FUTURE"),
    ],
)
def test_remittance_business_rules_return_400(client, body, code):
    response = client.post("/remittances", json=body)
    assert response.status_code == 400
    assert response.json()["error"]["code"] == code


def test_remittance_unknown_facility_returns_404(client):
    response = client.post(
        "/remittances",
        json={"facility_id": "FV-9999", "amount": 100, "transaction_date": "2026-01-01"},
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "FACILITY_NOT_FOUND"


def test_remittance_schema_violation_returns_422(client):
    response = client.post(
        "/remittances",
        json={"facility_id": "FV-1001", "amount": "abc", "transaction_date": "2026-01-01"},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"
