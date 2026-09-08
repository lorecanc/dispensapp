# Wiki Log

## [2026-09-06] incremental-update | OFF v3 universal, naive-UTC fixes, two-axis categories, pantry cascade, iOS paging/TZ/outbox, prod default, CI + test suites (35 updated, 0 added)

- **Watermark range:** 179b4a5..25037bc (18 commits)
- **Pages created:** 0
- **Pages updated:** 35
  - Root: overview.md, architecture.md, getting-started.md (3)
  - Modules: backend-api.md, backend-config.md, backend-database.md, backend-models.md, backend-routes-contribute.md, backend-routes-inventory.md, backend-routes-pantries.md, backend-routes-scan.md, backend-schemas.md, backend-service-off.md, backend-tests.md (11)
  - Components: ios-category-picker.md, ios-inventory-list-view.md, ios-inventory-row-view.md, ios-item-detail-view.md, ios-scan-preview-sheet.md, ios-settings-view.md (6)
  - API: contribute.md, inventory.md, pantries.md, scan.md, suggestions.md (5)
  - Concepts: category-registry.md, ios-models.md, ios-networking.md, ios-offline-outbox.md, ios-state-management.md, off-integration.md, shopping-departments.md (7)
  - Config: backend-config.md, ios-config.md (2)
  - Dependencies: python-dependencies.md (1)
- **Pages deprecated:** 0
- **Depth:** Incremental (all categories + root touched, no structural changes)
- **Commit:** 25037bc
- **Themes:**
  - OFF v0→v3 universal rewrite (product_type=all): OFF_V3_BASE_URL / OFF_PRODUCT_TYPE_DEFAULT / OFF_V3_HOSTS, resolve_write_url
  - UtcDatetime + naive-UTC fixes; inventoryDate no-fraction naive step, outbound device-local TZ
  - Two-axis categories/storage_location; suggest_category / storage_for_category; source/product_type + ProductSource badges (sourceBadge)
  - Contribute product_type + 413-before-validation (413 wins over 422); uniform 422 handler
  - Pantry delete 6-table cascade
  - iOS listScoped paging loop; outbox stop on 401/403/408/429
  - APIConfig prod default; alembic-heads CI
  - 8 new backend test suites + iOS Red suites
- **Notes:**
  - `api/contribute.md` frontmatter description reads "Opt-in Open Facts write API" (missing "Food"); the index keeps the correct "Open Food Facts" spelling — wiki-writer should fix the frontmatter typo.
  - No new/removed pages; index descriptions synced from frontmatter (category-picker, category-registry, shopping-departments).

## [2026-09-05] audit-fix | Corrupted-session audit: root-link repair, frontmatter/terminology normalization, 11 stale pages refreshed

- **Scope:** form + content audit of the 2026-09-05 incremental update; no code changes (watermark unchanged: 179b4a5..179b4a5)
- **Form fixes:**
  - Root: overview.md, architecture.md, getting-started.md (9+2+9 `../` → `./` links), glossary.md (99 links) — 119 broken links, now 0
  - Components: ios-app-entry.md frontmatter normalized (added description, quoted category, standard key order + created)
  - Glossary: `.offline classification` → `offline classification`, `idempotenza 201/200` → `idempotent 201/200`, `temp-id negativi + remap` → `negative temp-ids + remap`, `[Scan API]` label → `[Scan]`
- **Pages updated:** 11 (stale since 2026-06-24, sources changed after June)
  - Modules: backend-api.md (7 routers, Alembic lifespan, error handler, CORS without Idempotency-Key), backend-service-expiration.md (exact match + aliases, get_status, resolve_expiration, 26 categories), backend-service-markdown-export.md (get_status reuse, escaping, DD/MM/YYYY, shopping_markdown reference)
  - Components: ios-category-picker.md (CategoryRegistry-driven), ios-empty-state-view.md (custom Material card + params, not ContentUnavailableView), ios-manual-entry-view.md (registry categories, offline enqueue, pantry-scoped client), ios-quantity-stepper.md (accessibility), ios-settings-view.md (Terra colors, ShareLink subject/message, store.client), ios-status-badge.md (Terra colors, Label + border + a11y)
  - Concepts: expiration-estimation.md (exact match, resolve_expiration section, 26 categories), item-status.md (get_status delegation, Terra colors, updated badge snippet)
- **Pages added:** 1
  - Modules: backend-routes-contribute.md (code-unit reference for routes/contribute.py, mirroring the scan route + API pattern)
- **Pages removed:** 0
- **Notes:**
  - `backend/routes/categories.py` linked as source_file of the Category Registry concept (no standalone module page: 36 lines, behavior covered).
  - Shopping side (`ShoppingStore`, `ShoppingListView`, `compartment.py`, `shopping_markdown.py`) verified covered via Shopping Routes module + Shopping Departments concept — no new pages.
  - `modules/backend-config.md` vs `config/backend-config.md` kept as-is: already split by angle (code constants vs env-var reference) with cross-links.

## [2026-06-24] initial-generation | Wiki initialization — all 39 pages created

