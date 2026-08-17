-- ============================================================================
-- OTCMS — Pharmacy Management System
-- Supabase PostgreSQL schema (migration 0001)
--
-- Run this file in: Supabase Dashboard → SQL Editor → New query → paste → Run
-- Then run:  select app_bootstrap(...)  (see bottom / docs/SETUP.md)
--
-- Principles:
--   * Row Level Security everywhere (FORCE RLS). Tenant = organization.
--   * organization_id / branch_id are NEVER trusted from the client.
--     They are derived inside RLS policies and SECURITY DEFINER functions
--     from the authenticated user's profile (auth.jwt() -> profiles).
--   * Idempotency: every synced entity carries a globally unique
--     operation_id; replayed operations return "duplicate".
--   * Money is stored as integer minor units (pesewas): price_pesewas.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helpers (request-context)
-- ---------------------------------------------------------------------------

create or replace function public.app_my_profile() returns public.profiles
language sql stable security definer set search_path = public
as $$
  select p.* from public.profiles p where p.auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.app_my_role() returns text
language sql stable security definer set search_path = public
as $$
  select (select role from public.profiles where auth_user_id = auth.uid() limit 1);
$$;

create or replace function public.app_has_permission(p_perm text) returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_role text;
begin
  select role into v_role from public.profiles where auth_user_id = auth.uid() limit 1;
  if v_role is null then return false; end if;
  if v_role = 'SUPER_ADMIN' then return true; end if;
  return exists (
    select 1 from public.role_permissions rp
    where rp.role_name = v_role and rp.permission = p_perm
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Organizations / branches
-- ---------------------------------------------------------------------------

create table if not exists public.organizations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.branches (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name            text not null,
  address         text,
  phone           text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, name)
);

-- ---------------------------------------------------------------------------
-- Roles & permissions
-- ---------------------------------------------------------------------------

create table if not exists public.roles (
  name        text primary key,
  description text
);

create table if not exists public.role_permissions (
  role_name   text not null references public.roles(name) on delete cascade,
  permission  text not null,
  primary key (role_name, permission)
);

insert into public.roles(name, description) values
  ('SUPER_ADMIN', 'Full system administration'),
  ('OWNER',       'Pharmacy owner'),
  ('ADMIN',       'Pharmacy administrator'),
  ('PHARMACIST',  'Pharmacist'),
  ('INVENTORY_MANAGER', 'Inventory management'),
  ('CASHIER',     'Cashier / sales'),
  ('STAFF',       'General staff')
on conflict (name) do nothing;

insert into public.role_permissions(role_name, permission) values
  ('ADMIN', 'view_products'), ('ADMIN', 'create_product'), ('ADMIN', 'edit_product'),
  ('ADMIN', 'create_sale'), ('ADMIN', 'view_sales'), ('ADMIN', 'adjust_stock'),
  ('ADMIN', 'receive_stock'), ('ADMIN', 'create_purchase'), ('ADMIN', 'approve_purchase'),
  ('ADMIN', 'view_reports'), ('ADMIN', 'manage_users'), ('ADMIN', 'manage_settings'),
  ('ADMIN', 'view_stock_counts'), ('ADMIN', 'view_expiry'),
  ('PHARMACIST', 'view_products'), ('PHARMACIST', 'create_product'), ('PHARMACIST', 'edit_product'),
  ('PHARMACIST', 'create_sale'), ('PHARMACIST', 'view_sales'), ('PHARMACIST', 'adjust_stock'),
  ('PHARMACIST', 'receive_stock'), ('PHARMACIST', 'create_purchase'), ('PHARMACIST', 'view_reports'),
  ('PHARMACIST', 'view_stock_counts'), ('PHARMACIST', 'view_expiry'),
  ('INVENTORY_MANAGER', 'view_products'), ('INVENTORY_MANAGER', 'create_product'),
  ('INVENTORY_MANAGER', 'edit_product'), ('INVENTORY_MANAGER', 'view_sales'),
  ('INVENTORY_MANAGER', 'adjust_stock'), ('INVENTORY_MANAGER', 'receive_stock'),
  ('INVENTORY_MANAGER', 'create_purchase'), ('INVENTORY_MANAGER', 'approve_purchase'),
  ('INVENTORY_MANAGER', 'view_stock_counts'), ('INVENTORY_MANAGER', 'view_expiry'),
  ('CASHIER', 'view_products'), ('CASHIER', 'create_sale'), ('CASHIER', 'view_sales'),
  ('STAFF', 'view_products'), ('STAFF', 'create_sale')
on conflict (role_name, permission) do nothing;

-- ---------------------------------------------------------------------------
-- Profiles (extends auth.users)
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id              uuid primary key default gen_random_uuid(),
  auth_user_id    uuid not null unique references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  role            text not null default 'STAFF' references public.roles(name),
  display_name    text not null,
  phone           text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Catalog
-- ---------------------------------------------------------------------------

create table if not exists public.categories (
  id              text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name            text not null,
  description     text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, name)
);

create table if not exists public.products (
  id                text primary key,
  organization_id   uuid not null references public.organizations(id) on delete cascade,
  branch_id         uuid references public.branches(id) on delete set null,
  name              text not null,
  generic_name      text,
  brand_name        text,
  category_id       text references public.categories(id),
  dosage_form       text,
  strength          text,
  pack_size         text,
  barcode           text,
  sku               text,
  manufacturer      text,
  responsible       text,
  selling_price_pesewas integer not null default 0 check (selling_price_pesewas >= 0),
  cost_price_pesewas    integer check (cost_price_pesewas >= 0),
  reorder_level     integer not null default 10,
  minimum_stock     integer not null default 5,
  target_stock      integer not null default 50,
  reorder_quantity  integer not null default 20,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (organization_id, name)
);

