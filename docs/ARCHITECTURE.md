# OTCMS — Pharmacy Management System Architecture

**Agya Appiah OTCMS** — offline-first pharmacy management for Windows Desktop + Android, synchronized through Supabase.

---

## 1. System Overview

```
                    SUPABASE (PostgreSQL)
                    CENTRAL CLOUD DATABASE
                            |
                +-----------+-----------+
                |                       |
          WINDOWS DESKTOP           ANDROID PHONE
                |                       |
        LOCAL JSON DATABASE       LOCAL SQLITE CACHE
        (structured per-             (sqflite)
        collection files)                 |
                |                       |
                +-----------+-----------+
                            |
                       SYNC ENGINE
                       (outbox push +
                        incremental pull)
                            |
                       SUPABASE
```

- **Online**: Supabase is the authoritative store (auth, tenant data, audit).
- **Offline**: both platforms operate fully from local data. Offline is a supported mode, never an error.
- **Synchronization**: local → outbox queue → push (idempotent RPCs) → pull (incremental since last sync point).

---

## 2. Repository & Flutter App Layout

```
OTCMS/                          (git monorepo)
├── app/                        Flutter application (Windows + Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/               money, ids, time, results, config
│   │   ├── models/             pure Dart domain classes (manual JSON, no codegen)
│   │   ├── data/
│   │   │   ├── local/          LocalStore interface
│   │   │   │   ├── json/       Windows JSON implementation
│   │   │   │   └── sqflite/    Android sqflite implementation
│   │   │   ├── remote/         Supabase repository (RLS-scoped)
│   │   │   └── repositories/   domain repositories (local-first)
│   │   ├── sync/               sync engine, outbox, pull, conflicts
│   │   ├── services/           pure business logic (no Flutter imports where possible)
│   │   ├── state/              Riverpod providers
│   │   └── ui/                 desktop + mobile shells, shared screens
│   ├── assets/
│   ├── android/                Android platform (built in CI)
│   ├── windows/                Windows platform
│   └── test/                   unit + integration tests
├── supabase/
│   └── migrations/0001_init.sql   complete schema, RLS, RPCs, seed admin
├── docs/
│   ├── ARCHITECTURE.md         (this file)
│   └── SETUP.md                Supabase + GitHub Actions + secrets guide
├── data/
│   └── products_master.json    the pharmacy's original product list (source of truth for import)
└── .github/workflows/build.yml  CI/CD (test, Android APK/AAB, Windows ZIP)
```

**Decisions**
- No codegen (`freezed`/`drift` avoided): models are hand-written Dart with explicit `toJson`/`fromJson`; every line is reviewable and CI-verifiable without `build_runner`.
- State management: **Riverpod**; business logic lives in plain services so it is unit-testable without widgets.
- Money: `Money` = integer minor units (pesewas). All financial math integer-only. `33.8` → `3380` pesewas → renders `₵33.80`.
- Dates: stored ISO-8601 UTC (`...Z`); display uses configured pharmacy timezone (default `Africa/Accra`).

---

## 3. Windows Local JSON Storage

Directory: `<settings.dataDirectory>` (default `%APPDATA%/OTCMS`):

```
OTCMS/
├── data/
│   ├── pharmacy.json          pharmacy profile + branches
│   ├── users.json             local mirror of user profiles + roles
│   ├── categories.json
│   ├── products.json
│   ├── suppliers.json
│   ├── batches.json
│   ├── sales.json
│   ├── sale_items.json
│   ├── purchases.json
│   ├── purchase_items.json
│   ├── stock_movements.json
│   ├── notifications.json
│   └── audit_log.json
├── sync/
│   ├── pending_operations.json
│   ├── sync_state.json        deviceId, lastPulledAt, lastPushedAt, counters
│   └── conflicts.json
├── settings/
│   └── settings.json          pharmacy name, address, currency, timezone, thresholds
└── backups/
    └── backup_YYYYMMDD_HHMMSS/   full snapshot (one JSON file per collection)
```

**File format** — every collection file:

```json
{ "schemaVersion": 1, "items": [ ... ] }
```