- **Pages created:** 39
  - Root: overview.md, architecture.md, getting-started.md (3)
  - Modules: backend-api.md, backend-config.md, backend-database.md, backend-models.md, backend-schemas.md, backend-routes-inventory.md, backend-routes-scan.md, backend-service-off.md, backend-service-expiration.md, backend-service-markdown-export.md, backend-tests.md (11)
  - Components: ios-app-entry.md, ios-inventory-list-view.md, ios-inventory-row-view.md, ios-item-detail-view.md, ios-status-badge.md, ios-scanner-view.md, ios-scan-preview-sheet.md, ios-manual-entry-view.md, ios-settings-view.md, ios-quantity-stepper.md, ios-empty-state-view.md, ios-category-picker.md, ios-error-banner.md (13)
  - API: scan.md, inventory.md (2)
  - Concepts: expiration-estimation.md, off-integration.md, item-status.md, ios-networking.md, ios-state-management.md, ios-models.md (6)
  - Config: backend-config.md, ios-config.md (2)
  - Dependencies: python-dependencies.md, apple-dependencies.md (2)
- **Pages updated:** 0
- **Pages deprecated:** 0
- **Depth:** Full wiki (all categories)

## [2026-09-05] incremental-update | Pantry sharing, consume history, offline outbox, scan session, OFF contribute/photo, shopping departments (29 updated, 13 added)

- **Watermark range:** 27803fdb154c88d008e9147c165ff2f01ccf2d76..179b4a5d67828e87e9b314316cf8a54fdd06f772 (20 commits)
- **Pages updated:** 29
  - Root: overview.md, architecture.md, getting-started.md (3)
  - Modules: backend-config.md, backend-database.md, backend-models.md, backend-routes-inventory.md, backend-routes-scan.md, backend-schemas.md, backend-service-off.md, backend-tests.md, backend-api.md (9)
  - Components: ios-app-entry.md, ios-error-banner.md, ios-inventory-list-view.md, ios-inventory-row-view.md, ios-item-detail-view.md, ios-scan-preview-sheet.md, ios-scanner-view.md (7)
  - API: inventory.md, scan.md (2)
  - Concepts: ios-models.md, ios-networking.md, ios-state-management.md, off-integration.md (4)
  - Config: backend-config.md, ios-config.md (2)
  - Dependencies: apple-dependencies.md, python-dependencies.md (2)
- **Pages added:** 13
  - Modules: backend-routes-pantries.md, backend-routes-shopping.md (2)
  - API: pantries.md, contribute.md, suggestions.md (3)
  - Concepts: pantry-sharing.md, inventory-consume-history.md, ios-offline-outbox.md, shopping-departments.md, category-registry.md (5)
  - Components: ios-invite-members-sheet.md, ios-scan-session.md, ios-cached-thumbnail.md (3)
- **Pages removed:** 0
- **Commits:**
  - 179b4a5 feat(inventario): audit-fix completo Fasi A-D — suggestions auth, scan DB thread, CachedThumbnail, ConnectivityMonitor/OfflinePill/BannerView, OutboxStore/LocalInventoryCache, CategoryRegistry, ItemDetailView live-by-id
  - ca3bea1 chore(checkpoint): dispensa-storico-pill — Storico sheet da tre punti, archivio locale
  - 67e283b chore(checkpoint): inviti-UI-punto1 test
  - 7540ec7 chore(checkpoint): spesa-cleanup-reparti — rimozione dispensa da Spesa, export sheet-only, reparti
  - e27f48b checkpoint
  - b274307 chore(checkpoint): pill-aggiungi-prodotto — pill ovale, insets 16
  - 010bcf5 chore(checkpoint): gestione-dispense-liste-HIG — gestione dispense/liste, DELETE pantry/lista, delete ottimistica
  - 3a0c4d1 chore(checkpoint): risolvi-residui — idempotenza 201/200, privacy token, invite body dual, single-source pantry
  - ea7eaae chore(checkpoint): chiudi-debiti-qol — provisioning single-flight, single-source pantry, invite body dual
  - 7433541 chore(checkpoint): qol-multi-lista-share-consumo — pantries/invites/members, consume atomico + history, Keychain, test 88 green
  - 95da976 chore(checkpoint): elimina-tab-aggiungi
  - 27115a8 chore(checkpoint): fix-scan-shopping-orientations — ScannerView, ShoppingModels, ScanAcquiredOverlay
  - 251bbbf fix(docs): CORS snippet backend-api allineato a allowlist reale
  - df43c0c chore(checkpoint): follow-up mirror/test stabilizzazione — ScanPreviewSheet, PhotoEnrichmentTests
  - 8242c18 chore(checkpoint): follow-up HEIC compat + locks — maxPhotoBytes iOS
  - a1bde0a fix(off-photo): fix residui foto OFF — Content-Length 413, HEIC strict, photoError, guard 5MB
  - 4d13324 chore(checkpoint): OFF photo upload fase2 — POST /api/scan/contribute/photo verso product_image_upload.pl
  - 301b500 chore(checkpoint): OFF contribute onboarding — POST /api/scan/contribute verso product_jqm2.pl, staging default, CC BY-SA
  - d76adc0 chore(checkpoint): scansioni-multiple-cassa + restyle-Aggiungi — scanner continuo multiplo
  - 79e5039 chore(wiki): update watermark to 27803fd
