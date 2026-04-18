import os
import subprocess
import structlog
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

log = structlog.get_logger()

def _read_password():
    password = os.environ.get("TELLER_DB_PASSWORD", "")
    if not password:
        try:
            result = subprocess.run(["1psa", "-p", os.environ.get("TELLER_PSA_ITEM", "localhost_postgres_teller")],
                                    capture_output=True, text=True, check=True)
            password = result.stdout.strip()
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            log.warning("Could not read DB password from 1psa", error=str(exc))
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
        _engine = create_engine("postgresql+psycopg2://", echo=False, connect_args={
            "host": host, "port": int(port), "dbname": db, "user": user, "password": password
        })

        @event.listens_for(_engine, "connect")
        def set_search_path(dbapi_conn, connection_record):
            cursor = dbapi_conn.cursor()
            cursor.execute("SET search_path TO teller")
            cursor.close()

        log.info("Database engine created", host=host, port=port, db=db, user=user)
    return _engine

def get_session():
    return sessionmaker(bind=get_engine())()
