begin;
select no_plan();

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'browse-a@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Browse Seller"}', now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'browse-b@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Second Seller"}', now(), now());

select is(
  (select count(*) from public.profiles where auth_user_id in (
    '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'
  )),
  2::bigint,
  'Auth signup trigger creates one profile per user'
);
update public.profiles set onboarding_complete = true
where auth_user_id in (
  '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'
);

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status
)
select
  '20000000-0000-4000-8000-000000000001', p.id, c.id, l.id,
  'browse-active-200000000001', 'Active test listing', 'Visible to visitors', 2500, 'active'
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '10000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics'
  and l.county = 'Nairobi' and l.area_slug = 'westlands';

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status
)
select
  '20000000-0000-4000-8000-000000000002', p.id, c.id, l.id,
  'browse-pending-200000000002', 'Pending test listing', 'Private during review', 5000, 'pending_review'
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '10000000-0000-4000-8000-000000000002'
  and c.slug = 'electronics'
  and l.county = 'Nairobi' and l.area_slug = 'westlands';

set local role anon;
select is(
  (select count(*) from public.listings where id = '20000000-0000-4000-8000-000000000001'),
  1::bigint,
  'anon can read an active listing'
);
select is(
  (select count(*) from public.listings where id = '20000000-0000-4000-8000-000000000002'),
  0::bigint,
  'anon cannot read a pending listing'
);
select results_eq(
  $$select display_name from public.profiles where id = (select seller_profile_id from public.listings where id = '20000000-0000-4000-8000-000000000001')$$,
  array['Browse Seller'::text],
  'anon can read the intentionally public seller display name'
);
select throws_ok(
  $$select auth_user_id from public.profiles limit 1$$,
  '42501', null,
  'anon cannot select the private Auth link from profiles'
);
select throws_ok(
  $$update public.profiles set onboarding_complete = true$$,
  '42501', null,
  'anon cannot change onboarding state'
);
select throws_ok(
  $$select * from public.reports$$,
  '42501', null,
  'anon has no report table access'
);
select throws_ok(
  $$update public.listings set status = 'active' where id = '20000000-0000-4000-8000-000000000002'$$,
  '42501', null,
  'anon cannot change a listing status directly'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
select is(
  (select count(*) from public.listings where id = '20000000-0000-4000-8000-000000000002'),
  1::bigint,
  'seller can read their own pending listing'
);
select throws_ok(
  $$update public.listings set seller_profile_id = '10000000-0000-4000-8000-000000000001' where id = '20000000-0000-4000-8000-000000000002'$$,
  '42501', null,
  'seller cannot reassign listing ownership through the table API'
);
reset role;

select * from finish();
rollback;