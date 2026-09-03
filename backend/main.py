import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.config import CORS_ORIGINS
from backend.database import Base, engine

logger = logging.getLogger(__name__)
from backend.routes.categories import router as categories_router
from backend.routes.contribute import router as contribute_router
from backend.routes.inventory import router as inventory_router
from backend.routes.pantries import router as pantries_router
from backend.routes.scan import router as scan_router
from backend.routes.shopping import router as shopping_router
from backend.routes.suggestions import router as suggestions_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Migrazioni gestite da Alembic; create_all solo come fallback se Alembic
    # non è disponibile (es. env di test leggeri) o alembic.ini mancante.
    try:
        from pathlib import Path

        from alembic import command
        from alembic.config import Config

        alembic_ini = Path(__file__).resolve().parent / "alembic.ini"
        if alembic_ini.exists():
            cfg = Config(str(alembic_ini))
            # Usa DATABASE_URL da env/config (path assoluto) per l'upgrade
            import os

            from backend.config import DATABASE_URL as _lifespan_url

            cfg.set_main_option("sqlalchemy.url", os.getenv("DATABASE_URL", _lifespan_url))
            command.upgrade(cfg, "head")
        else:
            logger.warning("alembic.ini mancante, usato create_all fallback")
            Base.metadata.create_all(bind=engine)
    except Exception as e:
        logger.warning("Alembic upgrade fallito (%s), uso create_all fallback", e)
        Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="Inventario Dispensa API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "Accept", "X-Pantry-Token"],
)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    # uniforma errori a {"detail": ...} mantenendo alias "message" per compatibilità legacy/test
    content: dict = {"detail": exc.detail}
    if isinstance(exc.detail, str):
        content["message"] = exc.detail
    return JSONResponse(status_code=exc.status_code, content=content)


app.include_router(scan_router)
app.include_router(contribute_router)
app.include_router(inventory_router)
app.include_router(pantries_router)
app.include_router(categories_router)
app.include_router(shopping_router)
app.include_router(suggestions_router)

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