create index if not exists idx_products_org_name on public.products(organization_id, lower(name));
create index if not exists idx_products_barcode on public.products(organization_id, barcode);
create index if not exists idx_products_sku on public.products(organization_id, sku);

create table if not exists public.suppliers (
  id              text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  name            text not null,
  phone           text,
  address         text,
  email           text,
  contact_person  text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, name)
);

-- ---------------------------------------------------------------------------
-- Batches (expiry + stock lots)
-- ---------------------------------------------------------------------------

create table if not exists public.batches (
  id              text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  product_id      text not null references public.products(id),
  batch_number    text not null,
  expiry_date     date,
  manufacture_date date,
  quantity        integer not null default 0 check (quantity >= 0),
  cost_price_pesewas   integer check (cost_price_pesewas >= 0),
  selling_price_pesewas integer check (selling_price_pesewas >= 0),
  supplier_id     text references public.suppliers(id),
  received_at     timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, batch_number)
);

create index if not exists idx_batches_product on public.batches(organization_id, product_id);
create index if not exists idx_batches_expiry on public.batches(organization_id, expiry_date);

-- ---------------------------------------------------------------------------
-- Purchases
-- ---------------------------------------------------------------------------

create table if not exists public.purchase_orders (
  id              text primary key,
  operation_id    text not null unique,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  supplier_id     text references public.suppliers(id),
  purchase_number text not null,
  status          text not null default 'DRAFT'
                    check (status in ('DRAFT','ORDERED','RECEIVED','CANCELLED')),
  total_cost_pesewas integer not null default 0,
  received_at     timestamptz,
  user_id         uuid not null references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, purchase_number)
);

create table if not exists public.purchase_order_items (
  id               text primary key,
  purchase_id      text not null references public.purchase_orders(id) on delete cascade,
  product_id       text not null references public.products(id),
  quantity         integer not null check (quantity > 0),
  cost_price_pesewas integer not null check (cost_price_pesewas >= 0),
  batch_number     text,
  expiry_date      date,
  manufacture_date date,
  created_at       timestamptz not null default now()
);

create index if not exists idx_poi_purchase on public.purchase_order_items(purchase_id);

-- ---------------------------------------------------------------------------
-- Sales
-- ---------------------------------------------------------------------------

create table if not exists public.sales (
  id                  text primary key,
  operation_id        text not null unique,
  organization_id     uuid not null references public.organizations(id) on delete cascade,
  branch_id           uuid references public.branches(id) on delete set null,
  invoice_number      text not null,
  user_id             uuid not null references auth.users(id),
  seller_name         text not null,
  device_id           text not null,
  sale_date           date not null,
  sale_time           time not null,
  created_at          timestamptz not null default now(),
  total_amount_pesewas integer not null check (total_amount_pesewas >= 0),
  unique (organization_id, invoice_number)
);

create index if not exists idx_sales_date on public.sales(organization_id, sale_date);
create index if not exists idx_sales_user on public.sales(organization_id, user_id);

create table if not exists public.sale_items (
  id                  text primary key,
  sale_id             text not null references public.sales(id) on delete cascade,
  product_id          text not null references public.products(id),
  batch_id            text references public.batches(id),
  medicine_name       text not null,
  quantity            integer not null check (quantity > 0),
  unit_price_pesewas  integer not null check (unit_price_pesewas >= 0),
  amount_pesewas      integer not null check (amount_pesewas >= 0),
  created_at          timestamptz not null default now()
);

create index if not exists idx_sale_items_sale on public.sale_items(sale_id);
create index if not exists idx_sale_items_product on public.sale_items(product_id);

-- ---------------------------------------------------------------------------
-- Stock movements — the transactional inventory truth
-- ---------------------------------------------------------------------------

create table if not exists public.stock_movements (
  id              text primary key,
  operation_id    text not null unique,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  product_id      text not null references public.products(id),
  batch_id        text references public.batches(id),
  quantity        integer not null check (quantity > 0),
  movement_type   text not null check (movement_type in (
                    'OPENING_BALANCE','PURCHASE_RECEIPT','SALE','SALE_RETURN',
                    'PURCHASE_RETURN','STOCK_ADJUSTMENT','DAMAGE','EXPIRED',
                    'TRANSFER_IN','TRANSFER_OUT')),
  direction       integer not null check (direction in (-1, 1)),
  reference_id    text,
  reason          text,
  user_id         uuid not null references auth.users(id),
  created_at      timestamptz not null default now()
);

create index if not exists idx_movements_product on public.stock_movements(organization_id, product_id);
create index if not exists idx_movements_batch on public.stock_movements(organization_id, batch_id);
create index if not exists idx_movements_created on public.stock_movements(organization_id, created_at);

-- ---------------------------------------------------------------------------
-- Stock count
-- ---------------------------------------------------------------------------

