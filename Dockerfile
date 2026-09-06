# syntax=docker/dockerfile:1
FROM python:3.11-slim

WORKDIR /app

# Dipendenze - prima requirements per sfruttare cache layer
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Alembic e driver Postgres non sono in requirements.txt ma servono in prod
# (lifespan esegue `alembic upgrade head`; DATABASE_URL Postgres richiede psycopg2)
RUN pip install --no-cache-dir alembic psycopg2-binary

# Backend + alembic.ini/alembic/ già dentro backend/
COPY backend ./backend

EXPOSE 7860
EXPOSE 8000

# Lifespan in backend/main.py esegue già `alembic upgrade head` all'avvio
# con fallback su Base.metadata.create_all. PORT è iniettata da HF Spaces.
# HF Spaces espone 7860 (PORT=7860) — il default 7860 copre HF, locale usa PORT env.
CMD ["sh", "-c", "python -m uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-7860}"]