**Integrity rules**
1. One file per collection — only the changed collection is rewritten, never one giant blob.
2. Atomic writes: write `<file>.tmp` → flush → `File.rename` over the target.
3. Write-behind: collection writes are debounced (short timer) and serialized through a single writer queue.
4. Backups: automatic before first sync after N days/major import and on demand (`Settings → Backup`). Retention: keep last 30.
5. Recovery: if a file is corrupt/missing, it is rebuilt from Supabase (pull) when online; the app logs a recovery event and continues; offline, an empty collection + notice is used rather than a crash.
6. `products.json` supports the pharmacy's original shape on import: `Name`, `Responsible`, `Sales Price` map to `name`, `responsible`, `sellingPrice` and every original product is preserved (names never altered, prices preserved exactly as pesewas).

**High-level equivalent schema** (conceptual, split across files):

```json
{
  "schemaVersion": 1,
  "pharmacy": { },
  "branches": [ ],
  "users": [ ],
  "categories": [ ],
  "products": [ ],
  "suppliers": [ ],
  "batches": [ ],
  "sales": [ ],
  "saleItems": [ ],
  "purchases": [ ],
  "purchaseItems": [ ],
  "stockMovements": [ ],
  "notifications": [ ],
  "sync": { },
  "settings": { }
}
```

---

## 4. Domain Models (used by JSON, SQLite, and Supabase)

All IDs are UUIDs with type prefixes, generated client-side: `prod_`, `batch_`, `sale_`, `sup_`, `cat_`, `mov_`, `op_`, `notif_`...

### 4.1 Product

```json
{
  "id": "prod_001",
  "organizationId": null,
  "branchId": null,
  "name": "3FER SYRUP",
  "genericName": null,
  "brandName": null,
  "categoryId": null,
  "dosageForm": null,
  "strength": null,
  "packSize": null,
  "barcode": null,
  "sku": null,
  "manufacturer": null,
  "responsible": "Administrator",
  "sellingPricePesewas": 1454,
  "costPricePesewas": null,
  "reorderLevel": 10,
  "minimumStock": 5,
  "targetStock": 50,
  "reorderQuantity": 20,
  "active": true,
  "createdAt": "...",
  "updatedAt": "..."
}
```

- Only `id`, `name`, `sellingPricePesewas` are required; every other field is nullable/optional.
- `name` is unique within an organization (server-enforced) so imports never duplicate.

### 4.2 Category — `{ id, name, description?, createdAt, updatedAt }`

### 4.3 Batch

```json
{
  "id": "batch_001",
  "productId": "prod_001",
  "batchNumber": "BATCH-2026-001",
  "expiryDate": "2026-12-30",          // YYYY-MM-DD, nullable for non-expiring
  "manufactureDate": null,
  "quantity": 100,                     // remaining sellable units (derived from movements, mirrored here)
  "costPricePesewas": 850,
  "sellingPricePesewas": 1454,
  "supplierId": null,
  "receivedAt": "2026-08-17T10:00:00Z",
  "branchId": null,
  "organizationId": null,
  "createdAt": "...",
  "updatedAt": "..."
}
```

Sellable quantity of a batch = committed stock movements per batch; `quantity` is always the **remaining** stock.

### 4.4 Stock Movement (transactional inventory truth)

```json
{
  "id": "mov_001",
  "operationId": "op_001",
  "productId": "prod_001",
  "batchId": "batch_001",
  "quantity": 30,                        // always positive; direction comes from type
  "movementType": "SALE",                // OPENING_BALANCE | PURCHASE_RECEIPT | SALE | SALE_RETURN
                                         // | PURCHASE_RETURN | STOCK_ADJUSTMENT | DAMAGE
                                         // | EXPIRED | TRANSFER_IN | TRANSFER_OUT
  "referenceId": "sale_001",
  "reason": null,
  "userId": "user_001",
  "branchId": null,
  "organizationId": null,
  "createdAt": "...",
  "syncStatus": "PENDING"                // PENDING | SYNCED
}
```

Movement signs: `SALE, PURCHASE_RETURN, STOCK_ADJUSTMENT(negative), DAMAGE, EXPIRED, TRANSFER_OUT` decrement; `PURCHASE_RECEIPT, SALE_RETURN, STOCK_ADJUSTMENT(positive), OPENING_BALANCE, TRANSFER_IN` increment. Stock totals are **derived** by summing movements — never blindly overwritten.

### 4.5 Sale + Sale Item

