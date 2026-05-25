import ctypes
import os
import structlog
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from teller.teller_db_profile import ResolvedProfile, resolve_profile

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


#R025: Resolve the connection password. ``TELLER_DB_PASSWORD`` overrides everything;
#R025: otherwise fall back to libonepsa, then ~/.env, using the profile's item name.
def _read_password(profile: ResolvedProfile) -> str:
    password = os.environ.get("TELLER_DB_PASSWORD")
    if password:
        return password
    item = profile.onepsa_item
    if not item:
        raise RuntimeError(
            f"DB profile {profile.name!r} has no onepsa_item and TELLER_DB_PASSWORD is unset"
        )
    try:
        password = _read_password_from_onepsa(item)
    except Exception:
        password = None
    if password:
        return password
    from teller.teller_db_profile import _read_env_file_fields
    env_fields = _read_env_file_fields(item)
    password = env_fields.get("password")
    if not password:
        raise RuntimeError(f"Could not read DB password from 1psa or ~/.env for item: {item}")
    return password


_engine = None


#R030: Build a single cached SQLAlchemy engine driven by the active profile.
def get_engine():
    global _engine
    if _engine is None:
        profile = resolve_profile()
        password = _read_password(profile)
        connect_args = {
            "host": profile.host,
            "port": profile.port,
            "dbname": profile.dbname,
            "user": profile.user,
            "password": password,
        }
        #R035: Apply ``sslmode`` from the profile (Supabase requires TLS).
        if profile.sslmode and profile.sslmode != "disable":
            connect_args["sslmode"] = profile.sslmode
        _engine = create_engine("postgresql+psycopg2://", echo=False, connect_args=connect_args)

        #R040: On every new DBAPI connection, set the schema search path and
        #R040: optionally adopt the runtime role. Local PostgreSQL uses
        #R040: ``teller_write``; Supabase profiles can leave this blank to skip
        #R040: ``SET ROLE`` entirely.
        @event.listens_for(_engine, "connect")
        def _on_connect(dbapi_conn, connection_record):  # noqa: ARG001
            cursor = dbapi_conn.cursor()
            cursor.execute(f"SET search_path TO {profile.search_path}")
            if profile.runtime_role:
                cursor.execute("SELECT quote_ident(%s)", (profile.runtime_role,))
                quoted_role = cursor.fetchone()[0]
                cursor.execute(f"SET ROLE {quoted_role}")
            cursor.close()

        log.info(
            "Database engine created",
            profile=profile.name,
            host=profile.host,
            port=profile.port,
            db=profile.dbname,
            user=profile.user,
            sslmode=profile.sslmode,
            search_path=profile.search_path,
            runtime_role=profile.runtime_role or None,
        )
    return _engine


def get_session():
    return sessionmaker(bind=get_engine())()
