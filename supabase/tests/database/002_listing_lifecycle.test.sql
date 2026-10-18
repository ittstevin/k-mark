begin;
select no_plan();

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('30000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'life-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Lifecycle Owner"}', now(), now()),
  ('30000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'life-other@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Lifecycle Other"}', now(), now()),
  ('30000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'life-mod@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Lifecycle Moderator"}', now(), now());

update public.profiles set onboarding_complete = true
where auth_user_id in (
  '30000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003'
);

insert into private.moderator_roles (user_id)
values ('30000000-0000-4000-8000-000000000003');

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status
)
select
  '40000000-0000-4000-8000-000000000001', p.id, c.id, l.id,
  'life-draft-400000000001', 'Owner draft', 'Draft content', 1500, 'draft'
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '30000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status
)
select
  '40000000-0000-4000-8000-000000000002', p.id, c.id, l.id,
  'life-pending-400000000002', 'Pending moderation', 'Needs approval', 2500, 'pending_review'
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '30000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status, approved_at
)
select
  '40000000-0000-4000-8000-000000000003', p.id, c.id, l.id,
  'life-active-400000000003', 'Owner active', 'Approved content', 10000, 'active', now()
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '30000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status, approved_at
)
select
  '40000000-0000-4000-8000-000000000005', p.id, c.id, l.id,
  'life-active-draft-400000000005', 'Second owner active', 'Second approved content', 8000, 'active', now()
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '30000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status
)
select
  '40000000-0000-4000-8000-000000000004', p.id, c.id, l.id,
  'life-removed-400000000004', 'Removed listing', 'Removed by moderator', 10000, 'removed'
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '30000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

set local role authenticated;
set local request.jwt.claim.sub = '30000000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.pause_listing('40000000-0000-4000-8000-000000000003')$$,
  '42501', null,
  'another seller cannot pause the owner's listing'
);
select throws_ok(
  $$select public.moderator_decide_listing('40000000-0000-4000-8000-000000000002', 'approve', 'forged')$$,
  '42501', null,
  'ordinary authenticated user cannot approve'
);
select throws_ok(
  $$select public.moderator_decide_listing('40000000-0000-4000-8000-000000000003', 'remove', 'forged')$$,
  '42501', null,
  'ordinary authenticated user cannot remove an active listing'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '30000000-0000-4000-8000-000000000001';
select ok(
  public.create_listing_draft(
    (select id from public.categories where slug = 'electronics'),
    (select id from public.locations where area_slug = 'westlands'),
    'Maximum price is valid', 'Boundary price test', 100000000
  ) is not null,
  'KSh 100,000,000 is accepted'
);
select throws_ok(
  $$select public.create_listing_draft(
    (select id from public.categories where slug = 'electronics'),
    (select id from public.locations where area_slug = 'westlands'),
    'Above maximum price', 'Boundary price test', 100000001
  )$$,
  '23514', null,
  'price above KSh 100,000,000 is rejected'
);
select is(
  public.submit_listing('40000000-0000-4000-8000-000000000001'),
  'pending_review'::public.listing_status,
  'seller can submit their draft for review'
);
select throws_ok(
  $$update public.listings set status = 'active' where id = '40000000-0000-4000-8000-000000000002'$$,
  '42501', null,
  'seller cannot set active status directly'
);
select is(
  public.save_listing_content(
    '40000000-0000-4000-8000-000000000003',
    (select id from public.categories where slug = 'electronics'),
    (select id from public.locations where area_slug = 'westlands'),
    'Edited owner active', 'Edited content goes back for review', 10000, false, '[]'::jsonb
  ),
  'pending_review'::public.listing_status,
  'editing active content immediately takes it offline for review'
);
select is(
  public.save_listing_content(
    '40000000-0000-4000-8000-000000000005',
    (select id from public.categories where slug = 'electronics'),
    (select id from public.locations where area_slug = 'westlands'),
    'Saved as draft', 'Seller explicitly saves the edit as draft', 8000, true, '[]'::jsonb
  ),
  'draft'::public.listing_status,
  'seller may explicitly save their active listing changes as a private draft'
);
select throws_ok(
  $$select public.moderator_decide_listing('40000000-0000-4000-8000-000000000004', 'restore', null)$$,
  '42501', null,
  'seller cannot restore a moderator-removed listing'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '30000000-0000-4000-8000-000000000003';
select is(
  public.moderator_decide_listing('40000000-0000-4000-8000-000000000002', 'approve', 'approved by test moderator'),
  'approved'::public.listing_status,
  'authorized moderator can approve pending listing'
);
select is(
  public.publish_approved_listing('40000000-0000-4000-8000-000000000002', '[]'::jsonb),
  'active'::public.listing_status,
  'approved listing with zero images can be activated because MVP has no minimum image count'
);
select is(
  public.moderator_decide_listing('40000000-0000-4000-8000-000000000004', 'restore', 'restored by test moderator'),
  'paused'::public.listing_status,
  'moderator restore returns removed listing to paused, not active'
);
select is(
  public.moderator_decide_listing('40000000-0000-4000-8000-000000000002', 'remove', 'test removal'),
  'removed'::public.listing_status,
  'moderator can remove a listing'
);
select is(
  (select count(*) from private.listing_moderation_events
    where listing_id = '40000000-0000-4000-8000-000000000004' and action = 'remove'),
  1::bigint,
  'moderator removal writes a private audit event'
);
select throws_ok(
  $$update private.moderator_roles set revoked_at = now() where user_id = auth.uid()$$,
  '42501', null,
  'moderator cannot grant or revoke their own role through the API'
);
reset role;

select * from finish();
rollback;