```json
{
  "id": "sale_001",
  "operationId": "operation_001",
  "invoiceNumber": "INV-20260817-1A2F-0042",
  "userId": "user_001",
  "sellerName": "Kwame Appiah",
  "deviceId": "ANDROID-001",
  "branchId": null,
  "organizationId": null,
  "date": "2026-08-17",
  "time": "10:42:00",
  "createdAt": "2026-08-17T10:42:00Z",
  "items": [{
     "id": "si_001",
     "productId": "prod_001",
     "medicineName": "Paracetamol 500mg",   // denormalized for invoices/reports
     "quantity": 2,
     "unitPricePesewas": 1000,
     "amountPesewas": 2000,
     "batchId": "batch_001"
  }],
  "totalAmountPesewas": 5000,
  "syncStatus": "PENDING"
}
```

The seller comes from the authenticated profile — never typed text. `totalAmount` is always computed by the system, never user-entered.

### 4.6 Invoice (derived view of a Sale)

```
AGYA APPIAH OTCMS                ← pharmacy.name (configurable)
INVOICE: INV-20260817-1A2F-0042
Date: 17 August 2026
Time: 10:42 AM
Sold By: Kwame Appiah
--------------------------------
Medicine            Qty     Amount
Paracetamol 500mg    2      ₵20.00
Vitamin C            1      ₵15.00
ORS                  3      ₵15.00
--------------------------------
TOTAL: ₵50.00
Thank you
```

Invoice numbering: `INV-YYYYMMDD-<devicePrefix3>-<dailySeq4>` — daily per-device sequence + device fragment ⇒ collision-resistant across offline devices; server enforces a unique index and rejects duplicates (idempotent retry regenerates on true collision).

### 4.7 Supplier — `{ id, name, phone, address, email, contactPerson, organizationId, branchId, createdAt, updatedAt }`

### 4.8 Purchase + Purchase Item

```json
{
  "id": "pur_001",
  "operationId": "op_002",
  "supplierId": "sup_001",
  "purchaseNumber": "PO-2026-0001",
  "status": "RECEIVED",                  // DRAFT | ORDERED | RECEIVED | CANCELLED
  "totalCostPesewas": 0,
  "receivedAt": null,
  "userId": "...", "branchId": null, "organizationId": null,
  "createdAt": "...", "updatedAt": "...",
  "syncStatus": "PENDING"
}
```

`purchaseItem`: `{ id, purchaseId, productId, quantity, costPricePesewas, batchNumber, expiryDate, manufactureDate, supplierBatchRef }`. Receiving creates the batch + `PURCHASE_RECEIPT` movement atomically.

### 4.9 Stock Count

`stockCountSession { id, status: OPEN|POSTED, countedAt, userId, notes, operationId, branchId, organizationId, syncStatus }`
`stockCountEntry { id, sessionId, productId, batchId, systemQty, physicalQty, difference, reason }` — posting creates `STOCK_ADJUSTMENT` movements.

### 4.10 Notification

```json
{
  "id": "notif_001",
  "type": "EXPIRY | LOW_STOCK | OUT_OF_STOCK | RESTOCK | SYNC | SYSTEM",
  "severity": "INFO | WARNING | CRITICAL",
  "title": "Expiry Alert",
  "body": "3 products are expiring within 30 days.",
  "data": { "productId": "...", "batchId": "...", "expiryDate": "..." },
  "read": false,
  "createdAt": "...",
  "seenOnDevice": false
}
```

Deduping key = `type + productId/batchId + period(yyyy-mm)` so the same alert is not re-created every start.

### 4.11 User / Role / Permission

- `profile { id, authUserId, organizationId, branchId, role, displayName, phone, active }`
- `role { name, permissions string[] }` — server-side only.
- Permissions: `view_products, create_product, edit_product, create_sale, view_sales, adjust_stock, receive_stock, create_purchase, approve_purchase, view_reports, manage_users, manage_settings, view_stock_counts, view_expiry` … Clients may filter UI, but authorization is enforced in the database (RLS + RPC body checks).

### 4.12 Pharmacy Settings (local + cloud)

```json
{
  "pharmacyName": "Agya Appiah OTCMS",
  "address": "",
  "phone": "",
  "email": "",
  "currencyCode": "GHS",
  "currencySymbol": "₵",
  "timezone": "Africa/Accra",
  "expiryWarningDays": [7, 30, 60, 90, 180],
  "lowStockDaysBack": 14,
  "autoBackupDays": 7,
  "dataDirectory": ""
}
```

### 4.13 Sync Operation (outbox)

