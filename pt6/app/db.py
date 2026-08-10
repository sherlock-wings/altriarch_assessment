"""
Snowflake connectivity for the API.

Reads every credential from pt6/.env
"""

import os
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv
from snowflake.connector import DictCursor

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

COMMON_VARS = (
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
    "SNOWFLAKE_AUTHENTICATOR",
)

AUTHENTICATOR_VARS = {
    "snowflake_jwt": ("SNOWFLAKE_PRIVATE_KEY_FILE",),
    "username_password_mfa": ("SNOWFLAKE_PASSWORD",),
    "snowflake": ("SNOWFLAKE_PASSWORD",),
}

_connection = None


def _connect_kwargs() -> dict:
    missing = [name for name in COMMON_VARS if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing environment variables: {', '.join(missing)}")

    authenticator = os.environ["SNOWFLAKE_AUTHENTICATOR"].lower()
    if authenticator not in AUTHENTICATOR_VARS:
        raise RuntimeError(
            f"SNOWFLAKE_AUTHENTICATOR must be one of {', '.join(AUTHENTICATOR_VARS)}, "
            f"got '{authenticator}'."
        )

    missing = [name for name in AUTHENTICATOR_VARS[authenticator] if not os.environ.get(name)]
    if missing:
        raise RuntimeError(
            f"SNOWFLAKE_AUTHENTICATOR={authenticator} requires: {', '.join(missing)}"
        )

    kwargs = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": os.environ["SNOWFLAKE_ROLE"],
        "warehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
        "database": os.environ["SNOWFLAKE_DATABASE"],
        "authenticator": authenticator,
        "client_session_keep_alive": True,
    }

    if authenticator == "snowflake_jwt":
        kwargs["private_key_file"] = os.environ["SNOWFLAKE_PRIVATE_KEY_FILE"]
        key_password = os.environ.get("SNOWFLAKE_PRIVATE_KEY_FILE_PWD")
        if key_password:
            kwargs["private_key_file_pwd"] = key_password.encode()
    else:
        kwargs["password"] = os.environ["SNOWFLAKE_PASSWORD"]

    return kwargs


def get_connection():
    global _connection
    if _connection is None or _connection.is_closed():
        _connection = snowflake.connector.connect(**_connect_kwargs())
    return _connection


def close_connection() -> None:
    global _connection
    if _connection is not None and not _connection.is_closed():
        _connection.close()
    _connection = None


def run_query(sql: str, params: dict | tuple | None = None) -> list[dict]:
    with get_connection().cursor(DictCursor) as cursor:
        cursor.execute(sql, params)
        return [{key.lower(): value for key, value in row.items()} for row in cursor.fetchall()]


def run_write(sql: str, params: dict | tuple | None = None) -> int:
    with get_connection().cursor() as cursor:
        cursor.execute(sql, params)
        return cursor.rowcount
