# PlantDoctor — Project Audit

**Audit date:** 2026-09-27
**Auditor:** automated repository inspection (read-only; nothing was deleted or modified to produce this document)
**Repository root:** `/home/vansh/Desktop/PLANT`
**Version control:** ⚠️ **not a git repository.** See `PROBLEMS → P-1`.

---

## 0. Executive summary

| Question | Answer |
|---|---|
| Is there a mobile app? | **Yes** — Flutter 3.47.5 / Dart 3.13.4, Android-first, ~12,300 lines in `mobile/lib` |
| Is there a backend? | **Yes** — FastAPI + psycopg3, 388 lines, **read-only knowledge-base API only** |
| Is there a database? | **Yes** — PostgreSQL 16 installed; ~90 knowledge tables/views defined in `backend/migrations` |
| Is there authentication? | **No.** Zero auth code anywhere (server or mobile) |
| Is there a user model? | **No.** No `users` table, no `user_id` anywhere |
| Is there an image-upload pipeline? | **No.** `POST /images` is a deliberate 202 no-op stub |
| Is there a diagnosis/AI service? | **No** on the server. The mobile app has a *local, deterministic, non-ML* analysis engine |
| Does the mobile app talk to the server? | **No.** Zero HTTP client code, zero `Uri.parse`, no `INTERNET` permission |
| Do containers run? | **No.** Docker is not installed on this machine |
| Is the database running? | **No.** `pg_lsclusters` shows cluster `16/plantdoctor` pointing at `/plantdoctor-data/database/postgres`, **which no longer exists on disk** — the previous database is lost |

**Bottom line:** the knowledge base is a genuinely strong, already-built asset and must be
preserved and reused. Everything to do with *identity, sessions, user data, uploads, admin,
and mobile↔server communication* is greenfield. This is an **additive** project, not a rewrite.

---

## 1. Existing architecture

```
┌──────────────────────────┐        ┌────────────────────────────────────────────┐
│  mobile/  (Flutter)      │        │  backend/plantdoctor_api  (FastAPI)        │
│                          │        │                                            │
│  lib/services/*.dart     │   ✗    │  main.py  — 388 lines, read-only          │
│    107 hard-coded const  │  HTTP  │    /health /sources /plants /diseases     │
│    records, NO network   │        │    /pests /toxicity /plants/{id}/*         │
│                          │        │                                            │
│  lib/services/analysis/  │        │  db.py    — psycopg3 ConnectionPool      │
│    pure-Dart image       │        │  config.py — env-only settings            │
│    analysis (no ML)      │        │                                            │
│                          │        │  migrations/000..017 (.sql, 3,434 lines)  │
│  lib/services/storage/   │        │            │                              │
│    sqflite + files       │        │            ▼                              │
└──────────────────────────┘        │  PostgreSQL 16 — knowledge base          │
                                    │  scripts/ — migrate/import/backup/verify  │
                                    └────────────────────────────────────────────┘
```

There is **no wire between the two halves.** The Flutter app is a strictly offline,
single-user, anonymous application and its own documentation says so.

---

## 2. Existing technologies

### Backend (`backend/`)
| Concern | Technology | Notes |
|---|---|---|
| Language | Python 3.12.3 | system interpreter |
| Web framework | FastAPI 0.141.1 | 3 endpoints only |
| ASGI server | Uvicorn 0.54.0 | launched via `scripts/serve_api.py` |
| Validation | Pydantic 2.13.5 | **used implicitly by FastAPI only; no explicit schemas exist** |
| DB driver | psycopg 3.3.6 + psycopg-pool 3.3.3 | **raw SQL, no ORM** |
| Migrations | 18 hand-numbered `.sql` files + custom runner | **not Alembic** |
| DB | PostgreSQL 16 | cluster `plantdoctor` (data directory missing) |
| Tests | pytest 9.1.1 | `backend/tests/{conftest,test_database,test_crud}.py` |
| Other | Pillow 12.3.0, python-dotenv, python-multipart, httpx | |
| Virtualenv | `backend/.venv` | already provisioned |