```json
{
  "operationId": "op_001",
  "deviceId": "device-001",
  "entityType": "SALE",          // SALE | STOCK_MOVEMENT | PURCHASE | PRODUCT | ...
  "entityId": "sale-123",
  "operationType": "CREATE",     // CREATE | UPDATE | DELETE
  "createdAt": "...",
  "status": "PENDING",           // PENDING | SYNCING | SYNCED | FAILED | CONFLICT
  "retryCount": 0,
  "lastError": null,
  "payload": { }
}
```

---

## 5. Android Local Cache (SQLite via sqflite)

Android uses a SQLite cache (`otcms.db`) with the same domain model. Tables mirror local collections: `products, categories, batches, suppliers, sales, sale_items, purchases, purchase_items, stock_movements, notifications, sync_operations, sync_state, conflicts, settings, audit_log`.

- Schema versioned (`PRAGMA user_version` + migration steps in Dart).
- Inventory/expiry/notifications are computed from cache exactly as on Windows.
- Local notifications (`flutter_local_notifications`) are scheduled/generated from cache data — fully offline.
- **Clearing app data** (or cache miss): user logs in → pull from Supabase (authorized data only) → rebuild cache → offline-capable again. Supabase is the recovery source; never Windows files.

---

## 6. Supabase PostgreSQL Schema

See `supabase/migrations/0001_init.sql` for the complete DDL. Design principles:

1. **Tenant isolation**: every tenant table carries `organization_id` (and `branch_id` where branch-scoped). RLS policies dereference the authenticated user's profile (`auth.jwt()` → `public.profiles`) — clients can send anything; the server derives `organization_id`/`branch_id` from the JWT and ignores client-supplied ones.
2. **Idempotency**: every mutable table has `operation_id TEXT UNIQUE`; sync RPCs handle duplicates with `ON CONFLICT (operation_id) DO NOTHING`.
3. **Integrity**: `products (organization_id, name)` unique; `sales.invoice_number` unique per organization; FKs with `ON DELETE RESTRICT`.
4. **Admin bootstrap**: a seed RPC (`app_bootstrap(org_name, branch_name, admin_email, admin_password, admin_display_name)`) creates the first organization and administrator — called once from the Supabase dashboard.
5. **Key tables**:
   - `organizations`, `branches`
   - `profiles` (extends `auth.users`), `roles`, `role_permissions`
   - `categories`, `products`, `suppliers`
   - `purchase_orders`, `purchase_order_items`
   - `batches`
   - `sales`, `sale_items`
   - `stock_movements`
   - `stock_count_sessions`, `stock_count_entries`
   - `notifications`
   - `audit_logs`
   - `sync_conflicts`
   - `sync_state` (device → last pull/push point, cloud-side)
6. **Sync RPCs** (security definer, org derived from JWT, payload validated):
   - `sync_sale(payload jsonb)` — creates sale + items + movements in one transaction; dedupe by `operation_id`; validates: product active, batch not expired, quantities positive, amounts match quantity×unit price, invoice number unique.
   - `sync_movement(payload jsonb)` — appends stock movement; dedupe; validates product/batch belong to org and batch has not expired for `SALE`.
   - `sync_purchase_receipt(payload jsonb)` — purchase + items + batches + `PURCHASE_RECEIPT` movements.
   - `sync_upsert(payload jsonb)` for catalog/mirror entities (products, categories, suppliers, profiles, settings, notifications, audit log).
   - `pull_changes(p_last_sync timestamptz, p_entity text)` → rows changed since point (per organization).
   - `ack_conflict(conflict_id)`, `report_conflict(...)`.
7. **No service-role key in the app.** Only anon key + `auth.signInWithPassword`. All writes flow through RLS-protected tables and definer RPCs.

---

## 7. Synchronization Engine

### Outbox (upload)

```
local mutation (sale, movement, purchase, product edit, ...)
      │ 1. applied to local store atomically (single transaction)
      │ 2. gains operationId + syncStatus=PENDING
      ▼
pending_operations (local)
      │ 3. when online AND queue non-empty:
      ▼
for each op (status=PENDING, ordered by createdAt):
      │ 4. status=SYNCING
      │ 5. POST to matching RPC with payload (never raw table UPSERT from client)
      │ 6a. response CONFLICT(already processed) → mark SYNCED (idempotent success)
      │ 6b. response VALIDATION_ERROR (e.g. batch expired server-side, invoice collision)
      │     → mark CONFLICT, write conflicts.json / sync_conflicts, notify
      │ 6c. response OK → mark SYNCED, record lastPushedAt
      ▼
next op (retry with backoff on network failure; FAILED after N attempts + manual retry)
```

