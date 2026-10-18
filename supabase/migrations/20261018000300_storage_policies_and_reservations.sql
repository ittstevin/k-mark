alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema private revoke execute on functions from public;

grant select on storage.objects to anon, authenticated;
grant insert on storage.objects to authenticated;

create function private.can_read_staging_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := storage.foldername(p_name);
begin
  return (select private.is_moderator())
    or (auth.uid() is not null
    and pg_catalog.array_length(v_parts, 1) = 2
    and v_parts[1] = (select auth.uid())::text
    and exists (
      select 1
      from public.listings l
      where l.id::text = v_parts[2]
        and l.seller_profile_id = private.current_profile_id()
        and l.status in ('draft', 'pending_review', 'rejected', 'paused', 'sold')
      ));
end;
$$;

create function private.can_insert_staging_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := storage.foldername(p_name);
  v_listing_id uuid;
begin
  if auth.uid() is null or pg_catalog.array_length(v_parts, 1) <> 2
     or v_parts[1] <> (select auth.uid())::text then
    return false;
  end if;
  begin
    v_listing_id := v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  return exists (
    select 1 from public.listings l
    join private.image_upload_reservations r on r.listing_id = l.id
    where l.id = v_listing_id
      and l.seller_profile_id = private.current_profile_id()
      and r.user_id = (select auth.uid())
      and r.storage_path = p_name
      and (
        (r.purpose = 'new_image' and l.status in ('draft', 'rejected'))
        or (r.purpose = 'image_archive' and l.status in ('active', 'paused'))
      )
      and r.expires_at > pg_catalog.now()
  );
end;
$$;

revoke all on function private.can_read_staging_object(text) from public, anon, authenticated;
revoke all on function private.can_insert_staging_object(text) from public, anon, authenticated;
grant execute on function private.can_read_staging_object(text) to authenticated;
grant execute on function private.can_insert_staging_object(text) to authenticated;

on storage.objects for select to authenticated
using (bucket_id = 'listing-staging' and private.can_read_staging_object(name));

create policy listing_staging_insert_reserved
on storage.objects for insert to authenticated
with check (
  bucket_id = 'listing-staging'
  and owner_id = (select auth.uid())::text
  and private.can_insert_staging_object(name)
);

create policy public_image_objects_not_listable
on storage.objects for select to anon, authenticated
using (false);

