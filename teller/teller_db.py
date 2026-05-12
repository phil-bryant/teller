import ctypes
import os
import structlog
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

log = structlog.get_logger()


def _read_password_from_onepsa(item: str) -> str:
    lib_path = os.environ.get("ONEPSA_LIB_PATH", "/usr/local/lib/libonepsa.dylib")
    lib = ctypes.CDLL(lib_path)
    lib.OnepsaStringFree.argtypes = [ctypes.c_void_p]
    lib.OnepsaStringFree.restype = None
    lib.OnepsaGetField.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_char_p),
    ]
    lib.OnepsaGetField.restype = ctypes.c_void_p

    err = ctypes.c_char_p()
    out_ptr = lib.OnepsaGetField(item.encode("utf-8"), b"password", ctypes.byref(err))
    if err.value is not None:
        message = err.value.decode("utf-8")
        lib.OnepsaStringFree(err)
        raise RuntimeError(message)
    if not out_ptr:
        raise RuntimeError("libonepsa returned null password without error")

    out = ctypes.cast(out_ptr, ctypes.c_char_p).value
    lib.OnepsaStringFree(out_ptr)
    return (out or b"").decode("utf-8").strip()


def _read_password():
    password = os.environ.get("TELLER_DB_PASSWORD", "")
    if password:
        return password

    item = os.environ.get("TELLER_PSA_ITEM", "localhost_postgres_teller")
    try:
        password = _read_password_from_onepsa(item)
    except Exception as exc:
        raise RuntimeError("Could not read DB password from libonepsa") from exc
    if not password:
        raise RuntimeError(f"1psa returned empty password for item: {item}")
    return password

_engine = None

def get_engine():
    global _engine
    if _engine is None:
        password = _read_password()
        host = os.environ.get("TELLER_DB_HOST", "localhost")
        port = os.environ.get("TELLER_DB_PORT", "5432")
        db = os.environ.get("TELLER_DB_NAME", "prod")
        user = os.environ.get("TELLER_DB_USER", "teller")
        runtime_role = os.environ.get("TELLER_DB_ROLE", "teller_write").strip()
        _engine = create_engine("postgresql+psycopg2://", echo=False, connect_args={
            "host": host, "port": int(port), "dbname": db, "user": user, "password": password
        })

        @event.listens_for(_engine, "connect")
        def set_search_path(dbapi_conn, connection_record):
            cursor = dbapi_conn.cursor()
            cursor.execute("SET search_path TO teller")
            if runtime_role:
                cursor.execute("SELECT quote_ident(%s)", (runtime_role,))
                quoted_role = cursor.fetchone()[0]
                cursor.execute(f"SET ROLE {quoted_role}")
            cursor.close()

        log.info("Database engine created", host=host, port=port, db=db, user=user, runtime_role=runtime_role or None)
    return _engine

def get_session():
    return sessionmaker(bind=get_engine())()