### Pull (download)

```
after upload drain:
  1. push device sync_state: deviceId, lastSyncedAt
  2. for each entity in [products, categories, suppliers, batches, sales,
                        sale_items, purchases, purchase_items, stock_movements,
                        profiles, settings, notifications]:
      pull_changes(lastPulledAt) → rows; upsert into local store
  3. advance lastPulledAt to now
  4. mark device SYNCED; UI: ONLINE — SYNCED
```

- Only records changed **after** `lastPulledAt` are transferred (`updated_at` column maintained by trigger on every change).
- `lastPulledAt` is stored per device locally and mirrored in cloud `sync_state` (enables cache rebuild after app data clear).
- Sync binds to connectivity events (connectivity_plus) + retry timer + manual "Sync now" button. Debounced.

### Conflict semantics

- Inventory conflicts are impossible at the data level because only movements synchronize: `100 - 10 - 20 = 70` emerges naturally on every device that receives both movements.
- True business conflicts (e.g., two stock counts adjusting the same batch, price edited on two devices) are written to `conflicts` and reviewed in the Conflicts screen; nothing is silently overwritten (see `sync_conflicts` + RLS).
- Notifications/alerts are pure local derivations — never synced as facts (except system notifications mirrored to cloud).

---

## 8. Security Model

1. **Auth**: Supabase `signInWithPassword` (email+password). Session persisted; refresh handled by supabase_flutter.
2. **RLS everything**: every tenant table has `FORCE ROW LEVEL SECURITY`; policies use `auth.uid()` → `profiles` → `organization_id`/`branch_id`/`role`. Zero trust of client-supplied org/branch/role.
3. **Definer RPCs** validate payload shape, amounts (integer pesewas, exact math), ownership (product/batch belongs to org), and expiry rules before writing.
4. **Secrets**: anon URL/key enter the app via `--dart-define` or a local `secrets` file that is git-ignored; GitHub Actions receives them from repository secrets to stamp build config. Service-role key exists only in the Supabase dashboard (and locally if the owner exports it for migrations — never committed).
5. **Local**: no passwords stored in JSON; only the auth session. Device id is a random UUID. Audit log records user/device/action/entity/timestamp/before-after.
6. **Validation**: domain-level `Result` errors — product exists & active, batch valid & not expired, qty > 0, price valid, total recomputed, invoice number unique, operation id unique.

---

## 9. Business Services (shared logic)

- `InventoryService` — movement application, derived stock per product/batch, FEFO batch selection (earliest valid expiry first, expired excluded), stock statuses: HEALTHY / LOW STOCK / CRITICAL / OUT OF STOCK.
- `ExpiryService` — buckets: EXPIRED / ≤7d / ≤30d / ≤60d / ≤90d / ≤180d / SAFE (thresholds configurable); value-at-risk and days-remaining/velocity estimates.
- `AlertService` — low stock, getting-finished, stockout prediction (avg daily sales from sales history), restock recommendations (current, reorder level, target, avg sales, lead-time, pack size, expiry risk) — recommendations are never auto-purchased.
- `SalesService` — cart → validate → FEFO allocate → apply movements → create sale + items + invoice number → compute total (integer math) → commit locally → queue for sync → immediately usable invoice.
- `DailySalesService` — totals by day/week/month/custom range, transactions, units, average transaction — always computed from local committed sales.
- `NotificationService` — builds/dedupes notifications on local changes; Android posts local notifications (flutter_local_notifications) honoring configured lead days; no spam (state tracked per notification key).
- `AuditService` — SALE_CREATED, PRODUCT_CREATED, STOCK_ADJUSTED, SYNC_STARTED/COMPLETED/FAILED, USER_LOGIN, ...
- `BackupService` — snapshot to `backups/`, retention 30, restore-preview.
- `SyncService` — orchestrates outbox + pull + connectivity UI state (ONLINE — SYNCED / OFFLINE — WORKING LOCALLY / SYNCING… / N CHANGES PENDING / SYNC ERROR — LOCAL DATA SAFE).

---

## 10. UI