### Mobile (`mobile/`)
| Concern | Technology |
|---|---|
| Language | Dart 3.13.4 / Flutter 3.47.5 stable |
| State | `provider` 6.1.5 (ChangeNotifier), 3 controllers |
| Imaging | `image` 4.10.1 (pure Dart) |
| Capture | `image_picker` 1.2.3 (`camera` 0.12.1 declared but unused) |
| Storage | `sqflite` 2.4.4 (2 tables), `shared_preferences` 2.5.5, files under app-documents |
| Charts | `fl_chart` 1.2.0 (declared, unused) |
| Android | minSdk 24, target/compile SDK 36, Java 17, `applicationId com.plantdoctor.plantdoctor` |
| Network | **none** |
| Secure storage | **none** |

---

## 3. Existing features

### 3.1 What the backend already does well (KEEP — DO NOT REPLACE)

The knowledge base is a **provenance-first, verification-first** design. This is the single
most valuable existing asset and directly satisfies specification rules 1, 8 and 9.

* **90+ tables and views** across 18 numbered SQL migrations, including:
  * Taxonomy: `plants`, `plant_taxonomy`, `plant_names`, `plant_synonyms`, `plant_parts`,
    `plant_habitats`, `plant_appearance`, `plant_appearance_attributes`
  * Care: `plant_growth_requirements`, `plant_characteristics`, `plant_identification_features`
  * Health: `diseases`, `disease_symptoms`, `disease_images`, `pests`, `pest_symptoms`,
    `symptoms`, `symptom_causes`, `symptom_plants`, `symptom_parts`, `symptom_images`,
    `plant_diseases`, `plant_pests`, `stress_symptoms`, `nutrient_deficiencies`
  * Prevention: `prevention_methods`, `condition_prevention`
  * Treatment/medicine: `treatments`, `treatment_products`, `active_ingredients`,
    `product_active_ingredients`, `treatment_dosages`, `treatment_instructions`,
    `treatment_safety`, `treatment_protective_equipment`, `treatment_prohibitions`,
    `treatment_restrictions`, `treatment_targets`, `treatment_plant_scope`
  * Safety/toxicity: `toxicity_profiles`, `human_safety`, `pet_safety`, `livestock_safety`,
    `first_aid_records`, `safety_warnings`, `possible_toxic_compounds`, `toxicity_parts`
  * Provenance: `sources`, `source_documents`, `verification_records`, `data_provenance`,
    `record_conflicts`, `import_batches`, `data_quality_reports`, `data_quality_findings`,
    `dosage_plausibility_rules`, `dosage_plausibility_findings`
  * Search: `plant_search_index`, `condition_search_index`, `fn_search_plants(...)`
  * ML bookkeeping: `model_versions`, `model_classes`, `model_labels`, `model_metrics`,
    `model_evaluations`, `prediction_records`, `scan_sessions`, `scan_evidence`,
    `scan_condition_candidates`
  * Read models: `v_plant_overview`, `v_plant_symptom_index`, `v_plant_conditions`,
    `v_condition_detail`, `v_subject_safety_summary`, `v_treatment_dosage_verified`,
    `v_data_quality_summary`, `v_missing_knowledge`, `v_science_fair_metrics`
* **SQL enum types** for statuses, so `verification_status` ∈ `{UNVERIFIED, VERIFIED, …}`
  and `treatment_type` ∈ `{CHEMICAL, BIOLOGICAL, CULTURAL, MECHANICAL, PREVENTIVE, …}`
  are enforced by the database itself.
* **Dose data is label-gated.** `v_treatment_dosage_verified` only exposes rows carrying
  `label_page_reference`, `label_url`, `label_sha256` and `last_verified` — an explicit
  implementation of spec rule 1 ("do not invent … dangerous pesticide instructions").
* **Unknown is a first-class value.** `v_subject_safety_summary.is_unknown` +
  `unknown_notice` implements "return *Information not verified* instead of generating".
* Integrity hardening migrations: `012_canonical_name_integrity`, `014_canonical_name_token_rule`,
  `015_nullable_unique_constraints`, `017_merge_duplicate_plants_self_guard`.
