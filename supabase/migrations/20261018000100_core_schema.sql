create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create extension if not exists pgtap with schema extensions;

create type public.listing_status as enum (
  'draft',
  'pending_review',
  'approved',
  'active',
  'paused',
  'sold',
  'rejected',
  'removed'
);

create type public.report_status as enum (
  'open',
  'reviewing',
  'resolved',
  'dismissed'
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  county text not null check (county in ('Nairobi', 'Kiambu')),
  area_slug text not null check (area_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  area_name text not null check (length(btrim(area_name)) between 1 and 80),
  is_active boolean not null default true,
  sort_order integer not null check (sort_order >= 0),
  unique (county, area_slug),
  unique (county, area_name)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null unique check (length(btrim(name)) between 1 and 80),
  sort_order integer not null check (sort_order >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  display_name text not null default 'New K-Mark member'
    check (length(btrim(display_name)) between 1 and 80),
  location_id uuid references public.locations (id) on delete set null,
  onboarding_complete boolean not null default false,
  is_anonymized boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_profile_id uuid not null references public.profiles (id) on delete restrict,
  category_id uuid not null references public.categories (id) on delete restrict,
  location_id uuid not null references public.locations (id) on delete restrict,
  slug text not null unique check (
    length(slug) between 1 and 120 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
  ),
  title text not null check (length(btrim(title)) between 1 and 100),
  description text not null check (length(btrim(description)) between 1 and 5000),
  price_kes integer not null check (price_kes between 0 and 100000000),
  status public.listing_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  approved_at timestamptz,
  sold_at timestamptz
);

create table public.listing_images (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  staging_path text unique,
  published_path text unique,
  alt_text text not null check (length(btrim(alt_text)) between 1 and 240),
  sort_order integer not null check (sort_order between 0 and 7),
  created_at timestamptz not null default now(),
  constraint listing_images_one_path check (num_nonnulls(staging_path, published_path) = 1),
  constraint listing_images_order_unique unique (listing_id, sort_order)
    deferrable initially deferred
);

create table public.favorites (
  user_id uuid not null references auth.users (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid references auth.users (id) on delete set null,
  reporter_profile_id uuid references public.profiles (id) on delete set null,
  target_listing_id uuid references public.listings (id) on delete restrict,
  target_profile_id uuid references public.profiles (id) on delete restrict,
  target_reference_snapshot uuid not null,
  reason text not null check (reason in (
    'scam', 'prohibited_item', 'misleading', 'harassment', 'other'
  )),
  details text check (details is null or length(details) <= 2000),
  status public.report_status not null default 'open',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint reports_one_target check (
    (target_listing_id is not null and target_profile_id is null)
    or (target_listing_id is null and target_profile_id is not null)
  ),
  constraint reports_target_snapshot_matches check (
    target_reference_snapshot = coalesce(target_listing_id, target_profile_id)
  )
);

create schema if not exists private;

create table private.moderator_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  granted_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table private.listing_moderation_events (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete restrict,
  moderator_user_id uuid references auth.users (id) on delete set null,
  action text not null check (action in ('approve', 'reject', 'remove', 'restore', 'archive_images')),
  reason text check (reason is null or length(reason) <= 2000),
  created_at timestamptz not null default now()
);

create table private.report_moderation_events (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id) on delete restrict,
  moderator_user_id uuid references auth.users (id) on delete set null,
  previous_status public.report_status not null,
  new_status public.report_status not null,
  created_at timestamptz not null default now()
);

create table private.storage_cleanup_queue (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null check (bucket_id in ('listing-staging', 'listing-images')),
  object_name text not null,
  reason text not null check (reason in (
    'public_to_private_archive', 'staging_source', 'abandoned_staging', 'account_deletion'
  )),
  attempts integer not null default 0 check (attempts >= 0),
  last_error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (bucket_id, object_name)
);

create table private.image_upload_reservations (
  id uuid primary key default gen_random_uuid(),
  storage_path text not null unique,
  listing_id uuid not null references public.listings (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  purpose text not null check (purpose in ('new_image', 'image_archive')),
  image_id uuid references public.listing_images (id) on delete cascade,
  sort_order integer not null check (sort_order between 0 and 7),
  alt_text text not null check (length(btrim(alt_text)) between 1 and 240),
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint image_reservation_target check (
    (purpose = 'new_image' and image_id is null)
    or (purpose = 'image_archive' and image_id is not null)
  )
);

create index listings_public_feed_idx
  on public.listings (created_at desc, id desc)
  where status = 'active';
create index listings_category_feed_idx
  on public.listings (category_id, created_at desc, id desc)
  where status = 'active';
create index listings_location_feed_idx
  on public.listings (location_id, created_at desc, id desc)
  where status = 'active';
create index listings_seller_status_idx
  on public.listings (seller_profile_id, status, updated_at desc);
create index listing_images_listing_idx
  on public.listing_images (listing_id, sort_order);
create index favorites_listing_idx on public.favorites (listing_id);
create index reports_reporter_created_idx
  on public.reports (reporter_user_id, created_at desc);
create index reports_listing_target_idx
  on public.reports (target_listing_id)
  where target_listing_id is not null;
create index reports_profile_target_idx
  on public.reports (target_profile_id)
  where target_profile_id is not null;
create index moderation_events_listing_created_idx
  on private.listing_moderation_events (listing_id, created_at desc);
create index report_moderation_events_report_created_idx
  on private.report_moderation_events (report_id, created_at desc);
create index storage_cleanup_pending_idx
  on private.storage_cleanup_queue (created_at)
  where completed_at is null;
create index image_upload_reservations_listing_idx
  on private.image_upload_reservations (listing_id, expires_at);

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger listings_set_updated_at
before update on public.listings
for each row execute function private.set_updated_at();

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_name text;
begin
  normalized_name := nullif(btrim(new.raw_user_meta_data ->> 'display_name'), '');
  if normalized_name is null or length(normalized_name) > 80 then
    normalized_name := 'New K-Mark member';
  end if;

  insert into public.profiles (auth_user_id, display_name, onboarding_complete)
  values (new.id, normalized_name, false);
  return new;
end;
$$;

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_auth_user();