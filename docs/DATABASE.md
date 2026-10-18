# K-Mark Database Design

Status: initial local-only schema/migrations are drafted under `supabase/`, but have not been applied or tested because the Supabase CLI, Docker, and PostgreSQL client are unavailable in the current environment. No hosted project has been created or changed.

## Current Data Model

The frontend demo data and types are in `app/data/listings.ts`. `ListingCategory`, `Listing`, `categoryOptions`, and `listings` are in-memory presentation data; IDs such as `camera-01`, display-relative `posted`, `emoji`, image URLs, seller demo labels, and `featured` are not database identifiers or trusted fields. Use UUID database IDs and map rows into the existing UI view model on the server.

## Tables

All timestamps use `timestamptz`; record creation/update timestamps are database-managed. Enable RLS on every API-exposed table and explicitly configure grants as well as policies.

Define `listing_status` with exactly `draft`, `pending_review`, `approved`, `active`, `paused`, `sold`, `rejected`, and `removed`. Define `report_status` with `open`, `reviewing`, `resolved`, and `dismissed`. Treat these as reviewed migration types; do not accept enum values supplied directly by a client for protected state changes.

### `locations`

Controlled MVP location vocabulary, seeded through migrations:

- Seed Nairobi areas: Westlands, Kilimani, Kasarani, and Roysambu.
- Seed Kiambu areas: Kiambu Town, Ruiru, Kikuyu, and Thika.
- Treat the current mock-data area names as seed labels, not as free-form user input.

- `id uuid primary key`.
- `county text not null check (county in ('Nairobi', 'Kiambu'))`.
- `area_slug text not null`, `area_name text not null`, `is_active boolean not null default true`, `sort_order integer not null`.
- `unique (county, area_slug)`.

Listings and public profiles reference `locations.id`; callers cannot invent an area string. Future counties/areas are introduced through reviewed migrations. Expand the county constraint in a migration when the service area expands.

### `profiles`

One profile per Auth account, with a surrogate profile ID so anonymized seller references can remain valid after account deletion:

- `id uuid primary key default gen_random_uuid()`.
- `auth_user_id uuid unique null references auth.users(id) on delete set null`.
- `display_name text not null` with a short length bound and a safe default for incomplete onboarding.
- `location_id uuid null references locations(id) on delete set null`.
- `is_anonymized boolean not null default false`, `created_at`, `updated_at`.

Public profile queries expose only `display_name` and broad location. Email remains in `auth.users`; phone, exact address, and private account data are not public profile fields. Anonymization replaces the display name with a generic deleted-account label, clears location and other personal fields, and retains the profile UUID only where a listing/report still needs a stable non-identifying reference.

### `categories`

- `id uuid primary key`, `slug text unique not null`, `name text not null`.
- `sort_order integer not null`, `is_active boolean not null default true`, `created_at`.

Seed the seven existing categories. Keep icons in frontend configuration keyed by slug. Client roles read active categories only; migrations/trusted operators maintain the rows.

### `listings`

- `id uuid primary key default gen_random_uuid()`.
- `seller_profile_id uuid not null references profiles(id) on delete restrict`.
- `category_id uuid not null references categories(id) on delete restrict`.
- `location_id uuid not null references locations(id) on delete restrict`.
- `slug text unique not null`, generated and collision-checked server-side.
- `title text not null` (maximum 100 characters); `description text not null` (maximum 5,000 characters).
- `price_kes integer not null check (price_kes between 0 and 100000000)`.
- `status listing_status not null default 'draft'`.
- `created_at`, `updated_at`, `submitted_at timestamptz null`, `approved_at timestamptz null`, `sold_at timestamptz null`.

`integer` safely represents the approved KSh 100,000,000 maximum in JavaScript and PostgreSQL. Database IDs, seller/category/location references, status, approval fields, and timestamps are never accepted from listing form input. Do not persist the demo `posted` label; derive it from `created_at`. Do not expose a seller-controlled `featured` value.

### `listing_images`

- `id uuid primary key default gen_random_uuid()`.
- `listing_id uuid not null references listings(id) on delete cascade`.
- `staging_path text unique not null`; `published_path text unique null`.
- `alt_text text not null` with a length bound.
- `sort_order integer not null check (sort_order between 0 and 7)`.
- `created_at`; `unique (listing_id, sort_order)` (defer the constraint during reorder transactions if needed).
- A check requires exactly one of `staging_path` or `published_path` to be present.

