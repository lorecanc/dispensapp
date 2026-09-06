# Deploy su Hugging Face Spaces (Docker)

Backend FastAPI (`backend/main.py`) collegato a Neon Postgres esistente (`DATABASE_URL` già fornito). Space Docker espone `7860` (HF default); locale usa `8000` via `PORT` env.

## File preparati

- `Dockerfile` (root): `FROM python:3.11-slim`, `EXPOSE 7860` + `EXPOSE 8000`, `CMD ["sh","-c","python -m uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-7860}"]` — HF inietta `PORT=7860`, locale usa `PORT` o fallback `7860` (puoi lanciare con `PORT=8000`).
- `README.md`: frontmatter HF in cima (`sdk: docker`, `app_port: 7860`) preservando contenuto esistente. Backup in `README.md.bak`.
- `.dockerignore` già esclude `.venv`, `__pycache__`, `*.db`, `ios/`, `wiki/`.

## Creare lo Space

1. Vai su https://huggingface.co/new-space
2. **Space name**: `inventario` (URL finale `https://<username>-inventario.hf.space`)
3. **SDK**: seleziona `Docker` (non Gradio/Streamlit)
4. **Visibility**: Public o Private a scelta
5. Crea lo Space (vuoto, con README template Docker)

## Push del codice

### Opzione A — push diretto allo Space (consigliata)

```bash
# aggiungi remote HF (sostituisci USERNAME)
git remote add hf https://huggingface.co/spaces/USERNAME/inventario
git push hf main
# se branch HF è main, altrimenti: git push hf HEAD:main
```

> HF Spaces clona il repo e fa `docker build` dal `Dockerfile` in root. Assicurati che `README.md` con frontmatter `app_port: 7860` sia nel push.

### Opzione B — duplicare repo GitHub

Collega lo Space a GitHub da Settings → non supportato nativamente per Docker; usa push mirror o GitHub Action che fa push su `huggingface.co`.

## Secrets e Variables

In Space → **Settings** → **Variables and secrets**:

| Tipo | Nome | Valore | Note |
|------|------|--------|------|
| Secret | `DATABASE_URL` | `postgresql://user:pass@ep-xxx.neon.tech/neondb?sslmode=require` | Neon Postgres già esistente. `?sslmode=require` obbligatorio. Il `lifespan` esegue `alembic upgrade head` con fallback `create_all`. |
| Secret | `CORS_ORIGINS` | `https://<username>-inventario.hf.space,http://localhost:3000` | Lista comma-separated. In `backend/config.py` si somma ai default localhost. Aggiungi dominio frontend se separato. |
| Variable | `PORT` | (non impostare) | HF imposta automaticamente `PORT=7860`. Il Dockerfile usa `${PORT:-7860}`. |

> **Non committare** `DATABASE_URL` nel repo — usa solo Secrets dello Space.

## Health check

Dopo il deploy (Build log → `Running on ...`):

```bash
curl https://<username>-inventario.hf.space/docs        # Swagger UI
curl https://<username>-inventario.hf.space/api/inventory  # lista inventario (richiede DB)
curl https://<username>-inventario.hf.space/openapi.json  # spec
```

HF Spaces fa health check su `/` e `/docs`; il backend risponde su entrambi.

## iOS — URL da impostare

In app iOS: **Impostazioni → Server → URL API** imposta:

```
https://<username>-inventario.hf.space
```

Sostituisci `<username>` con il tuo username HF (es. se username è `lore`, URL è `https://lore-inventario.hf.space`). Su simulatore e device fisico usa lo stesso URL (non serve `127.0.0.1`). Aggiungi lo stesso URL a `CORS_ORIGINS` nello Space se l'app web lo richiede.

## Verifica locale (prima del push)

```bash
python -m py_compile backend/main.py backend/config.py backend/database.py

docker build -t inventario-api:test .
docker run --rm -p 7860:7860 -e DATABASE_URL=sqlite:////tmp/test.db -e PORT=7860 inventario-api:test
# in altro terminale:
curl http://localhost:7860/docs
# test su 8000 (locale):
docker run --rm -p 8000:8000 -e DATABASE_URL=sqlite:////tmp/test.db -e PORT=8000 inventario-api:test
curl http://localhost:8000/docs
```

## Note

- Alembic: `lifespan` in `backend/main.py` cerca `backend/alembic.ini` e fa `command.upgrade(cfg, "head")` con `sqlalchemy.url` da `DATABASE_URL` env. Nessuna modifica backend oltre Dockerfile.
- HF Spaces Docker espone solo `7860` pubblicamente — `EXPOSE 8000` è mantenuto per compatibilità locale senza effetti su HF.
- Se il build HF fallisce su `psycopg2-binary`, verifica che `requirements.txt` + `pip install alembic psycopg2-binary` siano nel Dockerfile (già presenti).
