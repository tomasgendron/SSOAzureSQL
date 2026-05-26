import struct
from collections.abc import Generator
from contextlib import contextmanager
import os

import pyodbc
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

from .config import get_settings


SQL_COPT_SS_ACCESS_TOKEN = 1256
settings = get_settings()
if os.getenv("WEBSITE_SITE_NAME"):
    credential = ManagedIdentityCredential(client_id=settings.managed_identity_client_id)
else:
    credential = DefaultAzureCredential(
        managed_identity_client_id=settings.managed_identity_client_id,
        exclude_interactive_browser_credential=False,
    )


def _access_token_struct() -> bytes:
    token = credential.get_token("https://database.windows.net/.default").token
    token_bytes = token.encode("utf-16-le")
    return struct.pack("<I", len(token_bytes)) + token_bytes


def get_connection() -> pyodbc.Connection:
    connection_string = (
        f"Driver={{{settings.sql_odbc_driver}}};"
        f"Server=tcp:{settings.sql_server},1433;"
        f"Database={settings.sql_database};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )
    return pyodbc.connect(
        connection_string,
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: _access_token_struct()},
    )


@contextmanager
def db_cursor() -> Generator[pyodbc.Cursor, None, None]:
    connection = get_connection()
    try:
        cursor = connection.cursor()
        yield cursor
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
