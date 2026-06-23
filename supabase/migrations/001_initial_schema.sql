-- =============================================================================
-- Step 1: Run this FIRST (fresh database)
-- Supabase Dashboard → SQL Editor → New query → Run
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user ()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Stores & members (owner = admin / 管理者)
-- ---------------------------------------------------------------------------

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  created_at timestamptz not null default now()
);

create table public.store_members (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'staff' check (role in ('owner', 'staff')),
  created_at timestamptz not null default now(),
  unique (store_id, user_id)
);

create index store_members_user_id_idx on public.store_members (user_id);

-- ---------------------------------------------------------------------------
-- Products
-- ---------------------------------------------------------------------------

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  name text not null,
  unit text not null default '個',
  target_stock integer not null default 0 check (target_stock >= 0),
  min_stock integer check (min_stock is null or min_stock >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index products_store_id_idx on public.products (store_id);

-- ---------------------------------------------------------------------------
-- Business days & stock
-- ---------------------------------------------------------------------------

create table public.business_days (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  business_date date not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  unique (store_id, business_date)
);

create table public.daily_stock (
  id uuid primary key default gen_random_uuid(),
  business_day_id uuid not null references public.business_days (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  opening_quantity integer not null default 0 check (opening_quantity >= 0),
  sold_quantity integer not null default 0 check (sold_quantity >= 0),
  updated_at timestamptz not null default now(),
  unique (business_day_id, product_id),
  check (sold_quantity <= opening_quantity)
);

-- ---------------------------------------------------------------------------
-- Sales
-- ---------------------------------------------------------------------------

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  business_day_id uuid not null references public.business_days (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  quantity integer not null check (quantity > 0),
  sold_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create or replace function public.sync_sold_quantity_on_sale ()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.daily_stock
  set sold_quantity = sold_quantity + new.quantity, updated_at = now()
  where business_day_id = new.business_day_id and product_id = new.product_id;

  if not found then
    raise exception 'Set opening stock for this product first.';
  end if;

  return new;
end;
$$;

drop trigger if exists on_sale_insert on public.sales;

create trigger on_sale_insert
  after insert on public.sales
  for each row
  execute function public.sync_sold_quantity_on_sale();

-- ---------------------------------------------------------------------------
-- Hacchuu (発注)
-- ---------------------------------------------------------------------------

create table public.hacchuu_orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  business_day_id uuid not null references public.business_days (id) on delete cascade,
  order_for_date date not null,
  status text not null default 'draft' check (
    status in ('draft', 'pending_review', 'confirmed', 'submitted')
  ),
  confirmed_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  unique (business_day_id)
);

create table public.hacchuu_order_items (
  id uuid primary key default gen_random_uuid(),
  hacchuu_order_id uuid not null references public.hacchuu_orders (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  opening_quantity integer not null check (opening_quantity >= 0),
  sold_quantity integer not null check (sold_quantity >= 0),
  remaining_quantity integer not null check (remaining_quantity >= 0),
  target_quantity integer not null check (target_quantity >= 0),
  calculated_quantity integer not null check (calculated_quantity >= 0),
  confirmed_quantity integer check (confirmed_quantity is null or confirmed_quantity >= 0),
  algorithm_version text not null default 'v1_basic',
  unique (hacchuu_order_id, product_id)
);

-- ---------------------------------------------------------------------------
-- RLS helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_store_member (p_store_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.store_members
    where store_id = p_store_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_store_owner (p_store_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.store_members
    where store_id = p_store_id and user_id = auth.uid() and role = 'owner'
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.products enable row level security;
alter table public.business_days enable row level security;
alter table public.daily_stock enable row level security;
alter table public.sales enable row level security;
alter table public.hacchuu_orders enable row level security;
alter table public.hacchuu_order_items enable row level security;

create policy "profiles_select_own" on public.profiles for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id);

create policy "stores_select_member" on public.stores for select using (public.is_store_member(id));
create policy "stores_insert_auth" on public.stores for insert with check (auth.uid() is not null);
create policy "stores_update_owner" on public.stores for update using (public.is_store_owner(id));

create policy "members_select" on public.store_members for select using (public.is_store_member(store_id));
create policy "members_insert_self_owner" on public.store_members for insert
  with check (user_id = auth.uid() and role = 'owner');
create policy "members_insert_owner" on public.store_members for insert
  with check (public.is_store_owner(store_id));
create policy "members_update_owner" on public.store_members for update using (public.is_store_owner(store_id));
create policy "members_delete_owner" on public.store_members for delete using (public.is_store_owner(store_id));

create policy "products_all_member" on public.products for all
  using (public.is_store_member(store_id))
  with check (public.is_store_member(store_id));

create policy "business_days_all_member" on public.business_days for all
  using (public.is_store_member(store_id))
  with check (public.is_store_member(store_id));

create policy "daily_stock_all_member" on public.daily_stock for all
  using (exists (
    select 1 from public.business_days bd
    where bd.id = daily_stock.business_day_id and public.is_store_member(bd.store_id)
  ))
  with check (exists (
    select 1 from public.business_days bd
    where bd.id = daily_stock.business_day_id and public.is_store_member(bd.store_id)
  ));

create policy "sales_all_member" on public.sales for all
  using (public.is_store_member(store_id))
  with check (public.is_store_member(store_id));

create policy "hacchuu_orders_all_member" on public.hacchuu_orders for all
  using (public.is_store_member(store_id))
  with check (public.is_store_member(store_id));

create policy "hacchuu_items_all_member" on public.hacchuu_order_items for all
  using (exists (
    select 1 from public.hacchuu_orders ho
    where ho.id = hacchuu_order_items.hacchuu_order_id and public.is_store_member(ho.store_id)
  ))
  with check (exists (
    select 1 from public.hacchuu_orders ho
    where ho.id = hacchuu_order_items.hacchuu_order_id and public.is_store_member(ho.store_id)
  ));

grant execute on function public.is_store_member(uuid) to authenticated;
grant execute on function public.is_store_owner(uuid) to authenticated;
