begin;
select no_plan();

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('50000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'report-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Report Owner"}', now(), now()),
  ('50000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'reporter-a@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Reporter A"}', now(), now()),
  ('50000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'reporter-b@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Reporter B"}', now(), now()),
  ('50000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'report-mod@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Report Moderator"}', now(), now());

update public.profiles set onboarding_complete = true
where auth_user_id in (
  '50000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000002',
  '50000000-0000-4000-8000-000000000003',
  '50000000-0000-4000-8000-000000000004'
);

insert into private.moderator_roles (user_id)
values ('50000000-0000-4000-8000-000000000004');

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status
)
select
  '60000000-0000-4000-8000-000000000001', p.id, c.id, l.id,
  'reported-active-600000000001', 'Report target', 'Active report target', 3200, 'active'
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '50000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000002';
select lives_ok(
  $$insert into public.reports (
      reporter_user_id, reporter_profile_id, target_listing_id,
      target_reference_snapshot, reason, details
    )
    values (
      auth.uid(), private.current_profile_id(),
      '60000000-0000-4000-8000-000000000001',
      '60000000-0000-4000-8000-000000000001', 'misleading', 'Test report details'
    )$$,
  'reporter can create a report against a listing'
);

select is(
  (select count(*) from public.reports),
  1::bigint,
  'reporter can read their own report'
);
select throws_ok(
  $$insert into public.reports (reporter_user_id, reporter_profile_id, target_listing_id, target_reference_snapshot, reason)
    values (
      '50000000-0000-4000-8000-000000000003',
      private.current_profile_id(),
      '60000000-0000-4000-8000-000000000001',
      '60000000-0000-4000-8000-000000000001', 'other'
    )$$,
  '42501', null,
  'reporter cannot submit as another account'
);
select throws_ok(
  $$update public.reports set status = 'resolved'$$,
  '42501', null,
  'reporter cannot update report status directly'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000001';
select is(
  (select count(*) from public.reports),
  0::bigint,
  'reported seller cannot read the report or reporter identity'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000003';
select is(
  (select count(*) from public.reports),
  0::bigint,
  'another user cannot read the report or reporter details'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000004';
select is(
  public.set_report_status((select id from public.reports limit 1), 'reviewing'),
  'reviewing'::public.report_status,
  'moderator can move an open report into review'
);
reset role;

insert into public.listings (
  id, seller_profile_id, category_id, location_id, slug, title, description, price_kes
)
select
  '60000000-0000-4000-8000-000000000002', p.id, c.id, l.id,
  'image-draft-600000000002', 'Image draft', 'Image upload test', 1000
from public.profiles p
cross join public.categories c
cross join public.locations l
where p.auth_user_id = '50000000-0000-4000-8000-000000000001'
  and c.slug = 'electronics' and l.area_slug = 'westlands';

select ok(
  exists (select 1 from storage.buckets where id = 'listing-staging' and public = false),
  'staging bucket is configured as private'
);
select ok(
  exists (select 1 from storage.buckets where id = 'listing-images' and public = true),
  'only the approved-images bucket is public'
);
select is(
  (select file_size_limit from storage.buckets where id = 'listing-staging'),
  5000000::bigint,
  'staging bucket enforces the exact 5 MB object limit'
);
select ok(
  (select allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']::text[]
    from storage.buckets where id = 'listing-staging'),
  'staging bucket allows only the approved raster formats'
);

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000001';
select ok(
  set_config(
    'test.image_path',
    public.reserve_listing_image_upload(
      '60000000-0000-4000-8000-000000000002', 0, 'Private staging test image', 'jpg'
    ),
    true
  ) <> '',
  'owner can reserve a private image path for a draft'
);
insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
  'listing-staging', current_setting('test.image_path'), auth.uid()::text,
  '{"mimetype":"image/jpeg","size":1024}'::jsonb
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.complete_listing_image_upload(current_setting('test.image_path'))$$,
  '42501', null,
  'browser role cannot call the byte-validation completion RPC'
);
reset role;

set local role service_role;
select ok(
  public.complete_listing_image_upload(current_setting('test.image_path')) is not null,
  'trusted server can attach an uploaded reserved image after validating its bytes'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000002';
insert into public.favorites (user_id, listing_id)
values ('50000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000001');
select is(
  (select count(*) from public.favorites),
  1::bigint,
  'a signed-in user can read their own favourite'
);
select throws_ok(
  $$insert into public.favorites (user_id, listing_id) values ('50000000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000001')$$,
  '42501', null,
  'a user cannot insert a favourite for another account'
);
select throws_ok(
  $$insert into public.favorites (user_id, listing_id) values ('50000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000001')$$,
  '23505', null,
  'the user/listing pair is unique'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '50000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 1, 'Other owner', 'jpg')$$,
  '42501', null,
  'another account cannot reserve an image for this listing'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('listing-images', auth.uid()::text || '/60000000-0000-4000-8000-000000000002/forged.jpg', auth.uid()::text, '{"mimetype":"image/jpeg","size":100}'::jsonb)$$,
  '42501', null,
  'seller cannot upload directly into the public image bucket'
);
select throws_ok(
  $$delete from storage.objects where bucket_id = 'listing-staging' and name = current_setting('test.image_path')$$,
  '42501', null,
  'seller cannot delete storage objects outside the checked cleanup path'
);

select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 1, 'Reserved 2', 'jpg')$$, 'reserve second image');
select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 2, 'Reserved 3', 'jpg')$$, 'reserve third image');
select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 3, 'Reserved 4', 'jpg')$$, 'reserve fourth image');
select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 4, 'Reserved 5', 'jpg')$$, 'reserve fifth image');
select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 5, 'Reserved 6', 'jpg')$$, 'reserve sixth image');
select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 6, 'Reserved 7', 'jpg')$$, 'reserve seventh image');
select lives_ok($$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 7, 'Reserved 8', 'jpg')$$, 'reserve eighth image');
select throws_ok(
  $$select public.reserve_listing_image_upload('60000000-0000-4000-8000-000000000002', 0, 'Ninth image', 'jpg')$$,
  '23514', null,
  'the ninth concurrent image reservation is denied'
);
reset role;

set local role anon;
select is(
  (select count(*) from storage.objects where bucket_id = 'listing-staging'),
  0::bigint,
  'anonymous role cannot inspect private staging objects'
);
reset role;

select * from finish();
rollback;