-- DEV ONLY: run before 001 if you need a completely fresh database
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_sale_insert on public.sales;

drop table if exists public.hacchuu_order_items cascade;
drop table if exists public.hacchuu_orders cascade;
drop table if exists public.sales cascade;
drop table if exists public.daily_stock cascade;
drop table if exists public.business_days cascade;
drop table if exists public.products cascade;
drop table if exists public.store_members cascade;
drop table if exists public.stores cascade;
drop table if exists public.profiles cascade;

drop function if exists public.sync_sold_quantity_on_sale();
drop function if exists public.handle_new_user();
drop function if exists public.is_store_member(uuid);
drop function if exists public.is_store_owner(uuid);
