import ctypes
import os
import shlex
import structlog
from sqlalchemy import create_engine, event, exc
from sqlalchemy.orm import sessionmaker

from teller.teller_db_profile import ResolvedProfile, resolve_profile

log = structlog.get_logger()


#R025: Build the canonical 1psa password lookup command for diagnostics.
def _onepsa_password_command(item: str) -> str:
    return f"1psa -p {shlex.quote(item)}"


#R025: Read the DB password from libonepsa for the selected profile item.
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
    env_key = f"{item}.password"
    onepsa_command = _onepsa_password_command(item)
    log.info(
        "Resolving DB password via 1Password",
        item=item,
        onepsa_command=onepsa_command,
        env_fallback_key=env_key,
    )
    try:
        password = _read_password_from_onepsa(item)
    except KeyboardInterrupt:
        log.warning(
            "Interrupted during 1Password password lookup",
            item=item,
            onepsa_command=onepsa_command,
            env_fallback_key=env_key,
        )
        raise
    except Exception as exc:
        log.warning(
            "1Password password lookup failed; falling back to ~/.env",
            item=item,
            onepsa_command=onepsa_command,
            env_fallback_key=env_key,
            error=str(exc),
        )
        password = None
    if password:
        return password
    from teller.teller_db_profile import _read_env_file_fields
    env_fields = _read_env_file_fields(item)
    password = env_fields.get("password")
    if not password:
        raise RuntimeError(
            "Could not read DB password from 1psa or ~/.env for item: "
            f"{item}. Try: {onepsa_command}. If 1psa is rate limited, add "
            f"{env_key}=... to ~/.env or set TELLER_DB_PASSWORD."
        )
    return password


#R030: Escape SQLCipher/sqlite literal inputs used in PRAGMA/ATTACH statements.
def _escape_sqlite_literal(value: str) -> str:
    """Escape a string literal for sqlite/sqlcipher PRAGMA statements."""
    return value.replace("'", "''")


#R030: Resolve SQLCipher key from env override or profile configuration.
def _resolve_sqlcipher_key(profile: ResolvedProfile) -> str:
    key = os.environ.get("TELLER_DB_SQLCIPHER_KEY")
    if key:
        return key
    if profile.sqlcipher_key:
        return profile.sqlcipher_key
    raise RuntimeError(
        f"DB profile {profile.name!r} is missing sqlcipher_key. "
        "Set TELLER_DB_SQLCIPHER_KEY or populate sqlcipher_key on the profile item."
    )


#R045: Normalize sqlite file path and ensure its parent directory exists.
def _prepare_sqlite_path(sqlite_path: str) -> str:
    resolved_path = os.path.abspath(os.path.expanduser(sqlite_path))
    parent_dir = os.path.dirname(resolved_path)
    if parent_dir:
        os.makedirs(parent_dir, exist_ok=True)
    return resolved_path


#R045: Adapt pysqlcipher connections to sqlite3's optional deterministic callback API.
class _SqlcipherConnectionAdapter:
    def __init__(self, connection):
        self._connection = connection

    def create_function(self, name, num_params, func, deterministic=False):
        try:
            return self._connection.create_function(
                name,
                num_params,
                func,
                deterministic=deterministic,
            )
        except TypeError:
            #R045: Older pysqlcipher builds do not support the deterministic kwarg.
            return self._connection.create_function(name, num_params, func)

    def __getattr__(self, attr_name):
        return getattr(self._connection, attr_name)


_engine = None


#R030: Build a single cached SQLAlchemy engine driven by the active profile.
def get_engine():
    global _engine
    if _engine is None:
        profile = resolve_profile()
        if profile.target == "sqlite":
            sqlite_url = "sqlite://"
            sqlite_path = profile.sqlite_path or ""
            if sqlite_path:
                sqlite_path = _prepare_sqlite_path(sqlite_path)
            sqlcipher_key = _resolve_sqlcipher_key(profile)

            #R030: Open SQLCipher connection and attach the configured Teller database.
            def _connect_sqlcipher():
                try:
                    from pysqlcipher3 import dbapi2 as sqlcipher_dbapi
                except ImportError as exc:
                    raise RuntimeError(
                        "pysqlcipher3 is required for sqlite target. "
                        "Run ./04_load_requirements.sh after installing prerequisites."
                    ) from exc

                dbapi_conn = sqlcipher_dbapi.connect(":memory:")
                cursor = dbapi_conn.cursor()
                escaped_key = _escape_sqlite_literal(sqlcipher_key)
                cursor.execute(f"PRAGMA key = '{escaped_key}'")
                if sqlite_path:
                    escaped_path = _escape_sqlite_literal(sqlite_path)
                    cursor.execute(
                        f"ATTACH DATABASE '{escaped_path}' AS teller KEY '{escaped_key}'"
                    )
                cursor.execute("PRAGMA foreign_keys = ON")
                cursor.close()
                #R030: Disable the DBAPI's implicit transaction management so
                #R030: SQLAlchemy owns BEGIN/COMMIT; required for SAVEPOINT
                #R030: (Session.begin_nested) to work on the sqlite target.
                dbapi_conn.isolation_level = None
                return _SqlcipherConnectionAdapter(dbapi_conn)

            _engine = create_engine(sqlite_url, echo=False, creator=_connect_sqlcipher)

            #R030: Emit BEGIN explicitly because the DBAPI-level autobegin is
            #R030: disabled above (standard SQLAlchemy sqlite SAVEPOINT recipe).
            def _sqlite_begin(conn):
                conn.exec_driver_sql("BEGIN")

            try:
                event.listen(_engine, "begin", _sqlite_begin)
            except exc.InvalidRequestError:
                #R030: Unit lanes substitute mock engines that expose no events.
                pass
        else:
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
            def _on_connect(dbapi_conn, _connection_record):
                cursor = dbapi_conn.cursor()
                cursor.execute(
                    """
                    SELECT string_agg(quote_ident(trim(schema_name)), ',')
                    FROM unnest(string_to_array(%s, ',')) AS schema_name
                    WHERE trim(schema_name) <> ''
                    """,
                    (profile.search_path,),
                )
                quoted_search_path = cursor.fetchone()[0]
                if not quoted_search_path:
                    raise RuntimeError("DB profile search_path resolved to no schema identifiers")
                cursor.execute(f"SET search_path TO {quoted_search_path}")
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
            sqlite_path=profile.sqlite_path or None,
            target=profile.target,
        )
    return _engine


#R030: Create a SQLAlchemy session bound to the cached process engine.
def get_session():
    return sessionmaker(bind=get_engine())()
