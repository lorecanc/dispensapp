# Deploy backend su Koyeb

Backend FastAPI (`backend/main.py`) con lifespan che esegue `alembic upgrade head` all'avvio (fallback `Base.metadata.create_all` se alembic manca).

## File creati

- `Dockerfile` (root): `FROM python:3.11-slim`, `WORKDIR /app`, `COPY requirements.txt` + `pip install`, `COPY backend ./backend`, `EXPOSE 8000`, `CMD python -m uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8000}`
- `.dockerignore` : esclude `.venv`, `__pycache__`, `*.db`, `ios/`, `wiki/`, ecc.
- `koyeb.yaml` : spec Koyeb (service `api`, dockerfile `./Dockerfile`, env `DATABASE_URL` + `CORS_ORIGINS`)

## Variabili d'ambiente (Koyeb Dashboard > Service > Environment)

| Var | Obbligatoria | Esempio | Note |
|-----|--------------|---------|------|
| `DATABASE_URL` | sì (prod) | `postgresql://user:pass@ep-xxx.neon.tech/neondb?sslmode=require` | Neon Postgres. Se assente il backend usa `sqlite:////app/inventory.db` (effimero su Koyeb — non usare in prod). Il Dockerfile installa `psycopg2-binary` per Postgres. |
| `CORS_ORIGINS` | sì se frontend su dominio | `https://tuo-frontend.koyeb.app,https://app.example.com` | Lista comma-separated. In `backend/config.py` si somma ai default localhost. Lascia vuoto per solo localhost. |
| `PORT` | no | `8000` | Iniettata da Koyeb. Il `CMD` usa `${PORT:-8000}`. Non impostare manualmente. |

## Deploy

### Opzione A — da dashboard (consigliata)

1. Koyeb > Create App > GitHub repo `Inventario` > Branch `main` > Builder `Dockerfile` > Dockerfile location `./Dockerfile`
2. Environment variables: imposta `DATABASE_URL` (Neon) e `CORS_ORIGINS` (dominio frontend)
3. Port `8000` protocol `http`, path `/`, health check `/docs`
4. Deploy — log deve mostrare `Alembic upgrade` o `create_all fallback` nel lifespan

### Opzione B — via CLI con koyeb.yaml

```bash
brew install koyeb/tap/koyeb
koyeb app init inventario --docker ./Dockerfile
# oppure se la CLI supporta yaml:
koyeb deploy --koyeb-yaml koyeb.yaml
```

Modifica `koyeb.yaml` prima: sostituisci `DATABASE_URL` e `CORS_ORIGINS` con i valori reali (non committare secret — usa dashboard per secret).

## Migrazioni

- Automatiche: `lifespan` in `backend/main.py` cerca `backend/alembic.ini` (`Path(__file__).parent / "alembic.ini"`) e fa `command.upgrade(cfg, "head")`. Configura `sqlalchemy.url` da `DATABASE_URL` env.
- Manuale (opzionale nel Dockerfile CMD): `alembic -c backend/alembic.ini upgrade head` prima di uvicorn — ridondante perché lifespan già lo fa, quindi il `CMD` attuale lancia solo uvicorn. Se vuoi renderlo esplicito, cambia `CMD` in `sh -c "alembic -c backend/alembic.ini upgrade head && python -m uvicorn ..."` (idempotente).

## Verifica locale

```bash
# py_compile (senza Docker)
python -m py_compile backend/main.py backend/config.py backend/database.py

# build Docker (richiede Docker daemon attivo)
docker build -t inventario-api:test .
docker run --rm -p 8000:8000 -e DATABASE_URL=sqlite:////tmp/test.db inventario-api:test
# test: curl http://localhost:8000/docs
```

## iOS

Dopo il deploy, imposta in app iOS (Impostazioni > Server > URL API) l'URL Koyeb: `https://<tuo-app>-<id>.koyeb.app` e aggiungilo a `CORS_ORIGINS` sul backend.
