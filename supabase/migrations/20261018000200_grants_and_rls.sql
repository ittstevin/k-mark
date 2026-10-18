alter table public.locations enable row level security;
alter table public.categories enable row level security;
alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.listing_images enable row level security;
alter table public.favorites enable row level security;
alter table public.reports enable row level security;
alter table private.moderator_roles enable row level security;
alter table private.listing_moderation_events enable row level security;
alter table private.report_moderation_events enable row level security;
alter table private.storage_cleanup_queue enable row level security;
alter table private.image_upload_reservations enable row level security;

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from public, anon, authenticated;
alter default privileges in schema private revoke all on tables from public, anon, authenticated;

create function private.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.profiles as p
  where p.auth_user_id = (select auth.uid())
    and p.onboarding_complete
    and not p.is_anonymized
$$;

create function private.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.moderator_roles as mr
    where mr.user_id = (select auth.uid())
      and mr.revoked_at is null
  )
$$;

create function private.enqueue_storage_cleanup(
  p_bucket_id text,
  p_object_name text,
  p_reason text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.storage_cleanup_queue (bucket_id, object_name, reason)
  values (p_bucket_id, p_object_name, p_reason)
  on conflict (bucket_id, object_name) do nothing
$$;

revoke all on function private.current_profile_id() from public, anon, authenticated;
revoke all on function private.is_moderator() from public, anon, authenticated;
revoke all on function private.enqueue_storage_cleanup(text, text, text) from public, anon, authenticated;
grant execute on function private.current_profile_id() to authenticated;
grant execute on function private.is_moderator() to authenticated;

grant select (id, county, area_slug, area_name, is_active, sort_order)
  on public.locations to anon, authenticated;
grant select (id, slug, name, sort_order, is_active, created_at)
  on public.categories to anon, authenticated;
grant select (id, display_name, location_id)
  on public.profiles to anon, authenticated;
grant update (display_name, location_id)
  on public.profiles to authenticated;
grant select (
  id, seller_profile_id, category_id, location_id, slug, title, description,
  price_kes, status, created_at, updated_at, sold_at
) on public.listings to anon, authenticated;
grant select (id, listing_id, alt_text, sort_order, published_path)
  on public.listing_images to anon, authenticated;
grant select (staging_path) on public.listing_images to authenticated;
grant select on public.favorites to authenticated;
grant insert (user_id, listing_id) on public.favorites to authenticated;
grant delete on public.favorites to authenticated;
grant select (
  id, reporter_user_id, reporter_profile_id, target_listing_id,
  target_profile_id, target_reference_snapshot, reason, details, status, created_at
) on public.reports to authenticated;
grant insert (
  reporter_user_id, reporter_profile_id, target_listing_id, target_profile_id,
  target_reference_snapshot, reason, details
) on public.reports to authenticated;

create policy locations_read_active
on public.locations for select to anon, authenticated
using (is_active);

create policy categories_read_active
on public.categories for select to anon, authenticated
using (is_active);

create policy profiles_read_public
on public.profiles for select to anon, authenticated
using (true);

create policy profiles_update_self
on public.profiles for update to authenticated
using (auth_user_id = (select auth.uid()) and not is_anonymized)
with check (auth_user_id = (select auth.uid()) and not is_anonymized);

create policy listings_read_active
on public.listings for select to anon, authenticated
using (status = 'active');

create policy listings_read_seller
on public.listings for select to authenticated
using (seller_profile_id = (select private.current_profile_id()));

create policy listings_read_moderator
on public.listings for select to authenticated
using ((select private.is_moderator()));

create policy listing_images_read_active
on public.listing_images for select to anon, authenticated
using (
  published_path is not null
  and exists (
    select 1 from public.listings as l
    where l.id = listing_id and l.status = 'active'
  )
);

create policy listing_images_read_seller
on public.listing_images for select to authenticated
using (
  exists (
    select 1 from public.listings as l
    where l.id = listing_id
      and l.seller_profile_id = (select private.current_profile_id())
      and l.status <> 'removed'
  )
);

create policy listing_images_read_moderator
on public.listing_images for select to authenticated
using ((select private.is_moderator()));

create policy favorites_read_self
on public.favorites for select to authenticated
using (user_id = (select auth.uid()));

create policy favorites_insert_self_active
on public.favorites for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.listings as l
    where l.id = listing_id and l.status = 'active'
  )
);

create policy favorites_delete_self
on public.favorites for delete to authenticated
using (user_id = (select auth.uid()));

create policy reports_read_reporter
on public.reports for select to authenticated
using (reporter_user_id = (select auth.uid()));

create policy reports_read_moderator
on public.reports for select to authenticated
using ((select private.is_moderator()));

create policy reports_insert_self
on public.reports for insert to authenticated
with check (
  reporter_user_id = (select auth.uid())
  and reporter_profile_id = (select private.current_profile_id())
  and (
    (target_listing_id is not null and target_profile_id is null)
      and exists (select 1 from public.listings l
        where l.id = target_listing_id and l.status = 'active')
    or (target_listing_id is null and target_profile_id is not null)
      and exists (select 1 from public.profiles p
        where p.id = target_profile_id and not p.is_anonymized)
  )
);

alter table storage.objects enable row level security;
revoke all on table storage.objects from public, anon, authenticated;