* Operational tooling in `scripts/`: `migrate.py` (checksummed, transactional, `--dry-run`),
  `import_plants.py`, `import_diseases.py`, `import_pests.py`, `import_dataset.py`,
  `validate_database.py`, `backup_database.py`, `restore_database.py`, `seed_sources.py`,
  `seed_minimal_kb.py`, `deduplicate_images.py`, `serve_api.py`.
* `data/sources.json` — a real source registry (GBIF, WFO, POWO …) with licences,
  attribution templates and terms URLs.

### 3.2 What the mobile app already does well (KEEP)

* A real, deterministic, documented **image-analysis pipeline** (845 lines) that runs
  entirely on-device: quality gate (blur via variance-of-Laplacian, brightness, plant
  presence, size) → HSV tile classification → connected-component plant masking →
  damage/spot detection → symptom fingerprint → 0–100 Health Index with published weights
  (colour 25 %, damage 30 %, spot 20 %, integrity 15 %, texture 10 %).
* **Honesty by construction:** species confidence is hard-capped at **0.42**, below the
  **0.45** certainty threshold, so species-level identification can never claim certainty.
  This is exactly the spirit of specification rule 9 and must be preserved.
* Local My-Plants + History persistence (SQLite) with a documented robustness fix.
* A 36–42 case synthetic benchmark (`ScienceFairService`) that runs the real engine live.
* A full legal pack (`docs/legal/*`) including an AI Disclaimer and a Data Policy that
  currently promises *"no data is uploaded to a server."*

### 3.3 Existing backend API surface (all read-only, unauthenticated)

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | pings PostgreSQL |
| GET | `/sources` | source registry |
| GET | `/plants` | paginated `v_plant_overview` |
| GET | `/plants/search` | `fn_search_plants()` |
| GET | `/plants/{id}` | base + growth requirements + names + synonyms + parts + appearance |
| GET | `/plants/{id}/diseases` | |
| GET | `/plants/{id}/pests` | |
| GET | `/plants/{id}/symptoms` | `v_plant_symptom_index` |
| GET | `/plants/{id}/toxicity` | returns explicit "unknown" payload when absent |
| GET | `/plants/{id}/treatments` | label-verified dosages only |
| GET | `/diseases`, `/diseases/{id}` | |
| GET | `/pests` | |
| GET | `/toxicity` | |
| POST | `/scan/analyze` | **deliberate 202 no-op** — "no fabrication" stub |
| POST | `/images` | **deliberate 202 no-op** metadata stub |
| GET | `/docs`, `/redoc` | FastAPI defaults, untitled beyond "PlantDoctor AI API v0.1.0" |

---

## 4. Existing problems