The eight-image maximum is a cross-row limit, so enforce it in the upload server operation/database function while locking the listing; test concurrent attempts. No minimum image count is required for MVP submission. `staging_path` names an object in the private staging bucket and may be cleared only after a verified public copy is recorded in `published_path`. A check requires at least one path to be present. Return image metadata to the public only for active listings. The first ordered image is the cover.

### `favorites`

- `user_id uuid not null references auth.users(id) on delete cascade`.
- `listing_id uuid not null references listings(id) on delete cascade`.
- `created_at`; primary key `(user_id, listing_id)`.

This enforces one favourite per user/listing pair. Signed-out favourites may remain in browser session storage; merging them at sign-in must be an explicit validated operation.

### `reports`

- `id uuid primary key`; `reporter_user_id uuid null references auth.users(id) on delete set null`.
- `reporter_profile_id uuid null references profiles(id) on delete set null`.
- `target_listing_id uuid null references listings(id) on delete set null`; `target_profile_id uuid null references profiles(id) on delete set null`.
- A check constraint requires exactly one target. Keep a non-personal `target_reference_snapshot uuid` and minimal evidence needed to review a report if the foreign-key target is later removed.
- `reason text not null` from an allow-list; bounded `details text null`.
- `status report_status not null default 'open'` (`open`, `reviewing`, `resolved`, `dismissed`), `created_at`, `reviewed_at timestamptz null`.

Only the reporter can read their own report; reported users cannot read reporter identity or report details. Moderation status is changed only by moderator-authorized operations. Retain the minimum necessary evidence for a duration confirmed against applicable Kenyan requirements; do not invent a legal retention period.

### Private moderation records

In a non-exposed `private` schema, add:

- `moderator_roles(user_id uuid primary key references auth.users(id) on delete cascade, granted_by uuid null references auth.users(id) on delete set null, created_at timestamptz not null, revoked_at timestamptz null)`. No client role receives table access or mutation grants. Only a trusted operator provisions/revokes roles.
- `listing_moderation_events(id uuid primary key, listing_id uuid not null references listings(id) on delete restrict, moderator_user_id uuid null references auth.users(id) on delete set null, action text not null, reason text null, created_at timestamptz not null)`. No public or seller read access; use this for review/rejection/removal/restoration audit.
- `image_upload_reservations` tracks user/listing/path, purpose, image order/alt text, expiry, and completion. The eight-image cap counts attached images plus unexpired reservations while the listing row is locked.
- `storage_cleanup_queue` uniquely queues `(bucket_id, object_name)` with reason, attempts, last error code, and completion time. It is private and idempotent; a future server worker processes it.

Moderator checks use a private helper with `SECURITY DEFINER`, fixed `SET search_path = ''`, fully schema-qualified references, and execute permission revoked from `PUBLIC`/`anon` and granted only as required to `authenticated`. Mutation functions repeat the moderator check; knowing a function name or reaching a hidden page grants nothing.

## Listing State-Transition Table

`approved` is a short, non-public publishing state: a moderator has approved the content and the server is copying/verifying media. Only after that succeeds does the controlled function change it to `active`.

| From | Action and actor | To | Visibility/notes |
| --- | --- | --- | --- |
| New | Server creates seller-owned draft | `draft` | Private; staging images only. |
| `draft` | Seller submits | `pending_review` | Private; seller cannot set `active`. |
| `pending_review` | Seller withdraws | `draft` | Private; seller edits then resubmits. |
| `pending_review` | Moderator approves | `approved` | Not publicly listed; approved-media publication is in progress. |
| `approved` | Trusted publication function verifies all images | `active` | Public listing and published image paths become available. |
| `pending_review` | Moderator rejects | `rejected` | Private; seller can edit/resubmit. |
| `rejected` | Seller edits and resubmits | `pending_review` | Private; requires a new moderator decision. |
| `active` | Seller pauses | `paused` | Hidden from browse; content remains approved. |
| `paused` | Seller resumes unchanged listing | `active` | Public again; no new approval because content is unchanged. |
| `active` or `paused` | Seller changes title, description, price, category, location, or images | `pending_review` | Immediately hidden; reapproval required. Seller can instead save edits as `draft`. |
| `active` or `paused` | Seller marks sold | `sold` | Not in public browse; terminal for seller. |
| `active`, `paused`, or `sold` | Moderator removes | `removed` | Hidden; copy public images to verified private archive paths before deleting public objects. Seller cannot restore or edit around removal. |
| `removed` | Moderator restores | `paused` | Not public until seller resumes; archived images remain private. Restoration is audited. |