create table if not exists public.stock_count_sessions (
  id              text primary key,
  operation_id    text not null unique,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  status          text not null default 'OPEN' check (status in ('OPEN','POSTED','CANCELLED')),
  notes           text,
  user_id         uuid not null references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists public.stock_count_entries (
  id              text primary key,
  session_id      text not null references public.stock_count_sessions(id) on delete cascade,
  product_id      text not null references public.products(id),
  batch_id        text references public.batches(id),
  system_qty      integer not null default 0,
  physical_qty    integer not null default 0,
  difference      integer not null default 0,
  reason          text,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Notifications (system mirrors; local alerts are derived locally)
-- ---------------------------------------------------------------------------

create table if not exists public.notifications (
  id              text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  type            text not null,
  severity        text not null default 'INFO',
  title           text not null,
  body            text,
  data            jsonb,
  read            boolean not null default false,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

create table if not exists public.audit_logs (
  id              text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid references auth.users(id),
  device_id       text,
  action          text not null,
  entity          text,
  entity_id       text,
  before          jsonb,
  after           jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists idx_audit_org on public.audit_logs(organization_id, created_at);

-- ---------------------------------------------------------------------------
-- Sync bookkeeping
-- ---------------------------------------------------------------------------

create table if not exists public.sync_state (
  device_id       text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid not null references auth.users(id),
  last_pushed_at  timestamptz,
  last_pulled_at  timestamptz,
  updated_at      timestamptz not null default now()
);

create table if not exists public.sync_conflicts (
  id              text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  operation_id    text,
  entity_type     text,
  entity_id       text,
  reason          text not null,
  payload         jsonb,
  status          text not null default 'OPEN' check (status in ('OPEN','ACKNOWLEDGED','RESOLVED')),
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz
);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create or replace function public.tg_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_org_updated  before update on public.organizations for each row execute function public.tg_set_updated_at();
create trigger trg_branch_updated before update on public.branches for each row execute function public.tg_set_updated_at();
create trigger trg_profile_updated before update on public.profiles for each row execute function public.tg_set_updated_at();
create trigger trg_cat_updated before update on public.categories for each row execute function public.tg_set_updated_at();
create trigger trg_prod_updated before update on public.products for each row execute function public.tg_set_updated_at();
create trigger trg_sup_updated before update on public.suppliers for each row execute function public.tg_set_updated_at();
create trigger trg_batch_updated before update on public.batches for each row execute function public.tg_set_updated_at();
create trigger trg_po_updated before update on public.purchase_orders for each row execute function public.tg_set_updated_at();
create trigger trg_sc_updated before update on public.stock_count_sessions for each row execute function public.tg_set_updated_at();

-- ===========================================================================
-- ROW LEVEL SECURITY
-- ===========================================================================

alter table public.organizations        force row level security;
alter table public.branches             force row level security;
alter table public.profiles             force row level security;
alter table public.categories           force row level security;
alter table public.products             force row level security;
alter table public.suppliers            force row level security;
alter table public.batches              force row level security;
alter table public.purchase_orders      force row level security;
alter table public.purchase_order_items force row level security;
alter table public.sales                force row level security;
alter table public.sale_items           force row level security;
alter table public.stock_movements      force row level security;
alter table public.stock_count_sessions force row level security;
alter table public.stock_count_entries  force row level security;
alter table public.notifications        force row level security;
alter table public.audit_logs           force row level security;
alter table public.sync_state           force row level security;
alter table public.sync_conflicts       force row level security;

-- organizations: members see their own; only SUPER_ADMIN/OWNER may update
create policy org_select on public.organizations
  for select using (id = (select organization_id from public.app_my_profile()));
create policy org_update on public.organizations
  for update using (app_has_permission('manage_settings'));

-- branches
create policy branch_select on public.branches
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy branch_insert on public.branches
  for insert with check (organization_id = (select organization_id from public.app_my_profile())
                         and app_has_permission('manage_settings'));
create policy branch_update on public.branches
  for update using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('manage_settings'));
create policy branch_delete on public.branches
  for delete using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('manage_settings'));

-- profiles: view org members; update self or (admins update org)
create policy profile_select on public.profiles
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy profile_insert on public.profiles
  for insert with check (organization_id = (select organization_id from public.app_my_profile())
                         and app_has_permission('manage_users'));
create policy profile_update on public.profiles
  for update using ((auth_user_id = auth.uid())
                    or (organization_id = (select organization_id from public.app_my_profile())
                        and app_has_permission('manage_users')));
create policy profile_delete on public.profiles
  for delete using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('manage_users'));

-- catalog (categories / products / suppliers)
create policy cat_select on public.categories
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy cat_insert on public.categories
  for insert with check (organization_id = (select organization_id from public.app_my_profile())
                         and app_has_permission('create_product'));
create policy cat_update on public.categories
  for update using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('edit_product'));
create policy cat_delete on public.categories
  for delete using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('edit_product'));

create policy prod_select on public.products
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy prod_insert on public.products
  for insert with check (organization_id = (select organization_id from public.app_my_profile())
                         and app_has_permission('create_product'));
create policy prod_update on public.products
  for update using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('edit_product'));
create policy prod_delete on public.products
  for delete using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('edit_product'));

create policy sup_select on public.suppliers
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy sup_insert on public.suppliers
  for insert with check (organization_id = (select organization_id from public.app_my_profile())
                         and app_has_permission('create_purchase'));
create policy sup_update on public.suppliers
  for update using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('create_purchase'));
create policy sup_delete on public.suppliers
  for delete using (organization_id = (select organization_id from public.app_my_profile())
                    and app_has_permission('create_purchase'));

