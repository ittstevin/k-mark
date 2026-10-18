create function public.create_listing_draft(
  p_category_id uuid,
  p_location_id uuid,
  p_title text,
  p_description text,
  p_price_kes integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_listing_id uuid := pg_catalog.gen_random_uuid();
  v_slug text;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'A complete account is required.';
  end if;
  if pg_catalog.length(pg_catalog.btrim(p_title)) not between 1 and 100
     or pg_catalog.length(pg_catalog.btrim(p_description)) not between 1 and 5000
     or p_price_kes not between 0 and 100000000 then
    raise exception using errcode = '23514', message = 'Invalid listing fields.';
  end if;
  if not exists (select 1 from public.categories c where c.id = p_category_id and c.is_active)
     or not exists (select 1 from public.locations l where l.id = p_location_id and l.is_active) then
    raise exception using errcode = '23503', message = 'Choose an active category and location.';
  end if;

  v_slug := pg_catalog.btrim(
    pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.btrim(p_title)), '[^a-z0-9]+', '-', 'g'),
    '-'
  );
  v_slug := pg_catalog.left(pg_catalog.coalesce(nullif(v_slug, ''), 'listing'), 80)
    || '-' || pg_catalog.left(pg_catalog.replace(v_listing_id::text, '-', ''), 12);

  insert into public.listings (
    id, seller_profile_id, category_id, location_id, slug, title, description, price_kes
  ) values (
    v_listing_id, v_profile_id, p_category_id, p_location_id, v_slug,
    pg_catalog.btrim(p_title), pg_catalog.btrim(p_description), p_price_kes
  );
  return v_listing_id;
end;
$$;