All other transitions are denied. In particular, sellers cannot set `approved`, `active` after rejection/removal, `removed`, reviewer IDs, or moderation-event fields. The final `approved -> active` function must verify a recorded moderator approval event and a complete verified published-image set; merely knowing/calling the RPC cannot activate a listing. Database mutation functions enforce transitions under a row lock; Server Actions also validate for good errors, but are not the security boundary. Hard deletion is limited to an unsubmitted draft with no report/audit references and always triggers retryable image cleanup.

## Account Creation and Deletion

An `auth.users` insert trigger creates a minimal profile in the same transaction, using a validated display name or safe default. If profile creation fails, signup fails atomically rather than leaving a user without the required seller profile. The onboarding Server Action is idempotent and may complete the default profile; it does not trust Auth `user_metadata` for roles or authorization.

Deletion is a controlled server-side workflow: take all owned listings offline (`removed`), delete favourites, remove moderator role, clear public profile location/name and mark the profile anonymized, remove avatars and media according to retention policy, then delete the Auth user. `profiles.auth_user_id ON DELETE SET NULL` and retained anonymized `profiles.id` keep listing seller references intact; report Auth/profile references use `SET NULL` so minimum report evidence can remain without a live identity. The favourites FK and moderator-role FK cascade on Auth deletion. Do not hard-delete profile tombstones while listings/audit records reference them. The exact report evidence and retention interval require legal/privacy confirmation before implementation.

## Storage Publication and Cleanup

Use a private `listing-staging` bucket with a 5 MB limit defined exactly as 5,000,000 bytes, JPEG/PNG/WebP allow-list, and no public reads. It stores draft/pending uploads and private archive copies of removed listings' photos. Object paths are generated server-side as `<auth-user-uuid>/<listing-uuid>/<random-uuid>.<extension>`; trusted archive copies use the same owner's listing namespace. Storage RLS verifies the path owner and listing state; only the owner can upload/delete staging objects for their own draft/pending listing, while archive objects are accessible only to the checked restore/cleanup functions. A transaction-locked server operation caps each listing at eight images.

On moderator approval, a trusted server operation validates the approved set, copies each object to a random path in the public `listing-images` bucket, verifies every copy, and then atomically publishes the paths and sets the listing active. Until approval, paths exist only in the private bucket. Do not return public paths before activation. If copying or final database update fails, keep the listing non-public, retry safely, and delete orphaned public copies. Public images are intentionally public after approval; previously downloaded/shared bytes cannot be recalled instantly.

On moderator removal, first set the listing non-public, then copy each published image to a private archive path and verify the copy before deleting its public object. Store the new private path in `staging_path` and clear `published_path`. If any copy fails, keep retry state and never delete the only verified copy. A moderator restore returns the listing to `paused` with archived images still private; the seller may resume unchanged previously approved content, at which point the publication function re-publishes those archived images. Any content/image edit instead requires a new review. Do not automatically expire removal archives until an approved retention/cost policy exists.

Cleanup is idempotent and retryable:

- Delete abandoned staging uploads after a short documented grace period by a scheduled trusted job.
- On draft deletion, image replacement, or account deletion, enqueue deletion from both buckets; do not expect a Postgres cascade to delete Storage objects. Listing removal archives, rather than deletes, image bytes; moderator-authorized purge can delete an archive after the case/retention decision.
- Keep private audit/report data only for a verified retention interval. Alert/retry failed cleanup rather than widening bucket access.

## Indexes and Search

Start with indexed filtering, stable cursor pagination, and no search service:

- Partial feed index on `listings(created_at desc, id desc)` where `status = 'active'`.
- Partial indexes on `(category_id, created_at desc, id desc)` and `(location_id, created_at desc, id desc)` where `status = 'active'`.
- `listings(seller_profile_id, status, updated_at desc)` for seller views.
- Unique `listing_images(listing_id, sort_order)` for ordered images.
- `favorites(listing_id)` in addition to the `(user_id, listing_id)` primary key.
- `reports(reporter_user_id, created_at desc)` and target indexes for private moderation queries.

Add PostgreSQL full-text search (`tsvector` plus GIN index) only when measured title/description search quality or catalogue size warrants it. Keep county/area/category/time filters on ordinary B-tree indexes.