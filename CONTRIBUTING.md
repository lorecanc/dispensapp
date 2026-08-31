# Contribuire a Inventario

Grazie per voler contribuire! Questo è un progetto open source — ogni PR è benvenuta.

## Setup

### Backend (FastAPI)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
# docs: http://127.0.0.1:8000/docs
```

Variabili utili: `DATABASE_URL` (default `sqlite:///<repo>/inventory.db` assoluto). Migrations Alembic auto-applicate al lancio; manuale con `alembic upgrade head` da `backend/`.

### iOS (SwiftUI)

Requisiti: Xcode 15+, iOS 17+, XcodeGen (`brew install xcodegen`).

```bash
cd ios
xcodegen generate          # rigenera Inventario.xcodeproj da project.yml
open Inventario.xcodeproj  # apri e Run (⌘R) su simulatore iOS 17+
```

Configura `http://127.0.0.1:8000` in Impostazioni se il backend gira altrove. Su device fisico usa l'IP del Mac (es. `http://192.168.1.x:8000`).

## Test

```bash
# Backend
pytest backend/tests/ -v
# oppure dal root
pytest -v

# iOS — da Xcode: Product > Test (⌘U)
# o CLI:
xcodebuild test -project ios/Inventario.xcodeproj -scheme Inventario -destination 'platform=iOS Simulator,name=iPhone 15'
```

Non modificare la logica backend né i test esistenti per task solo-UI/docs — scope discipline.

## Stile e convenzioni

- Swift: usa `Color+Palette` (Pantry/Moss/Terracotta/Stone/Oat/Status) + `Material+Glass` helper. Mai `Color.red` hardcoded.
- UI testi in italiano. `CategoryRegistry` è single source per categorie.
- Material su content (card/row/badge), glass solo su chrome (tabBar/toolbar/scanner overlay).
- Accessibilità: ogni card/row ha `accessibilityLabel`/`Value`/`Hint`, `dynamicTypeSize` con range, VoiceOver legge categoria e status.
- Markdown export con escape `|` e newline.

## PR Flow

1. Fork + branch feature (`feat/nome-breva`).
2. Commit piccoli, messaggi chiari in italiano o inglese.
3. Verifica: `pytest` verde + build iOS `xcodebuild` senza errori.
4. Apri PR verso `main` descrivendo cosa cambia e perché (linka issue se presente).
5. Mantieni diff minimo — non rifattorizzare codice non toccato dal task.

## Segnalazioni

Apri una Issue con passi per riprodurre, log e screenshot se UI.

## Licenza

Contribuendo accetti che il tuo codice sia distribuito sotto [MIT](./LICENSE).