create function public.complete_my_profile(p_display_name text, p_location_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
     or pg_catalog.length(pg_catalog.btrim(p_display_name)) not between 1 and 80
     or not exists (select 1 from public.locations l where l.id = p_location_id and l.is_active) then
    raise exception using errcode = '23514', message = 'A valid display name and active broad location are required.';
  end if;
  update public.profiles p
  set display_name = pg_catalog.btrim(p_display_name),
      location_id = p_location_id,
      onboarding_complete = true
  where p.auth_user_id = auth.uid() and not p.is_anonymized;
  if not found then
    raise exception using errcode = '42501', message = 'The profile is unavailable.';
  end if;
end;
$$;

create function public.submit_listing(p_listing_id uuid)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare v_profile_id uuid := private.current_profile_id();
begin
  perform 1 from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id and l.status = 'draft'
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Only your draft can be submitted.';
  end if;
  if exists (select 1 from private.image_upload_reservations r
    where r.listing_id = p_listing_id and r.expires_at > pg_catalog.now()) then
    raise exception using errcode = '55P03', message = 'Finish or wait for pending image uploads before submission.';
  end if;
  update public.listings l
  set status = 'pending_review', submitted_at = pg_catalog.now()
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id and l.status = 'draft';
  if not found then
    raise exception using errcode = '42501', message = 'Only your draft can be submitted.';
  end if;
  return 'pending_review';
end;
$$;

create function public.withdraw_listing(p_listing_id uuid)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare v_profile_id uuid := private.current_profile_id();
begin
  update public.listings l
  set status = 'draft', submitted_at = null
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id and l.status = 'pending_review';
  if not found then
    raise exception using errcode = '42501', message = 'Only your pending listing can be withdrawn.';
  end if;
  return 'draft';
end;
$$;

create function private.archive_published_listing_images(
  p_listing_id uuid,
  p_archived_images jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_auth_id uuid;
  v_image record;
  v_public_path text;
begin
  select p.auth_user_id into v_owner_auth_id
  from public.listings l
  join public.profiles p on p.id = l.seller_profile_id
  where l.id = p_listing_id;
  if v_owner_auth_id is null then
    raise exception using errcode = '23514', message = 'Listing owner profile is unavailable.';
  end if;
  if pg_catalog.jsonb_typeof(p_archived_images) <> 'array'
     or pg_catalog.jsonb_array_length(p_archived_images) <> (
       select pg_catalog.count(*) from public.listing_images i
       where i.listing_id = p_listing_id and i.published_path is not null
     ) then
    raise exception using errcode = '23514', message = 'Every public image must first have a private archive.';
  end if;

  for v_image in
    select x.image_id, x.staging_path, x.published_path
    from pg_catalog.jsonb_to_recordset(p_archived_images) as x(
      image_id uuid, staging_path text, published_path text
    )
  loop
    if not private.is_moderator() and not exists (
      select 1 from private.image_upload_reservations r
      where r.image_id = v_image.image_id
        and r.listing_id = p_listing_id
        and r.user_id = v_owner_auth_id
        and r.purpose = 'image_archive'
        and r.storage_path = v_image.staging_path
        and r.completed_at is not null
    ) then
      raise exception using errcode = '42501', message = 'A completed private archive reservation is required.';
    end if;
    update public.listing_images i
    set staging_path = v_image.staging_path, published_path = null
    where i.id = v_image.image_id and i.listing_id = p_listing_id
      and i.published_path is not null
      and i.published_path = v_image.published_path
      and v_image.staging_path ~ ('^' || v_owner_auth_id::text || '/' || p_listing_id::text || '/[A-Za-z0-9._-]+$')
      and exists (select 1 from storage.objects o
        where o.bucket_id = 'listing-staging' and o.name = v_image.staging_path);
    if not found then
      raise exception using errcode = '42501', message = 'A private image archive could not be verified.';
    end if;
    delete from private.image_upload_reservations r
    where r.image_id = v_image.image_id and r.storage_path = v_image.staging_path
      and r.purpose = 'image_archive';
    perform private.enqueue_storage_cleanup('listing-images', v_image.published_path, 'public_to_private_archive');
    perform private.enqueue_storage_cleanup('listing-images', v_image.published_path, 'public_to_private_archive');
  end loop;

  if exists (select 1 from public.listing_images i where i.listing_id = p_listing_id and i.published_path is not null) then
    raise exception using errcode = '23514', message = 'Every public image must be archived before hiding the listing.';
  end if;
end;
$$;

revoke all on function private.archive_published_listing_images(uuid, jsonb) from public, anon, authenticated;

create function public.pause_listing(p_listing_id uuid, p_archived_images jsonb default '[]'::jsonb)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_listing public.listings%rowtype;
begin
  select * into v_listing from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id and l.status = 'active'
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Only your active listing can be paused.';
  end if;
  perform private.archive_published_listing_images(p_listing_id, p_archived_images);
  update public.listings set status = 'paused' where id = p_listing_id;
  return 'paused';
end;
$$;

create function public.mark_listing_sold(p_listing_id uuid, p_archived_images jsonb default '[]'::jsonb)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_listing public.listings%rowtype;
begin
  select * into v_listing from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id and l.status in ('active', 'paused')
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Only your active or paused listing can be sold.';
  end if;
  perform private.archive_published_listing_images(p_listing_id, p_archived_images);
  update public.listings set status = 'sold', sold_at = pg_catalog.now() where id = p_listing_id;
  return 'sold';
end;
$$;

create function public.save_listing_content(
  p_listing_id uuid,
  p_category_id uuid,
  p_location_id uuid,
  p_title text,
  p_description text,
  p_price_kes integer,
  p_save_as_draft boolean default false,
  p_archived_images jsonb default '[]'::jsonb
)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_listing public.listings%rowtype;
  v_image record;
  v_next_status public.listing_status;
begin
  if pg_catalog.length(pg_catalog.btrim(p_title)) not between 1 and 100
     or pg_catalog.length(pg_catalog.btrim(p_description)) not between 1 and 5000
     or p_price_kes not between 0 and 100000000 then
    raise exception using errcode = '23514', message = 'Invalid listing fields.';
  end if;
  if not exists (select 1 from public.categories c where c.id = p_category_id and c.is_active)
     or not exists (select 1 from public.locations l where l.id = p_location_id and l.is_active) then
    raise exception using errcode = '23503', message = 'Choose an active category and location.';
  end if;

  select * into v_listing from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id
  for update;
  if not found or v_listing.status not in ('draft', 'rejected', 'active', 'paused') then
    raise exception using errcode = '42501', message = 'This listing cannot be edited by this seller.';
  end if;

  if v_listing.status in ('active', 'paused') then
    perform private.archive_published_listing_images(p_listing_id, p_archived_images);
    v_next_status := case when p_save_as_draft
      then 'draft'::public.listing_status else 'pending_review'::public.listing_status end;
  elsif v_listing.status = 'rejected' and not p_save_as_draft then
    v_next_status := 'pending_review';
  else
    v_next_status := 'draft';
  end if;

  update public.listings l
  set category_id = p_category_id,
      location_id = p_location_id,
      title = pg_catalog.btrim(p_title),
      description = pg_catalog.btrim(p_description),
      price_kes = p_price_kes,
      status = v_next_status,
      submitted_at = case when v_next_status = 'pending_review' then pg_catalog.now() else null end
  where l.id = p_listing_id;
  return v_next_status;
end;
$$;

create function public.moderator_decide_listing(
  p_listing_id uuid,
  p_action text,
  p_reason text default null,
  p_archived_images jsonb default '[]'::jsonb
)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing public.listings%rowtype;
  v_next_status public.listing_status;
begin
  if not private.is_moderator() then
    raise exception using errcode = '42501', message = 'Moderator permission is required.';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Listing not found.';
  end if;

  if p_action = 'approve' and v_listing.status = 'pending_review' then
    v_next_status := 'approved';
    update public.listings set status = v_next_status, approved_at = pg_catalog.now() where id = p_listing_id;
  elsif p_action = 'reject' and v_listing.status = 'pending_review' then
    v_next_status := 'rejected';
    update public.listings set status = v_next_status where id = p_listing_id;
  elsif p_action = 'remove' and v_listing.status in ('active', 'paused', 'sold') then
    perform private.archive_published_listing_images(p_listing_id, p_archived_images);
    v_next_status := 'removed';
    update public.listings set status = v_next_status where id = p_listing_id;
  elsif p_action = 'restore' and v_listing.status = 'removed'
      and not exists (
        select 1 from public.listing_images i
        where i.listing_id = p_listing_id and i.published_path is not null
      ) then
    v_next_status := 'paused';
    update public.listings set status = v_next_status where id = p_listing_id;
  else
    raise exception using errcode = '23514', message = 'This moderation transition is not allowed.';
  end if;

  insert into private.listing_moderation_events (listing_id, moderator_user_id, action, reason)
  values (p_listing_id, auth.uid(), p_action, nullif(pg_catalog.btrim(p_reason), ''));
  return v_next_status;
end;
$$;

create function public.publish_approved_listing(
  p_listing_id uuid,
  p_images jsonb
)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing public.listings%rowtype;
  v_owner_auth_id uuid;
  v_image record;
  v_image_count integer;
begin
  if not private.is_moderator() then
    raise exception using errcode = '42501', message = 'Moderator permission is required.';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing_id for update;
  if not found or v_listing.status <> 'approved'
     or not exists (select 1 from private.listing_moderation_events e
       where e.listing_id = p_listing_id and e.action = 'approve') then
    raise exception using errcode = '23514', message = 'A recorded moderator approval is required.';
  end if;
  select p.auth_user_id into v_owner_auth_id
  from public.profiles p where p.id = v_listing.seller_profile_id;
  select pg_catalog.count(*) into v_image_count
  from public.listing_images i where i.listing_id = p_listing_id;
  if pg_catalog.jsonb_typeof(p_images) <> 'array'
     or pg_catalog.jsonb_array_length(p_images) <> v_image_count then
    raise exception using errcode = '23514', message = 'Publication must include every listing image.';
  end if;

  for v_image in
    select x.image_id, x.published_path
    from pg_catalog.jsonb_to_recordset(p_images) as x(image_id uuid, published_path text)
  loop
    update public.listing_images i
    set published_path = v_image.published_path, staging_path = null
    where i.id = v_image.image_id and i.listing_id = p_listing_id
      and i.staging_path is not null and i.published_path is null
      and v_image.published_path ~ ('^' || v_owner_auth_id::text || '/' || p_listing_id::text || '/[A-Za-z0-9._-]+$')
      and not exists (select 1 from private.storage_cleanup_queue q
        where q.bucket_id = 'listing-images' and q.object_name = v_image.published_path and q.completed_at is null)
      and exists (select 1 from storage.objects o
        where o.bucket_id = 'listing-images' and o.name = v_image.published_path);
    if not found then
      raise exception using errcode = '42501', message = 'A public image object could not be verified.';
    end if;
    perform private.enqueue_storage_cleanup('listing-staging', v_image.staging_path, 'staging_source');
  end loop;

  if exists (
    select 1 from public.listing_images i
    where i.listing_id = p_listing_id and (i.staging_path is not null or i.published_path is null)
  ) then
    raise exception using errcode = '23514', message = 'All images must be published before activation.';
  end if;
  update public.listings set status = 'active' where id = p_listing_id and status = 'approved';
  return 'active';
end;
$$;

create function public.resume_listing(
  p_listing_id uuid,
  p_republished_images jsonb default '[]'::jsonb
)
returns public.listing_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_listing public.listings%rowtype;
  v_owner_auth_id uuid;
  v_image record;
  v_staging_count integer;
begin
  select * into v_listing from public.listings l
  where l.id = p_listing_id and l.seller_profile_id = v_profile_id
  for update;
  if not found or v_listing.status <> 'paused' or v_listing.approved_at is null then
    raise exception using errcode = '42501', message = 'Only your approved paused listing can resume.';
  end if;
  select p.auth_user_id into v_owner_auth_id from public.profiles p where p.id = v_profile_id;
  select pg_catalog.count(*) into v_staging_count from public.listing_images i
  where i.listing_id = p_listing_id and i.staging_path is not null;
  if pg_catalog.jsonb_typeof(p_republished_images) <> 'array'
     or pg_catalog.jsonb_array_length(p_republished_images) <> v_staging_count then
    raise exception using errcode = '23514', message = 'Republish every archived image before resuming.';
  end if;

  for v_image in
    select x.image_id, x.published_path
    from pg_catalog.jsonb_to_recordset(p_republished_images) as x(image_id uuid, published_path text)
  loop
    update public.listing_images i
    set published_path = v_image.published_path, staging_path = null
    where i.id = v_image.image_id and i.listing_id = p_listing_id
      and i.staging_path is not null and i.published_path is null
      and v_image.published_path ~ ('^' || v_owner_auth_id::text || '/' || p_listing_id::text || '/[A-Za-z0-9._-]+$')
      and not exists (select 1 from private.storage_cleanup_queue q
        where q.bucket_id = 'listing-images' and q.object_name = v_image.published_path and q.completed_at is null)
      and exists (select 1 from storage.objects o
        where o.bucket_id = 'listing-images' and o.name = v_image.published_path);
    if not found then
      raise exception using errcode = '42501', message = 'A republished image object could not be verified.';
    end if;
    perform private.enqueue_storage_cleanup('listing-staging', v_image.staging_path, 'staging_source');
  end loop;
  if exists (
    select 1 from public.listing_images i
    where i.listing_id = p_listing_id and (i.staging_path is not null or i.published_path is null)
  ) then
    raise exception using errcode = '23514', message = 'All archived images must be republished before resume.';
  end if;
  update public.listings set status = 'active' where id = p_listing_id and status = 'paused';
  return 'active';
end;
$$;

create function public.set_report_status(p_report_id uuid, p_status public.report_status)
returns public.report_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous_status public.report_status;
begin
  if not private.is_moderator() then
    raise exception using errcode = '42501', message = 'Moderator permission is required.';
  end if;
  if p_status not in ('reviewing', 'resolved', 'dismissed') then
    raise exception using errcode = '23514', message = 'Invalid report transition.';
  end if;
  select r.status into v_previous_status
  from public.reports r where r.id = p_report_id for update;
  if not found or v_previous_status not in ('open', 'reviewing') then
    raise exception using errcode = '23514', message = 'Report cannot be updated.';
  end if;
  update public.reports r
  set status = p_status,
      reviewed_at = case when p_status in ('resolved', 'dismissed') then pg_catalog.now() else null end
  where r.id = p_report_id;
  insert into private.report_moderation_events (
    report_id, moderator_user_id, previous_status, new_status
  ) values (p_report_id, auth.uid(), v_previous_status, p_status);
  return p_status;
end;
$$;

revoke all on function private.archive_published_listing_images(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.create_listing_draft(uuid, uuid, text, text, integer) from public, anon, authenticated;
revoke all on function public.complete_my_profile(text, uuid) from public, anon, authenticated;
revoke all on function public.submit_listing(uuid) from public, anon, authenticated;
revoke all on function public.withdraw_listing(uuid) from public, anon, authenticated;
revoke all on function public.pause_listing(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.mark_listing_sold(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.save_listing_content(uuid, uuid, uuid, text, text, integer, boolean, jsonb) from public, anon, authenticated;
revoke all on function public.moderator_decide_listing(uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.publish_approved_listing(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.resume_listing(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.set_report_status(uuid, public.report_status) from public, anon, authenticated;

grant execute on function public.create_listing_draft(uuid, uuid, text, text, integer) to authenticated;
grant execute on function public.complete_my_profile(text, uuid) to authenticated;
grant execute on function public.submit_listing(uuid) to authenticated;
grant execute on function public.withdraw_listing(uuid) to authenticated;
grant execute on function public.pause_listing(uuid, jsonb) to authenticated;
grant execute on function public.mark_listing_sold(uuid, jsonb) to authenticated;
grant execute on function public.save_listing_content(uuid, uuid, uuid, text, text, integer, boolean, jsonb) to authenticated;
grant execute on function public.moderator_decide_listing(uuid, text, text, jsonb) to authenticated;
grant execute on function public.publish_approved_listing(uuid, jsonb) to authenticated;
grant execute on function public.resume_listing(uuid, jsonb) to authenticated;
grant execute on function public.set_report_status(uuid, public.report_status) to authenticated;