-- batches: read for org; writes only via definer RPCs (no direct policies)
create policy batch_select on public.batches
  for select using (organization_id = (select organization_id from public.app_my_profile()));

-- purchases: read; writes via RPC
create policy po_select on public.purchase_orders
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy poi_select on public.purchase_order_items
  for select using (purchase_id in (select id from public.purchase_orders
                                    where organization_id = (select organization_id from public.app_my_profile())));

-- sales / sale items: read for org; writes via RPC
create policy sale_select on public.sales
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy si_select on public.sale_items
  for select using (sale_id in (select id from public.sales
                                where organization_id = (select organization_id from public.app_my_profile())));

-- movements: read; writes via RPC
create policy mov_select on public.stock_movements
  for select using (organization_id = (select organization_id from public.app_my_profile()));

-- stock counts: read; writes via RPC
create policy sc_select on public.stock_count_sessions
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy sce_select on public.stock_count_entries
  for select using (session_id in (select id from public.stock_count_sessions
                                   where organization_id = (select organization_id from public.app_my_profile())));

-- notifications: read/insert own org; update own reads
create policy notif_select on public.notifications
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy notif_insert on public.notifications
  for insert with check (organization_id = (select organization_id from public.app_my_profile()));
create policy notif_update on public.notifications
  for update using (organization_id = (select organization_id from public.app_my_profile()));

-- audit: read/insert own org
create policy audit_select on public.audit_logs
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy audit_insert on public.audit_logs
  for insert with check (organization_id = (select organization_id from public.app_my_profile()));

-- sync bookkeeping
create policy sync_state_select on public.sync_state
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy sync_state_all on public.sync_state
  for all using (organization_id = (select organization_id from public.app_my_profile()))
  with check (organization_id = (select organization_id from public.app_my_profile()));

create policy conflict_select on public.sync_conflicts
  for select using (organization_id = (select organization_id from public.app_my_profile()));
create policy conflict_insert on public.sync_conflicts
  for insert with check (organization_id = (select organization_id from public.app_my_profile()));
create policy conflict_update on public.sync_conflicts
  for update using (organization_id = (select organization_id from public.app_my_profile()));

-- ===========================================================================
-- SYNCHRONIZATION RPCs (SECURITY DEFINER — server-side authority)
-- ===========================================================================

