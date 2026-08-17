# OTCMS — Pharmacy Management System

**Agya Appiah OTCMS** is an offline-first pharmacy management application for **Windows Desktop** and **Android phones**. Every business action works with zero connection — sales, inventory, expiry tracking, purchases, and reports — and changes synchronize safely to **Supabase** whenever the device is online.

> Everything a pharmacy does must work when the Internet does not. OTCMS was built around that rule: local data is the source of truth on each device, the cloud is a sync target, never a gate.

---

## Core Features

| Area | What it does |
|---|---|
| **Sales** | Fast point-of-sale with product search, batch-level FEFO allocation, and daily totals in whole pesewas |
| **Invoice numbering** | Collision-resistant offline: `INV-YYYYMMDD-<device>-<seq>` — unique per device, enforced on the server too |
| **Inventory** | Batches, FEFO (first-expired-first-out) picking, sellable stock, low/out-of-stock flags, reorder levels |
| **Expiry alerts** | Buckets at 7 / 30 / 60 / 90 / 180 days; expired stock is never sold automatically |
| **Purchases** | Purchase receipts with items, supplier tracking, batch creation on receipt |
| **Stock counts** | Session-based physical counts with adjustments |
| **Reports** | Sales, stock, expiry, and movement reporting derived from committed local data |
| **Dashboard** | Today's sales, transactions, inventory value, top sellers, products running low, expiry alerts |
| **Notifications** | In-app alerts for expiry, low stock, and sync status |
| **Users & roles** | Local user profiles with roles (Administrator / others) and an audit trail |
| **Settings** | Pharmacy profile (used on invoices), currency (GHS), timezone, thresholds |
| **Product import** | One-click import of the pharmacy's existing `Products.json` — names preserved exactly, prices kept to the pesewa, no duplicates |
| **Sync engine** | Outbox push (idempotent RPCs) + incremental pull; conflicts recorded for review; retry with backoff |
| **Offline mode** | Fully supported and never an error — the status bar shows `LOCAL MODE`, `OFFLINE`, or `ONLINE — SYNCED` |

## Money & Data Integrity

- **All money is integer pesewas** (`Money`). `33.8` becomes `3380` pesewas and renders `₵33.80`. No floating-point financial math, ever.
- Dates are stored as ISO-8601 UTC and shown in the pharmacy timezone (default `Africa/Accra`).
- Local writes are **atomic** (temp file + rename), debounced, and serialized — a crash can never leave a half-written collection.
- Corrupt or missing files are recovered gracefully, never a crash.

## Architecture

```
            WINDOWS DESKTOP                 ANDROID PHONE
       structured JSON local store       local cache (JSON boot,
                                          sqflite cache planned)
                     \                        /
                      \                      /
                        SYNC ENGINE (outbox push + incremental pull)
                               |
                          SUPABASE (PostgreSQL, RLS, RPCs)
```

- **Local-first**: business logic lives in plain Dart services (unit-testable without widgets); Riverpod providers expose state to the UI.
- **No codegen**: models are hand-written Dart with explicit `toJson` / `fromJson` — every line reviewable, no `build_runner`.
- Full details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### Tech stack

Flutter · Riverpod · Supabase (PostgreSQL + RLS + RPCs) · `uuid` · `intl` · `timezone` · `connectivity_plus` · `file_picker` · `mobile_scanner` (planned barcode scanning) · GitHub Actions CI

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **3.24.5 stable** (the version CI pins)
- Windows: Visual Studio with the "Desktop development with C++" workload
- Android: Android Studio + SDK (for phone builds)

### Run on Windows

```bash
cd app
flutter pub get
flutter run -d windows
```

### Run on Android

```bash
cd app
flutter run -d <device-id>
```

### First run

The app seeds a default pharmacy profile (`Agya Appiah OTCMS`) and starts in **local mode** — no accounts, no Internet required. Import your product list from **Settings → Product Catalog → Choose JSON file…**.

## Supabase Configuration

Without credentials the app runs fully local. To enable sync:

```bash
flutter run -d windows \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Database schema, RLS policies, and sync RPCs live in [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) — apply it from the Supabase SQL editor. The anon key is public by design; the service-role key must never appear in the app or repository.

> `app/lib/core/config/secrets.dart` is a committed **placeholder** with empty values so the app compiles. Real secrets only enter via `--dart-define` (or CI secrets) — never edit the placeholder with real keys.

## Tests

```bash
cd app
flutter test --coverage
```

Covered: money math, invoice numbering, JSON persistence + corruption recovery + export/import, legacy product import, FEFO allocation, expiry buckets, stock levels, daily sales summaries, and an app boot smoke test.

## CI / CD

`.github/workflows/build.yml` runs on every push/PR to `main`:

1. **Analyze + Test** — `flutter analyze` and the full test suite
2. **Android** — release APK + AAB
3. **Windows** — release build, packaged as `otcms-windows.zip`

Artifacts are downloadable from the Actions run.

## Project Structure

```
.
├── app/                        Flutter application
│   ├── lib/
│   │   ├── core/               money, ids, time, results, config
│   │   ├── models/             pure Dart domain classes (manual JSON)
│   │   ├── data/
│   │   │   ├── local/          LocalStore interface + JSON implementation
│   │   │   └── remote/         Supabase repository
│   │   ├── sync/               sync engine, outbox, pull, conflicts, connectivity
│   │   ├── services/           business logic (FEFO, daily sales, import, audit, auth)
│   │   ├── state/              Riverpod providers
│   │   └── ui/                 responsive shell + 13 screens
│   ├── android/                Android platform
│   ├── windows/                Windows platform
│   └── test/                   unit + widget tests
├── supabase/migrations/        schema, RLS, RPCs
├── docs/                       architecture + setup guides
├── .github/workflows/          CI pipeline
└── Products.json               the pharmacy's original product list (kept out of git;
                                use Settings → import, never commit pharmacy data)
```

## Status

- **Phase 1 (done):** foundation — models, local JSON store, business services, sync engine, full desktop/mobile shell, tests, CI, Supabase schema.
- **Next:** SQLite cache for Android, barcode scanning, backups & recovery UI, stock count flows, reporting exports, and mobile-screen polish.