-- =============================================================================
-- Step 2: Run AFTER 001 — makes your Supabase Auth user the store admin (owner)
--
-- User from Supabase Auth:
--   Email: yeminaung.56jp@gmail.com
--   UID:   be1bf982-8c4c-4055-a845-3b9f702b45af
-- =============================================================================

insert into public.profiles (id, full_name)
values (
  'be1bf982-8c4c-4055-a845-3b9f702b45af',
  '管理者'
)
on conflict (id) do update
set full_name = excluded.full_name;

insert into public.stores (id, name, address)
values (
  'a0000000-0000-4000-8000-000000000001',
  'YOMI STORE',
  null
)
on conflict (id) do update
set name = excluded.name;

insert into public.store_members (store_id, user_id, role)
values (
  'a0000000-0000-4000-8000-000000000001',
  'be1bf982-8c4c-4055-a845-3b9f702b45af',
  'owner'
)
on conflict (store_id, user_id) do update
set role = 'owner';

-- Check result (should show 1 row: owner + メイン店舗)
select
  p.full_name,
  u.email,
  sm.role,
  s.name as store_name
from public.store_members sm
join public.profiles p on p.id = sm.user_id
join auth.users u on u.id = p.id
join public.stores s on s.id = sm.store_id
where sm.user_id = 'be1bf982-8c4c-4055-a845-3b9f702b45af';