| ID | Severity | Problem | Evidence |
|---|---|---|---|
| **P-1** | 🔴 Critical | **No version control.** A `git init`/`.gitignore` has never been created. Nothing is protected from accidental loss. | `git status` → `fatal: not a git repository` |
| **P-2** | 🔴 Critical | **The PostgreSQL cluster is gone.** Cluster `16/plantdoctor` is registered with data directory `/plantdoctor-data/database/postgres`, but that path is an **empty directory**. All previously imported knowledge data is lost. `pg_isready` → `no response`; `service postgresql status` → `inactive (dead)`. | `ls -la /plantdoctor-data` → empty |
| **P-3** | 🔴 Critical | **Docker is not installed**, although the target deployment model assumes `docker compose`. | `which docker` → not found |
| **P-4** | 🔴 High | **No authentication, no users, no sessions.** The backend is fully public. Any knowledge data written later would be world-readable and world-writable. | no `users` table; no auth module |
| **P-5** | 🔴 High | **The mobile app cannot reach any server.** No `http`/`dio` dependency, no `Uri.parse`, no base-URL config, **no `android.permission.INTERNET`** in the release manifest, and no `usesCleartextTraffic` (so even with the permission, plain-HTTP LAN calls would be blocked). | `mobile/android/app/src/main/AndroidManifest.xml` contains only `CAMERA` |
| **P-6** | 🟠 High | **The whole knowledge base lives in the app as `const` Dart.** 107 records (12 species, 24 conditions, 26 health entries, 10 topics, 10 tips, 25 citations, 54 treatments) are hard-coded in `mobile/lib/services/*.dart`. Duplicated truth, no server-side search, and mobile binary carries the data. | `plant_database.dart`, `condition_content.dart`, `plant_health_content.dart`, `education_content.dart` |
| **P-7** | 🟠 High | **No upload / storage layer.** `POST /images` and `POST /scan/analyze` are honest 202 no-ops. There is no `stored_file` table, no filesystem layout, no MIME/size/dimension validation, no safe filename generation. | `main.py:365-388` |
| **P-8** | 🟠 High | **No rate limiting, no security headers, no CORS config, no audit log.** | absent from `main.py` |
| **P-9** | 🟠 High | **No secrets file at all.** `config.py` *requires* `PLANTDOCTOR_DB_PASSWORD` etc. from `/plantdoctor-data/.env`, but **no `.env.example` exists** anywhere and the file is absent, so the server cannot currently start. | `config.py:73-79` raises at import time |
| **P-10** | 🟠 High | **Error format is inconsistent.** Legacy endpoints return FastAPI's `{"detail": "..."}`; the spec mandates `{"success": false, "error": {"code", "message"}}`. `HTTPException` also leaks `detail` from internals. | `main.py:127, 292` |
| **P-11** | 🟡 Medium | **Two ID worlds.** Knowledge base uses `BIGSERIAL` integer IDs; the spec asks for UUIDs. Migration must not rewrite existing PKs (that would break every view and FK). New domain tables will use UUID PKs and reference knowledge rows by their existing integer IDs. | `plants.id BIGSERIAL` |
| **P-12** | 🟡 Medium | **No `onUpgrade` in mobile SQLite.** Schema frozen at v1 with no `user_id`, so multi-user sync needs a version bump + migration callback. | `app_database.dart:25-55` |
| **P-13** | 🟡 Medium | **`pubspec.yaml` description is the Flutter template default**; `camera`, `intl`, `fl_chart` are declared but never imported; `http` is present in `pubspec.lock` only as a transitive dep. | `pubspec.yaml:2, 33-46` |
| **P-14** | 🟡 Medium | **Docs claim the app is offline-only.** Three UI strings and four legal documents promise "photos never leave this device". Enabling server upload requires updating all of them. | `settings_screen.dart:99`, `scan_capture_screen.dart:129`, `docs/legal/DATA_POLICY.md:19` |
| **P-15** | 🟢 Low | `docs/` at the repository root is **empty**. `backups/` and `data/plantdoctor/` do not exist. | `ls -la docs` → empty |
| **P-16** | 🟢 Low | `data/assets/{data,images}` in the mobile project are empty directories; `pubspec.yaml` declares no `assets:` section. | `mobile/pubspec.yaml:64-100` |
| **P-17** | 🟢 Low | 3 unrelated Python processes on the box: a `webpanel.py` on `:8080` (occupies the legacy port), VS Code, and `bedrock_server`. Port 8080 will clash. | `ss -ltnp` |

---

## 5. Target architecture (proposed)

### 5.1 Decision: **additive, not replacement**

The existing knowledge base is **kept exactly as it is**. A new, self-contained modular
application `backend/app/` is added beside it, and the legacy FastAPI app is **mounted
unchanged** at the root so no existing endpoint changes behaviour. This satisfies
rule 6 (*never delete existing project without first inspecting it*) and keeps
`backend/tests/` green.

