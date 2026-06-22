-- =============================================================================
-- Ordering Materials (発注) — Initial schema (MVP, no 業者/suppliers yet)
-- Run this in Supabase Dashboard → SQL Editor → New query → Run
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Profiles (extends auth.users)
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'User profile linked to Supabase Auth';

-- Auto-create profile when a user signs up
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
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2. Stores & members
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
create index store_members_store_id_idx on public.store_members (store_id);

-- ---------------------------------------------------------------------------
-- 3. Products
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

comment on column public.products.target_stock is 'Desired stock quantity for the next morning';
comment on column public.products.unit is 'e.g. パック, 個, kg';

-- ---------------------------------------------------------------------------
-- 4. Business days & daily stock
-- ---------------------------------------------------------------------------

create table public.business_days (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  business_date date not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  unique (store_id, business_date)
);

create index business_days_store_id_idx on public.business_days (store_id);
create index business_days_business_date_idx on public.business_days (business_date);

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

create index daily_stock_business_day_id_idx on public.daily_stock (business_day_id);
create index daily_stock_product_id_idx on public.daily_stock (product_id);

comment on column public.daily_stock.opening_quantity is 'Stock count at start of day (e.g. 10 packs)';
comment on column public.daily_stock.sold_quantity is 'Total sold during the day';

-- Remaining stock view
create or replace view public.daily_stock_with_remaining as
select
  ds.id,
  ds.business_day_id,
  ds.product_id,
  ds.opening_quantity,
  ds.sold_quantity,
  ds.opening_quantity - ds.sold_quantity as remaining_quantity,
  ds.updated_at,
  bd.store_id,
  bd.business_date,
  p.name as product_name,
  p.unit,
  p.target_stock
from public.daily_stock ds
join public.business_days bd on bd.id = ds.business_day_id
join public.products p on p.id = ds.product_id;

-- ---------------------------------------------------------------------------
-- 5. Sales
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

create index sales_business_day_id_idx on public.sales (business_day_id);
create index sales_product_id_idx on public.sales (product_id);
create index sales_store_id_idx on public.sales (store_id);

-- Keep daily_stock.sold_quantity in sync when a sale is recorded
create or replace function public.sync_sold_quantity_on_sale ()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.daily_stock
  set
    sold_quantity = sold_quantity + new.quantity,
    updated_at = now()
  where business_day_id = new.business_day_id
    and product_id = new.product_id;

  if not found then
    raise exception 'No daily_stock row for this product on this business day. Set opening stock first.';
  end if;

  return new;
end;
$$;

create trigger on_sale_insert
  after insert on public.sales
  for each row
  execute function public.sync_sold_quantity_on_sale();

-- ---------------------------------------------------------------------------
-- 6. Hacchuu (発注) orders
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

create index hacchuu_orders_store_id_idx on public.hacchuu_orders (store_id);

comment on column public.hacchuu_orders.status is 'submitted = sent to 業者 (future phase)';
comment on column public.hacchuu_orders.order_for_date is 'Usually the day after business_date';

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
  ai_suggested_quantity integer check (ai_suggested_quantity is null or ai_suggested_quantity >= 0),
  algorithm_version text not null default 'v1_basic',
  unique (hacchuu_order_id, product_id)
);

create index hacchuu_order_items_order_id_idx on public.hacchuu_order_items (hacchuu_order_id);