-- Resolve the effective branch: payload branch if it belongs to my org,
-- otherwise my profile's branch.
create or replace function public.resolved_branch_id(p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path = public
as $$
declare
  v_org uuid;
  v_default uuid;
begin
  select organization_id, branch_id into v_org, v_default
  from public.profiles where auth_user_id = auth.uid();
  if p_branch_id is null then
    return v_default;
  end if;
  if exists (select 1 from public.branches b
             where b.id = p_branch_id and b.organization_id = v_org) then
    return p_branch_id;
  end if;
  raise exception 'branch not authorized';
end;
$$;

-- ---------------------------------------------------------------------------
-- sync_sale: create sale + items + movements atomically (idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.sync_sale(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org      uuid;
  v_branch   uuid;
  v_user     uuid;
  v_seller   text;
  v_op       text;
  v_inv      text;
  v_sale_id  text;
  v_item     jsonb;
  v_prod     record;
  v_batch    record;
  v_total    bigint := 0;
  v_dir      integer;
  v_mov_id   text;
  v_item_id  text;
  v_created  timestamptz;
  v_sale_date date;
  v_sale_time time;
begin
  select organization_id, branch_id, auth_user_id, display_name
    into v_org, v_branch, v_user, v_seller
  from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;

  v_op := p_payload ->> 'operationId';
  v_inv := p_payload ->> 'invoiceNumber';
  v_sale_id := coalesce(p_payload ->> 'id', 'sale_' || gen_random_uuid()::text);
  v_created := coalesce((p_payload ->> 'createdAt')::timestamptz, now());
  v_sale_date := coalesce((p_payload ->> 'date')::date, v_created::date);
  v_sale_time := coalesce((p_payload ->> 'time')::time, v_created::time);

  if v_op is null or v_inv is null then
    return jsonb_build_object('status','ERROR','message','operationId and invoiceNumber required');
  end if;

  -- idempotency
  if exists (select 1 from public.sales where operation_id = v_op) then
    return jsonb_build_object('status','DUPLICATE','saleId', v_sale_id);
  end if;
  if exists (select 1 from public.sales s where s.organization_id = v_org and s.invoice_number = v_inv) then
    return jsonb_build_object('status','INVOICE_COLLISION','invoiceNumber', v_inv);
  end if;

  v_branch := public.resolved_branch_id((p_payload ->> 'branchId')::uuid);

  -- validate items & compute total
  for v_item in select * from jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb)) loop
    v_item_id := v_item ->> 'id';
    if v_item ->> 'quantity' is null
       or (v_item ->> 'quantity')::int <= 0
       or v_item ->> 'unitPricePesewas' is null
       or (v_item ->> 'unitPricePesewas')::bigint < 0 then
      return jsonb_build_object('status','ERROR','message','invalid item data');
    end if;
    if (v_item -> 'amountPesewas')::bigint <>
       (v_item ->> 'quantity')::bigint * (v_item ->> 'unitPricePesewas')::bigint then
      return jsonb_build_object('status','ERROR','message','amount mismatch');
    end if;

    select * into v_prod from public.products
      where id = v_item ->> 'productId' and organization_id = v_org;
    if v_prod.id is null or v_prod.active is not true then
      return jsonb_build_object('status','ERROR','message','product inactive or unknown');
    end if;

    select * into v_batch from public.batches
      where id = v_item ->> 'batchId' and product_id = v_prod.id and organization_id = v_org;
    if v_batch.id is null then
      return jsonb_build_object('status','ERROR','message','batch unknown');
    end if;
    if v_batch.expiry_date is not null and v_batch.expiry_date < current_date then
      return jsonb_build_object('status','ERROR','message','batch expired');
    end if;
    if (v_batch.quantity - (v_item ->> 'quantity')::int) < 0 then
      return jsonb_build_object('status','ERROR','message','insufficient stock');
    end if;

    v_total := v_total + (v_item ->> 'amountPesewas')::bigint;
  end loop;

  if (p_payload ->> 'totalAmountPesewas')::bigint <> v_total then
    return jsonb_build_object('status','ERROR','message','total mismatch');
  end if;

  -- persist
  insert into public.sales (id, operation_id, organization_id, branch_id, invoice_number,
                            user_id, seller_name, device_id, sale_date, sale_time,
                            created_at, total_amount_pesewas)
  values (v_sale_id, v_op, v_org, v_branch, v_inv, v_user, v_seller,
          coalesce(p_payload ->> 'deviceId','unknown'), v_sale_date, v_sale_time,
          v_created, v_total);

  for v_item in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.sale_items (id, sale_id, product_id, batch_id, medicine_name,
                                   quantity, unit_price_pesewas, amount_pesewas)
    values (coalesce(v_item ->> 'id', 'si_' || gen_random_uuid()::text),
            v_sale_id,
            v_item ->> 'productId',
            v_item ->> 'batchId',
            coalesce(v_item ->> 'medicineName', ''),
            (v_item ->> 'quantity')::int,
            (v_item ->> 'unitPricePesewas')::bigint,
            (v_item ->> 'amountPesewas')::bigint);

    -- SALE movements are direction -1
    v_mov_id := 'mov_' || gen_random_uuid()::text;
    insert into public.stock_movements (id, operation_id, organization_id, branch_id,
                                        product_id, batch_id, quantity, movement_type,
                                        direction, reference_id, user_id, created_at)
    values (v_mov_id, 'opx_' || gen_random_uuid()::text, v_org, v_branch,
            v_item ->> 'productId', v_item ->> 'batchId',
            (v_item ->> 'quantity')::int, 'SALE', -1, v_sale_id, v_user, v_created);

    update public.batches
      set quantity = quantity - (v_item ->> 'quantity')::int, updated_at = now()
      where id = v_item ->> 'batchId';
  end loop;

  insert into public.audit_logs (id, organization_id, user_id, device_id, action, entity, entity_id, after)
  values ('aud_' || gen_random_uuid()::text, v_org, v_user, p_payload ->> 'deviceId',
          'SALE_CREATED', 'sale', v_sale_id, p_payload);

  return jsonb_build_object('status','OK','saleId', v_sale_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- sync_movement: append a stock movement (idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.sync_movement(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org    uuid;
  v_branch uuid;
  v_user   uuid;
  v_op     text;
  v_type   text;
  v_dir    integer;
  v_qty    integer;
  v_prod   record;
  v_batch  record;
  v_mov_id text;
  v_created timestamptz;
begin
  select organization_id, branch_id, auth_user_id into v_org, v_branch, v_user
  from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;

  v_op := p_payload ->> 'operationId';
  v_type := p_payload ->> 'movementType';
  v_qty := (p_payload ->> 'quantity')::int;
  v_created := coalesce((p_payload ->> 'createdAt')::timestamptz, now());

  if exists (select 1 from public.stock_movements where operation_id = v_op) then
    return jsonb_build_object('status','DUPLICATE','movementId', p_payload ->> 'id');
  end if;

  select * into v_prod from public.products
    where id = p_payload ->> 'productId' and organization_id = v_org;
  if v_prod.id is null then
    return jsonb_build_object('status','ERROR','message','product unknown');
  end if;
  select * into v_batch from public.batches
    where id = p_payload ->> 'batchId' and product_id = v_prod.id and organization_id = v_org;
  if v_batch.id is null then
    return jsonb_build_object('status','ERROR','message','batch unknown');
  end if;
  if v_type = 'SALE' and v_batch.expiry_date is not null and v_batch.expiry_date < current_date then
    return jsonb_build_object('status','ERROR','message','batch expired');
  end if;

  v_dir := case when v_type in ('SALE','PURCHASE_RETURN','DAMAGE','EXPIRED','TRANSFER_OUT')
                then -1 else 1 end;
  -- negative adjustments flip direction
  if v_type = 'STOCK_ADJUSTMENT' and (p_payload ->> 'direction')::int < 0 then
    v_dir := -1;
  end if;

  v_mov_id := p_payload ->> 'id';
  if v_mov_id is null then v_mov_id := 'mov_' || gen_random_uuid()::text; end if;

  insert into public.stock_movements (id, operation_id, organization_id, branch_id,
                                      product_id, batch_id, quantity, movement_type,
                                      direction, reference_id, reason, user_id, created_at)
  values (v_mov_id, v_op, v_org, v_branch,
          v_prod.id, v_batch.id, v_qty, v_type, v_dir,
          p_payload ->> 'referenceId', p_payload ->> 'reason', v_user, v_created);

  if v_dir = 1 then
    update public.batches set quantity = quantity + v_qty, updated_at = now()
      where id = v_batch.id;
  else
    update public.batches
      set quantity = greatest(0, quantity - v_qty), updated_at = now()
      where id = v_batch.id;
  end if;

  insert into public.audit_logs (id, organization_id, user_id, device_id, action, entity, entity_id, after)
  values ('aud_' || gen_random_uuid()::text, v_org, v_user, p_payload ->> 'deviceId',
          'MOVEMENT_' || v_type, 'stock_movement', v_mov_id, p_payload);

  return jsonb_build_object('status','OK','movementId', v_mov_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- sync_purchase_receipt: purchase + items + batches + movements (idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.sync_purchase_receipt(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org    uuid;
  v_branch uuid;
  v_user   uuid;
  v_op     text;
  v_po_id  text;
  v_item   jsonb;
  v_prod   uuid;
  v_batch_id text;
  v_created timestamptz;
  v_total  bigint := 0;
begin
  select organization_id, branch_id, auth_user_id into v_org, v_branch, v_user
  from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;

  v_op := p_payload ->> 'operationId';
  v_po_id := coalesce(p_payload ->> 'id', 'pur_' || gen_random_uuid()::text);
  v_created := coalesce((p_payload ->> 'receivedAt')::timestamptz, now());

  if exists (select 1 from public.purchase_orders where operation_id = v_op) then
    return jsonb_build_object('status','DUPLICATE','purchaseId', v_po_id);
  end if;

  v_branch := public.resolved_branch_id((p_payload ->> 'branchId')::uuid);

  for v_item in select * from jsonb_array_elements(p_payload -> 'items') loop
    if not exists (select 1 from public.products
                   where id = v_item ->> 'productId' and organization_id = v_org) then
      return jsonb_build_object('status','ERROR','message','product unknown');
    end if;
    if v_item->>'batchId' is null or v_item->>'batchNumber' is null then
      return jsonb_build_object('status','ERROR','message','batch info required');
    end if;
    v_total := v_total + (v_item ->> 'costPricePesewas')::bigint * (v_item ->> 'quantity')::int;
  end loop;
  if (p_payload ->> 'totalCostPesewas')::bigint <> v_total then
    return jsonb_build_object('status','ERROR','message','total mismatch');
  end if;

  insert into public.purchase_orders (id, operation_id, organization_id, branch_id,
    supplier_id, purchase_number, status, total_cost_pesewas, received_at, user_id, created_at)
  values (v_po_id, v_op, v_org, v_branch, p_payload ->> 'supplierId',
          p_payload ->> 'purchaseNumber', 'RECEIVED', v_total, v_created, v_user, v_created);

  for v_item in select * from jsonb_array_elements(p_payload -> 'items') loop
    insert into public.purchase_order_items (id, purchase_id, product_id, quantity,
      cost_price_pesewas, batch_number, expiry_date, manufacture_date, created_at)
    values (coalesce(v_item ->> 'purchaseItemId', 'poi_' || gen_random_uuid()::text),
            v_po_id, v_item ->> 'productId', (v_item ->> 'quantity')::int,
            (v_item ->> 'costPricePesewas')::bigint,
            v_item ->> 'batchNumber', (v_item ->> 'expiryDate')::date,
            (v_item ->> 'manufactureDate')::date, v_created);

    v_batch_id := v_item ->> 'batchId';
    insert into public.batches (id, organization_id, branch_id, product_id, batch_number,
      expiry_date, manufacture_date, quantity, cost_price_pesewas, selling_price_pesewas,
      supplier_id, received_at, created_at)
    values (v_batch_id, v_org, v_branch, v_item ->> 'productId', v_item ->> 'batchNumber',
      (v_item ->> 'expiryDate')::date, (v_item ->> 'manufactureDate')::date,
      (v_item ->> 'quantity')::int, (v_item ->> 'costPricePesewas')::bigint,
      (v_item ->> 'sellingPricePesewas')::bigint, p_payload ->> 'supplierId', v_created, v_created)
    on conflict (id) do update set quantity = batches.quantity + excluded.quantity, updated_at = now();

    insert into public.stock_movements (id, operation_id, organization_id, branch_id,
      product_id, batch_id, quantity, movement_type, direction, reference_id, user_id, created_at)
    values ('mov_' || gen_random_uuid()::text, 'opx_' || gen_random_uuid()::text,
            v_org, v_branch, v_item ->> 'productId', v_batch_id,
            (v_item ->> 'quantity')::int, 'PURCHASE_RECEIPT', 1, v_po_id, v_user, v_created);
  end loop;

  insert into public.audit_logs (id, organization_id, user_id, device_id, action, entity, entity_id, after)
  values ('aud_' || gen_random_uuid()::text, v_org, v_user, p_payload ->> 'deviceId',
          'STOCK_RECEIVED', 'purchase', v_po_id, p_payload);

  return jsonb_build_object('status','OK','purchaseId', v_po_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- sync_upsert: catalog/mirror entities (products, categories, suppliers,
-- profiles, notifications, audit) — validated + idempotent per entity
-- ---------------------------------------------------------------------------
create or replace function public.sync_upsert(p_entity text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;

  case p_entity
    when 'product' then
      if not public.app_has_permission('create_product') then
        return jsonb_build_object('status','ERROR','message','permission denied');
      end if;
      insert into public.products (id, organization_id, branch_id, name, generic_name,
        brand_name, category_id, dosage_form, strength, pack_size, barcode, sku,
        manufacturer, responsible, selling_price_pesewas, cost_price_pesewas,
        reorder_level, minimum_stock, target_stock, reorder_quantity, active)
      values (p_payload ->> 'id', v_org, public.resolved_branch_id((p_payload ->> 'branchId')::uuid),
        p_payload ->> 'name', p_payload ->> 'genericName', p_payload ->> 'brandName',
        p_payload ->> 'categoryId', p_payload ->> 'dosageForm', p_payload ->> 'strength',
        p_payload ->> 'packSize', p_payload ->> 'barcode', p_payload ->> 'sku',
        p_payload ->> 'manufacturer', p_payload ->> 'responsible',
        (p_payload ->> 'sellingPricePesewas')::int, (p_payload ->> 'costPricePesewas')::int,
        coalesce((p_payload ->> 'reorderLevel')::int, 10),
        coalesce((p_payload ->> 'minimumStock')::int, 5),
        coalesce((p_payload ->> 'targetStock')::int, 50),
        coalesce((p_payload ->> 'reorderQuantity')::int, 20),
        coalesce((p_payload ->> 'active')::boolean, true))
      on conflict (id) do update set
        name = excluded.name, generic_name = excluded.generic_name,
        brand_name = excluded.brand_name, category_id = excluded.category_id,
        dosage_form = excluded.dosage_form, strength = excluded.strength,
        pack_size = excluded.pack_size, barcode = excluded.barcode, sku = excluded.sku,
        manufacturer = excluded.manufacturer, responsible = excluded.responsible,
        selling_price_pesewas = excluded.selling_price_pesewas,
        cost_price_pesewas = excluded.cost_price_pesewas,
        reorder_level = excluded.reorder_level, minimum_stock = excluded.minimum_stock,
        target_stock = excluded.target_stock, reorder_quantity = excluded.reorder_quantity,
        active = excluded.active, updated_at = now();

    when 'category' then
      if not public.app_has_permission('create_product') then
        return jsonb_build_object('status','ERROR','message','permission denied');
      end if;
      insert into public.categories (id, organization_id, name, description)
      values (p_payload ->> 'id', v_org, p_payload ->> 'name', p_payload ->> 'description')
      on conflict (id) do update set name = excluded.name, description = excluded.description,
        updated_at = now();

    when 'supplier' then
      if not public.app_has_permission('create_purchase') then
        return jsonb_build_object('status','ERROR','message','permission denied');
      end if;
      insert into public.suppliers (id, organization_id, branch_id, name, phone, address,
        email, contact_person, active)
      values (p_payload ->> 'id', v_org, public.resolved_branch_id((p_payload ->> 'branchId')::uuid),
        p_payload ->> 'name', p_payload ->> 'phone', p_payload ->> 'address',
        p_payload ->> 'email', p_payload ->> 'contactPerson',
        coalesce((p_payload ->> 'active')::boolean, true))
      on conflict (id) do update set name = excluded.name, phone = excluded.phone,
        address = excluded.address, email = excluded.email,
        contact_person = excluded.contact_person, active = excluded.active, updated_at = now();

    when 'notification' then
      insert into public.notifications (id, organization_id, branch_id, type, severity,
        title, body, data, read)
      values (p_payload ->> 'id', v_org, public.resolved_branch_id((p_payload ->> 'branchId')::uuid),
        p_payload ->> 'type', coalesce(p_payload ->> 'severity','INFO'),
        p_payload ->> 'title', p_payload ->> 'body', p_payload -> 'data',
        coalesce((p_payload ->> 'read')::boolean, false))
      on conflict (id) do update set read = excluded.read;

    when 'audit' then
      insert into public.audit_logs (id, organization_id, user_id, device_id, action,
        entity, entity_id, before, after)
      values (p_payload ->> 'id', v_org, p_payload ->> 'userId', p_payload ->> 'deviceId',
        p_payload ->> 'action', p_payload ->> 'entity', p_payload ->> 'entityId',
        p_payload -> 'before', p_payload -> 'after');

    else
      return jsonb_build_object('status','ERROR','message','unknown entity ' || p_entity);
  end case;

  return jsonb_build_object('status','OK','id', p_payload ->> 'id');
end;
$$;

-- ---------------------------------------------------------------------------
-- pull_all_changes: incremental download for a device (or NULL = full)
-- ---------------------------------------------------------------------------
create or replace function public.pull_all_changes(p_since timestamptz)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org uuid;
  result jsonb;
begin
  select organization_id into v_org from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;
  if p_since is null then p_since := '1970-01-01'::timestamptz; end if;

  select jsonb_build_object(
    'status','OK',
    'branches',   coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.branches where organization_id = v_org and updated_at > p_since) t), '[]'),
    'profiles',   coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.profiles where organization_id = v_org and updated_at > p_since) t), '[]'),
    'categories', coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.categories where organization_id = v_org and updated_at > p_since) t), '[]'),
    'products',   coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.products where organization_id = v_org and updated_at > p_since) t), '[]'),
    'suppliers',  coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.suppliers where organization_id = v_org and updated_at > p_since) t), '[]'),
    'batches',    coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.batches where organization_id = v_org and updated_at > p_since) t), '[]'),
    'sales',      coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.sales where organization_id = v_org and created_at > p_since) t), '[]'),
    'saleItems',  coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select si.* from public.sale_items si join public.sales s on s.id = si.sale_id
                             where s.organization_id = v_org and s.created_at > p_since) t), '[]'),
    'purchases',  coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.purchase_orders where organization_id = v_org and updated_at > p_since) t), '[]'),
    'purchaseItems', coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select poi.* from public.purchase_order_items poi join public.purchase_orders po on po.id = poi.purchase_id
                             where po.organization_id = v_org and po.updated_at > p_since) t), '[]'),
    'stockMovements', coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.stock_movements where organization_id = v_org and created_at > p_since) t), '[]'),
    'notifications', coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.notifications where organization_id = v_org and created_at > p_since) t), '[]'),
    'conflicts',  coalesce((select jsonb_agg(row_to_json(t)::jsonb) from
                            (select * from public.sync_conflicts where organization_id = v_org and created_at > p_since) t), '[]')
  ) into result;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_sync_point: record device pull/push points (server authority)