create function public.reserve_listing_image_upload(
  p_listing_id uuid,
  p_sort_order integer,
  p_alt_text text,
  p_extension text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_path text;
  v_count integer;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'A complete account is required.';
  end if;
  if p_extension not in ('jpg', 'jpeg', 'png', 'webp')
     or p_sort_order < 0 or p_sort_order > 7
     or length(btrim(p_alt_text)) not between 1 and 240 then
    raise exception using errcode = '23514', message = 'Invalid image metadata or file extension.';
  end if;

  perform 1 from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id
    and l.status in ('draft', 'rejected')
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Withdraw a pending listing before changing its images.';
  end if;

  insert into private.storage_cleanup_queue (bucket_id, object_name, reason)
  select 'listing-staging', r.storage_path, 'abandoned_staging'
  from private.image_upload_reservations r
  where r.expires_at <= pg_catalog.now() and r.completed_at is null
  on conflict (bucket_id, object_name) do nothing;
  delete from private.image_upload_reservations r
  where r.expires_at <= pg_catalog.now() and r.completed_at is null;
  select
    (select pg_catalog.count(*) from public.listing_images i where i.listing_id = p_listing_id)
    +
    (select pg_catalog.count(*) from private.image_upload_reservations r
      where r.listing_id = p_listing_id and r.purpose = 'new_image'
        and r.completed_at is null and r.expires_at > pg_catalog.now())
  into v_count;
  if v_count >= 8 then
    raise exception using errcode = '23514', message = 'A listing can have at most eight images.';
  end if;
  if exists (select 1 from public.listing_images i where i.listing_id = p_listing_id and i.sort_order = p_sort_order)
     or exists (select 1 from private.image_upload_reservations r
       where r.listing_id = p_listing_id and r.purpose = 'new_image'
         and r.completed_at is null and r.sort_order = p_sort_order and r.expires_at > pg_catalog.now()) then
    raise exception using errcode = '23505', message = 'That image order is already in use.';
  end if;

  v_path := (select auth.uid())::text || '/' || p_listing_id::text || '/' || gen_random_uuid()::text || '.' || p_extension;
  insert into private.image_upload_reservations (
    storage_path, listing_id, user_id, purpose, image_id, sort_order, alt_text, expires_at
  ) values (
    v_path, p_listing_id, (select auth.uid()), 'new_image', null,
    p_sort_order, btrim(p_alt_text), pg_catalog.now() + interval '15 minutes'
  );
  return v_path;
end;
$$;

create function public.reserve_listing_image_archive(
  p_listing_id uuid,
  p_image_id uuid,
  p_extension text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_path text;
  v_image public.listing_images%rowtype;
begin
  if v_profile_id is null or p_extension not in ('jpg', 'jpeg', 'png', 'webp') then
    raise exception using errcode = '42501', message = 'A valid owner and supported image type are required.';
  end if;
  perform 1 from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id and l.status in ('active', 'paused')
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Only your active or paused listing can archive photos.';
  end if;
  select * into v_image from public.listing_images i
  where i.id = p_image_id and i.listing_id = p_listing_id and i.published_path is not null
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'The published image was not found.';
  end if;
  if exists (select 1 from private.image_upload_reservations r
    where r.image_id = p_image_id and r.purpose = 'image_archive' and r.expires_at > pg_catalog.now()) then
    raise exception using errcode = '55P03', message = 'An archive upload is already reserved for this image.';
  end if;

  v_path := (select auth.uid())::text || '/' || p_listing_id::text || '/' || pg_catalog.gen_random_uuid()::text || '.' || p_extension;
  insert into private.image_upload_reservations (
    storage_path, listing_id, user_id, purpose, image_id, sort_order, alt_text, expires_at
  ) values (
    v_path, p_listing_id, (select auth.uid()), 'image_archive', p_image_id,
    v_image.sort_order, v_image.alt_text, pg_catalog.now() + interval '15 minutes'
  );
  return v_path;
end;
$$;

create function public.complete_listing_image_upload(p_storage_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reservation private.image_upload_reservations%rowtype;
  v_image_id uuid := gen_random_uuid();
begin
  select * into v_reservation
  from private.image_upload_reservations r
  where r.storage_path = p_storage_path
    and r.completed_at is null
    and r.expires_at > pg_catalog.now()
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'A valid upload reservation is required.';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'listing-staging'
      and o.name = p_storage_path
  ) then
    raise exception using errcode = '42501', message = 'The uploaded object is not owned by this account.';
  end if;

  if v_reservation.purpose = 'image_archive' then
    perform 1 from public.listings l
    where l.id = v_reservation.listing_id
      and exists (select 1 from public.profiles p
        where p.id = l.seller_profile_id and p.auth_user_id = v_reservation.user_id)
      and l.status in ('active', 'paused')
    for update;
    if not found or not exists (
      select 1 from public.listing_images i
      where i.id = v_reservation.image_id and i.listing_id = v_reservation.listing_id
        and i.published_path is not null
    ) then
      raise exception using errcode = '42501', message = 'The listing image is no longer eligible for archiving.';
    end if;
    update private.image_upload_reservations r
    set completed_at = pg_catalog.now()
    where r.id = v_reservation.id;
    return v_reservation.image_id;
  end if;

  perform 1 from public.listings l
  where l.id = v_reservation.listing_id
    and exists (select 1 from public.profiles p
      where p.id = l.seller_profile_id and p.auth_user_id = v_reservation.user_id)
    and l.status in ('draft', 'rejected')
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'The listing is no longer editable.';
  end if;
  if (select pg_catalog.count(*) from public.listing_images i where i.listing_id = v_reservation.listing_id) >= 8 then
    raise exception using errcode = '23514', message = 'A listing can have at most eight images.';
  end if;

  insert into public.listing_images (id, listing_id, staging_path, alt_text, sort_order)
  values (v_image_id, v_reservation.listing_id, p_storage_path, v_reservation.alt_text, v_reservation.sort_order);
  delete from private.image_upload_reservations r where r.id = v_reservation.id;
  return v_image_id;
end;
$$;

revoke all on function public.reserve_listing_image_upload(uuid, integer, text, text) from public, anon, authenticated;
revoke all on function public.reserve_listing_image_archive(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.complete_listing_image_upload(text) from public, anon, authenticated;
grant execute on function public.reserve_listing_image_upload(uuid, integer, text, text) to authenticated;
grant execute on function public.reserve_listing_image_archive(uuid, uuid, text) to authenticated;
grant execute on function public.complete_listing_image_upload(text) to service_role;