-- Generate 発注 from a closed business day
-- Formula: calculated_quantity = max(0, target_stock - remaining)
create or replace function public.generate_hacchuu (p_business_day_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_business_date date;
  v_order_id uuid;
begin
  select store_id, business_date
  into v_store_id, v_business_date
  from public.business_days
  where id = p_business_day_id;

  if v_store_id is null then
    raise exception 'Business day not found: %', p_business_day_id;
  end if;

  if not exists (
    select 1 from public.store_members
    where store_id = v_store_id and user_id = auth.uid()
  ) then
    raise exception 'Not a member of this store';
  end if;

  insert into public.hacchuu_orders (
    store_id,
    business_day_id,
    order_for_date,
    status
  )
  values (
    v_store_id,
    p_business_day_id,
    v_business_date + 1,
    'pending_review'
  )
  on conflict (business_day_id) do update
  set status = 'pending_review'
  returning id into v_order_id;

  delete from public.hacchuu_order_items
  where hacchuu_order_id = v_order_id;

  insert into public.hacchuu_order_items (
    hacchuu_order_id,
    product_id,
    opening_quantity,
    sold_quantity,
    remaining_quantity,
    target_quantity,
    calculated_quantity,
    confirmed_quantity,
    algorithm_version
  )
  select
    v_order_id,
    ds.product_id,
    ds.opening_quantity,
    ds.sold_quantity,
    ds.opening_quantity - ds.sold_quantity,
    p.target_stock,
    greatest(0, p.target_stock - (ds.opening_quantity - ds.sold_quantity)),
    greatest(0, p.target_stock - (ds.opening_quantity - ds.sold_quantity)),
    'v1_basic'
  from public.daily_stock ds
  join public.products p on p.id = ds.product_id
  where ds.business_day_id = p_business_day_id
    and p.is_active = true;

  update public.business_days
  set status = 'closed'
  where id = p_business_day_id;

  return v_order_id;
end;
$$;

comment on function public.generate_hacchuu is
  'Calculate 発注 quantities and set business day to closed. Owner reviews before confirm.';

-- Confirm 発注 (owner review)
create or replace function public.confirm_hacchuu (
  p_hacchuu_order_id uuid,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  select store_id into v_store_id
  from public.hacchuu_orders
  where id = p_hacchuu_order_id;

  if v_store_id is null then
    raise exception 'Hacchuu order not found';
  end if;

  if not exists (
    select 1 from public.store_members
    where store_id = v_store_id
      and user_id = auth.uid()
      and role = 'owner'
  ) then
    raise exception 'Only store owners can confirm orders';
  end if;

  update public.hacchuu_orders
  set
    status = 'confirmed',
    confirmed_by = auth.uid(),
    confirmed_at = now(),
    notes = coalesce(p_notes, notes)
  where id = p_hacchuu_order_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. RLS helper
-- ---------------------------------------------------------------------------

create or replace function public.is_store_member (p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_members
    where store_id = p_store_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.is_store_owner (p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_members
    where store_id = p_store_id
      and user_id = auth.uid()
      and role = 'owner'
  );
$$;

-- ---------------------------------------------------------------------------
-- 8. Row Level Security
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

-- profiles
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- stores
create policy "Members can view their stores"
  on public.stores for select
  using (public.is_store_member(id));

create policy "Authenticated users can create stores"
  on public.stores for insert
  with check (auth.uid() is not null);

create policy "Owners can update their stores"
  on public.stores for update
  using (public.is_store_owner(id));

-- store_members
create policy "Members can view store membership"
  on public.store_members for select
  using (public.is_store_member(store_id));

create policy "Owners can add members"
  on public.store_members for insert
  with check (
    public.is_store_owner(store_id)
    or not exists (
      select 1 from public.store_members sm where sm.store_id = store_members.store_id
    )
  );

create policy "Allow creator to add self as owner on new store"
  on public.store_members for insert
  with check (
    user_id = auth.uid()
    and role = 'owner'
  );

create policy "Owners can update members"
  on public.store_members for update
  using (public.is_store_owner(store_id));

create policy "Owners can remove members"
  on public.store_members for delete
  using (public.is_store_owner(store_id));

-- products
create policy "Members can view products"
  on public.products for select
  using (public.is_store_member(store_id));

create policy "Members can insert products"
  on public.products for insert
  with check (public.is_store_member(store_id));

create policy "Members can update products"
  on public.products for update
  using (public.is_store_member(store_id));

create policy "Owners can delete products"
  on public.products for delete
  using (public.is_store_owner(store_id));

-- business_days
create policy "Members can view business days"
  on public.business_days for select
  using (public.is_store_member(store_id));

create policy "Members can insert business days"
  on public.business_days for insert
  with check (public.is_store_member(store_id));

create policy "Members can update business days"
  on public.business_days for update
  using (public.is_store_member(store_id));

-- daily_stock
create policy "Members can view daily stock"
  on public.daily_stock for select
  using (
    exists (
      select 1 from public.business_days bd
      where bd.id = daily_stock.business_day_id
        and public.is_store_member(bd.store_id)
    )
  );

create policy "Members can insert daily stock"
  on public.daily_stock for insert
  with check (
    exists (
      select 1 from public.business_days bd
      where bd.id = daily_stock.business_day_id
        and public.is_store_member(bd.store_id)
    )
  );

create policy "Members can update daily stock"
  on public.daily_stock for update
  using (
    exists (
      select 1 from public.business_days bd
      where bd.id = daily_stock.business_day_id
        and public.is_store_member(bd.store_id)
    )
  );

-- sales
create policy "Members can view sales"
  on public.sales for select
  using (public.is_store_member(store_id));

create policy "Members can insert sales"
  on public.sales for insert
  with check (public.is_store_member(store_id));

-- hacchuu_orders
create policy "Members can view hacchuu orders"
  on public.hacchuu_orders for select
  using (public.is_store_member(store_id));

create policy "Members can insert hacchuu orders"
  on public.hacchuu_orders for insert
  with check (public.is_store_member(store_id));

create policy "Members can update hacchuu orders"
  on public.hacchuu_orders for update
  using (public.is_store_member(store_id));

-- hacchuu_order_items
create policy "Members can view hacchuu items"
  on public.hacchuu_order_items for select
  using (
    exists (
      select 1 from public.hacchuu_orders ho
      where ho.id = hacchuu_order_items.hacchuu_order_id
        and public.is_store_member(ho.store_id)
    )
  );

create policy "Members can insert hacchuu items"
  on public.hacchuu_order_items for insert
  with check (
    exists (
      select 1 from public.hacchuu_orders ho
      where ho.id = hacchuu_order_items.hacchuu_order_id
        and public.is_store_member(ho.store_id)
    )
  );

create policy "Members can update hacchuu items"
  on public.hacchuu_order_items for update
  using (
    exists (
      select 1 from public.hacchuu_orders ho
      where ho.id = hacchuu_order_items.hacchuu_order_id
        and public.is_store_member(ho.store_id)
    )
  );

-- ---------------------------------------------------------------------------
-- 9. Grant execute on functions to authenticated users
-- ---------------------------------------------------------------------------

grant execute on function public.generate_hacchuu(uuid) to authenticated;
grant execute on function public.confirm_hacchuu(uuid, text) to authenticated;
grant execute on function public.is_store_member(uuid) to authenticated;
grant execute on function public.is_store_owner(uuid) to authenticated;