-- ---------------------------------------------------------------------------
create or replace function public.update_sync_point(p_device_id text, p_pushed_at timestamptz, p_pulled_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org uuid;
  v_user uuid;
begin
  select organization_id, auth_user_id into v_org, v_user from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;
  insert into public.sync_state (device_id, organization_id, user_id, last_pushed_at, last_pulled_at)
  values (p_device_id, v_org, v_user, p_pushed_at, p_pulled_at)
  on conflict (device_id) do update set
    last_pushed_at = coalesce(excluded.last_pushed_at, sync_state.last_pushed_at),
    last_pulled_at = coalesce(excluded.last_pulled_at, sync_state.last_pulled_at),
    updated_at = now();
  return jsonb_build_object('status','OK');
end;
$$;

-- ---------------------------------------------------------------------------
-- ack_conflict: acknowledge a recorded conflict
-- ---------------------------------------------------------------------------
create or replace function public.ack_conflict(p_conflict_id text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.profiles where auth_user_id = auth.uid();
  update public.sync_conflicts set status = 'ACKNOWLEDGED', resolved_at = now()
  where id = p_conflict_id and organization_id = v_org;
  return jsonb_build_object('status','OK');
end;
$$;

-- ---------------------------------------------------------------------------
-- app_bootstrap: create the first organization + administrator
-- Run ONCE manually via SQL Editor, e.g.:
--   select * from app_bootstrap('Agya Appiah OTCMS', 'Main Branch',
--                                'admin@otcms.example', 'A-Strong-Password!', 'Administrator');
-- ---------------------------------------------------------------------------
create or replace function public.app_bootstrap(p_org_name text, p_branch_name text,
  p_admin_email text, p_admin_password text, p_admin_display_name text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org uuid;
  v_branch uuid;
  v_user uuid;
begin
  insert into public.organizations (name) values (p_org_name) returning id into v_org;
  insert into public.branches (organization_id, name) values (v_org, p_branch_name) returning id into v_branch;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
          p_admin_email, crypt(p_admin_password, gen_salt('bf')),
          now(), now(), now())
  returning id into v_user;

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_user, v_user::text,
          jsonb_build_object('sub', v_user::text, 'email', p_admin_email, 'email_verified', true),
          'email', now(), now(), now());

  insert into public.profiles (auth_user_id, organization_id, branch_id, role, display_name)
  values (v_user, v_org, v_branch, 'SUPER_ADMIN', p_admin_display_name);

  insert into public.audit_logs (id, organization_id, user_id, action, entity, entity_id, after)
  values ('aud_' || gen_random_uuid()::text, v_org, v_user, 'ORG_BOOTSTRAPPED', 'organization', v_org::text,
          jsonb_build_object('orgName', p_org_name, 'branch', p_branch_name));

  return jsonb_build_object('status','OK','organizationId', v_org, 'branchId', v_branch);
end;
$$;

-- ---------------------------------------------------------------------------
-- app_invite_user: create an additional user (callable by admins)
-- ---------------------------------------------------------------------------
create or replace function public.app_invite_user(p_email text, p_password text,
  p_display_name text, p_role text, p_branch_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_org uuid;
  v_user uuid;
begin
  if not public.app_has_permission('manage_users') then
    return jsonb_build_object('status','ERROR','message','permission denied');
  end if;
  select organization_id into v_org from public.profiles where auth_user_id = auth.uid();
  if v_org is null then
    return jsonb_build_object('status','ERROR','message','unauthorized');
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
          p_email, crypt(p_password, gen_salt('bf')), now(), now(), now())
  returning id into v_user;

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_user, v_user::text,
          jsonb_build_object('sub', v_user::text, 'email', p_email, 'email_verified', true),
          'email', now(), now(), now());

  insert into public.profiles (auth_user_id, organization_id, branch_id, role, display_name)
  values (v_user, v_org, coalesce(p_branch_id, (select branch_id from public.profiles where auth_user_id = auth.uid())), p_role, p_display_name);

  return jsonb_build_object('status','OK','userId', v_user);
end;
$$;

grant execute on function
  public.app_my_profile, public.app_my_role, public.app_has_permission,
  public.resolved_branch_id,
  public.sync_sale, public.sync_movement, public.sync_purchase_receipt,
  public.sync_upsert, public.pull_all_changes, public.update_sync_point,
  public.ack_conflict, public.app_invite_user
to authenticated;

revoke execute on function public.app_bootstrap from public, anon, authenticated;