```
PLANT/
├── PROJECT_AUDIT.md
├── README.md                      ← new, rewritten
├── .gitignore                     ← new (P-1)
├── data/
│   ├── README.md
│   ├── postgres/                  ← cluster data dir (gitignored)
│   └── plantdoctor/               ← uploads/ backups/ logs/ (gitignored)
├── backups/README.md
├── docs/{API,DATABASE,AUTH,OTP,DEPLOYMENT,SECURITY}.md
├── scripts/                       ← EXISTING, extended (new cli/ subpackage)
├── mobile/                        ← EXISTING, Phase 12 adds lib/services/api/
└── backend/                       ← EXISTING DIRECTORY, extended
    ├── plantdoctor_api/           ← UNCHANGED knowledge-base app (mounted for compat)
    ├── migrations/                ← UNCHANGED knowledge-base SQL (still applied)
    ├── tests/                     ← EXISTING, extended
    ├── alembic/                   ← NEW, app-schema migrations only
    ├── alembic.ini
    ├── app/                       ← NEW production server
    │   ├── main.py                ← FastAPI app, /api/v1, /health, mounts legacy
    │   ├── cli.py                 ← python -m app.cli …
    │   ├── core/                  ← config, security, errors, logging, pagination
    │   ├── database/              ← SQLAlchemy engine/session/Base
    │   ├── models/                ← SQLAlchemy ORM (app domain)
    │   ├── schemas/               ← Pydantic v2
    │   ├── repositories/          ← data access (ORM for app, SQL for knowledge base)
    │   ├── services/              ← auth, otp, email, storage, audit, diagnosis
    │   ├── api/v1/{auth,users,plants,diseases,symptoms,treatments,medicines,
    │   │            doctors,diagnosis,my_plants,admin,health,search}/
    │   ├── otp/                   ← OTPProvider / EmailOTPProvider / SMSOTPProvider
    │   ├── storage/               ← StorageBackend ABC + FilesystemBackend
    │   └── security/              ← rate limit, headers, rbac, brute force
    ├── Dockerfile
    ├── docker-compose.yml
    ├── requirements.txt
    ├── .env.example
    └── README.md
```

### 5.2 How the two halves meet