- **Desktop (Windows)**: `NavigationRail` (Dashboard, Sales, Products, Inventory, Batches, Expiry, Purchases, Suppliers, Stock Count, Reports, Notifications, Users, Settings), DataTables with keyboard search, side panels for detail, receipt-print-ready invoice view (printing architecture in place for future drivers).
- **Mobile (Android)**: `NavigationBar` — Home, Sell, Products, Inventory, Notifications (+ More). Touch-first: large tiles, big prices, fast search / barcode scan field, tappable alert cards. **Not** a scaled desktop UI.
- **Dashboard** (both): Today's Sales, Transactions, Units Sold, Avg Transaction, Inventory Value, Low Stock, Out of Stock, Expiring Soon, Expired, Products Getting Finished, Expiry Alerts, Top Selling Products, Daily Business Summary chips. Every card is tappable and updates instantly on local commits.
- Shared widgets: `SalesScreen`, `CartSheet`, `InvoiceView`, `ProductSearch` adapted per platform.
- Connectivity banner persistent: ONLINE / OFFLINE / SYNCING / N PENDING / ERROR(local safe).

---

## 11. Key Flows

### Sale (critical path)
```
search/scan → add to cart (qty) → TOTAL shown (computed) → SUBMIT SALE
→ validate stock+FEFO+expiry → movements + sale persisted locally (syncStatus=PENDING)
→ invoice IMMEDIATELY (offline OK) → totals/dashboard refreshed locally
→ connectivity returns → outbox push (idempotent) → pull → SYNCED
```
Never: wait for the network, lose the sale, expose edit of totals.

### Expiry alert
expiry <= threshold & > today → EXPIRING SOON (orange) / <=90d (yellow) / expired (red) —
dashboard count, click-through detail (product, batch, qty, expiry, days left, price, supplier),
Android local notification per configured lead days, deduped per key, works offline.

### First run / import
First run: set up settings (Agya Appiah OTCMS defaults) → Import Products (`data/products_master.json` shipped in repo; or user file picker) → names/prices preserved exactly → optionally create opening stock via Stock Count/batches later.

---

## 12. Data Flow Diagrams

### Offline sale (both platforms)

```
Seller → [Sales UI] → SalesService
        → validate (stock, expiry, qty, price)
        → FEFO allocate batches
        → apply StockMovements (local)
        → persist Sale + SaleItems (local, PENDING)
        → generate invoice → show immediately
        → enqueue Sale + Movement ops in outbox
        → recompute dashboard/alerts locally
   [OFFLINE: everything above works; syncStatus=PENDING]
   [ONLINE: SyncEngine drains outbox → RPC → SYNCED]
```

### Sync (after reconnect)

```
Connectivity ONLINE
  → push outbox (per entity RPC, dedupe by operation_id)
  → advance device sync point (push + pull timestamps in cloud sync_state)
  → pull_changes(since) per entity → upsert local store
  → mark SYNCED; alarms recompute locally
```

### Stock receipt

```
Purchase (DRAFT) → order → receive (goods in: qty, batch#, expiry, cost)
→ create batches + PURCHASE_RECEIPT movements + purchase items (atomic, local)
→ queue ops → sync idempotently (server re-validates org + expiry + amounts)
```

---

## 13. Implementation Phases

| Phase | Scope | Done when |
|---|---|---|
| 0 | Repo, CI, scaffold, architecture | Green CI (analyze, test, APK, Windows zip) |
| 1 | Core: Money/ids/time, JSON store (atomic), settings, auth wiring, products + catalog import | unit tests + manual import of 4,071 products |
| 2 | Inventory: batches, movements, FEFO, expiry buckets, low-stock, alerts (logic) | critical expiry/low-stock tests pass |
| 3 | Sales: cart, FEFO sale, invoice, daily sales, seller binding | critical sales test passes |
| 4 | Android: sqflite cache, offline sales, local notifications, offline dashboard | critical offline + Android cache tests |
| 5 | Sync: outbox, RPC push, incremental pull, idempotency, conflicts | critical offline→online test; no duplicates |
| 6 | Purchases, suppliers, goods receiving, stock count | receiving creates batches/movements consistently |
| 7 | Reports, BI, restock recommendations, expiry intelligence | report screens with real data |
| 8 | Permissions, branches, audit, backup/restore, advanced reports | RLS-ready; audit trail complete |

**Hard rule**: a feature is complete only when DB + business logic + local storage + offline behavior + online behavior + sync + validation + security + tests all work. The pharmacy must never lose a completed sale because the Internet is unavailable.