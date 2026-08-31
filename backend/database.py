import os
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

from backend.config import DATABASE_URL as _CONFIG_DATABASE_URL

# DATABASE_URL configurabile via env var; default assoluto rispetto al file.
# Usa il valore da config (già env-aware) come fallback, con ulteriore fallback
# assoluto se config avesse ancora un valore relativo legacy.
if _CONFIG_DATABASE_URL == "sqlite:///./inventory.db":
    _fallback_path = Path(__file__).resolve().parent.parent / "inventory.db"
    _fallback_url = f"sqlite:///{_fallback_path}"
else:
    _fallback_url = _CONFIG_DATABASE_URL
DATABASE_URL = os.getenv("DATABASE_URL", _fallback_url)

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=_connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