* **One database, two owners.** PostgreSQL holds everything. The 18 numbered SQL files
  continue to own the knowledge base (they are checksummed and transactional); Alembic
  owns the *new* app domain and **never edits a knowledge-base table** (rule 11, and
  protects P-2's recovery path).
* **Two schema registries, one engine.** `app/database/` builds one SQLAlchemy engine
  used by the ORM models; knowledge-base reads go through `app/repositories/knowledge/`
  using parameterised `text()` SQL against the same engine. The legacy
  `plantdoctor_api` sub-app keeps its own psycopg pool (unchanged code, unchanged tests).
* **Verification-first, preserved.** Knowledge reads pass through
  `v_*` read models and `verification_status = 'VERIFIED'`. Nothing is fabricated to fill
  a gap: missing knowledge returns an explicit `unverified` marker.

### 5.3 Namespace map

| Spec item | Where it lives | Status |
|---|---|---|
| Users, profiles, roles, permissions | `users`, `user_profiles`, `roles`, `permissions`, `user_roles` | **new tables** |
| Sessions, refresh tokens | `user_sessions`, `refresh_tokens` | **new** |
| OTP | `otp_requests`, `otp_attempts` | **new** |
| Plants / species / varieties / aliases | `plants`, `plant_taxonomy`, `plant_names`, `plant_synonyms` | **reuse** |
| Plant images | `images`, `plant_image_links`, `disease_images` | **reuse** |
| Symptoms / diseases / causes | `symptoms`, `diseases`, `disease_symptoms`, `symptom_causes`, `plant_diseases` | **reuse** |
| Treatments / products / steps | `treatments`, `treatment_instructions`, `treatment_products` | **reuse** |
| Medicines | `treatment_products` + `active_ingredients` + `product_active_ingredients` | **reuse** |
| Doctors / experts | `doctors`, `doctor_specializations`, `doctor_credentials`, `experts` | **new tables** |
| Diagnoses | `scan_sessions`, `scan_evidence`, `scan_condition_candidates`, `prediction_records` | **reuse + new `diagnoses` API layer** |
| Saved plants, notes, health history | `saved_plants`, `user_plant_notes`, `plant_health_history` | **new tables** |
| Sources / verification | `sources`, `source_documents`, `verification_records`, new `data_verification` | **reuse + extend** |
| Notifications | `notifications` | **new** |
| Audit / admin actions | `audit_logs`, `admin_actions` | **new** |
| Settings / backups | `system_settings`, `database_backups` | **new** |

### 5.4 Hardware / network facts (measured, not guessed)

| Fact | Value |
|---|---|
| Desktop LAN IPv4 | **`192.168.29.199`** (`wlp1s0`, Wi-Fi, 192.168.29.0/24) |
| Default gateway | `192.168.29.1` |
| RAM / CPU | 11 GiB / 4 cores |
| Free disk on `/` | 785 GB |
| Python | 3.12.3 |
| PostgreSQL | 16.13, **not running**, stale cluster registration |
| Docker | **absent** |
| Nginx | **absent** |
| Redis | **absent** (optional per spec — design must degrade gracefully) |

**Consequence:** verification of this build must run **natively** (uvicorn + local
PostgreSQL). Docker/Nginx/Redis are still delivered as correct, documented, optional
artefacts that are *not* required for local development.

---

## 6. Recommended migration plan

Ordered by dependency. Each phase is independently verifiable and ends green.

| Phase | Deliverable | Verification gate |
|---|---|---|
| **1** | Audit; PostgreSQL cluster + role + DB restored; 18 knowledge migrations re-applied; `app/` skeleton; `config`; structured logging; consistent error envelope; `/health`, `/health/database`, `/health/redis`; `.env.example`; `.gitignore`; `requirements.txt`; `Dockerfile`; `docker-compose.yml`; nginx conf | server boots; health endpoints green; **legacy endpoints byte-identical**; `backend/tests` still pass |
| **2** | SQLAlchemy models; Alembic `0001` creating users/roles/permissions/sessions/refresh_tokens/otp/audit/system_settings; role + permission seed | `alembic upgrade head` on a fresh DB; `downgrade`; roles present |
| **3** | Argon2id hashing; password policy; register / login / refresh (with rotation + reuse detection) / logout / logout-all / sessions list + revoke; `GET,PATCH /api/v1/users/me` | pytest auth suite green |
| **4** | `OTPProvider` ABC + `EmailOTPProvider` (+ `SMSOTPProvider` stub); request/verify/resend; HMAC-hashed OTPs, 5-min expiry, attempt + resend caps; forgot/reset password; console SMTP sink for dev | pytest OTP suite green; brute-force provably blocked |
| **5** | `/api/v1/plants`, `/diseases`, `/symptoms`, `/treatments`, `/medicines` bridged to the existing knowledge base with pagination, filter, sort, full-text search | every record traceable to a `sources` row; unverified content is visibly marked |
| **6** | `doctors`/`experts` tables + APIs; sources API; `data_verification` workflow (DRAFT→REVIEW→VERIFIED→REJECTED) | only VERIFIED experts public |
| **7** | Storage abstraction + filesystem backend; MIME/extension/size/dimension validation; safe filenames; `POST /api/v1/diagnosis`; `POST /api/v1/diagnosis/images`; AI prediction kept structurally separate from verified knowledge | malicious filename + oversize + wrong-MIME all rejected with tests |
| **8** | `/api/v1/my-plants` CRUD + notes + health history | ownership enforced (user A cannot read user B) |
| **9** | Admin API: user management, knowledge CRUD, verification, sources, diagnosis review, settings; every sensitive action writes an `audit_logs` row | non-admin is 403 on every admin route |
| **10** | CORS, security headers, global rate limiting, login lockout, audit middleware, request IDs, no stack traces in production | header/limit/lockout tests green |
| **11** | Full pytest suite (auth, OTP, admin, CRUD, diagnosis, upload, search, relationships) | `pytest` green from a clean database |
| **12** | Flutter `ApiClient` + `TokenStore` (secure storage) + auth + auto-refresh; `AppConfig` with LAN-IP default; `INTERNET` permission + cleartext config for LAN; auth screens; wire existing screens to services | `flutter analyze` 0 issues; `flutter test` green |
| **13** | `backup` / `restore` CLI with retention + checksums; cron/systemd timer; `README.md`; `docs/*.md`; full-stack end-to-end run | backup → wipe → restore proven |

### Explicit non-goals (deliberate, to be confirmed)

1. **No rewrite of the knowledge base.** It is good; it stays.
2. **No removal of the legacy endpoints.** They are mounted unchanged.
3. **No fabricated science.** No invented plants, diseases, doses or doctors — not in
   schema, not in seed data, not in API responses.
4. **No on-device ML model.** The existing honest heuristic engine is retained; the
   server stores and structures results and clearly labels them as *predictions*.
5. **No public internet exposure by default.** LAN only, `0.0.0.0` bind, firewall-scoped.
