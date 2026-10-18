# K-Mark Database Design

Status: proposed design only. This document is not migration SQL. No Supabase project or database is configured in this repository, and no schema has been created.

## Current Data Model

The frontend demo data and TypeScript types currently live in `app/data/listings.ts`:

- `ListingCategory` is a union of the seven display names.
- `Listing` is a presentation model with a string ID, slug, category name, KSh price, county/area, one image URL, relative `posted` text, optional `featured`, and a demonstration seller label.
- `listings` and `categoryOptions` are in-memory arrays. They are not database records.

The future database should use stable UUIDs and normalized foreign keys. A server-side mapper should turn rows plus related profile/category/image data into the existing card/detail view model. Do not make UI components depend on raw Supabase row shapes.

## Tables

All primary keys are UUIDs unless noted. Use `created_at timestamptz not null default now()` and `updated_at` where records can change. Enable RLS on every table exposed through the Supabase Data API, and explicitly set grants as well as policies.

### `profiles`

One public profile per Auth account. `id` is the same UUID as `auth.users.id` and references it. Suggested public fields:

- `display_name text not null` with a trimmed length limit.
- `avatar_path text null` for a public avatar, if avatars are introduced.
- `county text null` constrained to `Nairobi` or `Kiambu`.
- `area text null` for a broad neighbourhood only.
- `bio text null` with a short maximum length.
- `created_at`, `updated_at`.

Do not put email, phone number, exact address, or private account metadata in this public table. Keep email in Supabase Auth. Add a separate owner-only private table only if a concrete feature requires extra contact data.

### `categories`

- `id uuid primary key`.
- `slug text unique not null`, such as `home-living`.
- `name text not null`.
- `sort_order integer not null`.
- `is_active boolean not null default true`.
- `created_at`.

Seed the seven existing categories. Keep decorative icon choices in frontend code keyed by category slug; the database should not own presentation assets. Category rows are maintained by reviewed migrations or trusted moderation tooling, not regular users.

### `listings`

- `id uuid primary key`.
- `seller_id uuid not null references profiles(id) on delete restrict`.
- `category_id uuid not null references categories(id) on delete restrict`.
- `slug text unique not null`, generated and collision-checked on the server.
- `title text not null` (proposed maximum 100 characters).
- `description text not null` (proposed maximum 5,000 characters).
- `price_kes bigint not null check (price_kes >= 0)`; prices are whole Kenyan shillings, not floating-point values.
- `county text not null check (county in ('Nairobi', 'Kiambu'))`.
- `area text not null` with server-side length and input validation.
- `status listing_status not null default 'draft'`.
- `created_at`, `updated_at`, `published_at timestamptz null`, `sold_at timestamptz null`.

Do not persist the demo-only `posted` label; derive it from `created_at`. Do not let sellers write a `featured` flag. If paid or editorial promotion is ever approved, model it as a separately authorized moderation field, not as seller-controlled listing content.

### `listing_images`

- `id uuid primary key`.
- `listing_id uuid not null references listings(id) on delete cascade`.
- `storage_path text unique not null`; store a bucket-relative path, not a client-supplied URL.
- `alt_text text not null` with a length limit.
- `sort_order integer not null default 0 check (sort_order >= 0)`.
- `created_at`.
- `unique (listing_id, sort_order)` for deterministic cover-image ordering.

The first ordered image is the cover image. Storage objects are a separate service and do not participate in a Postgres transaction: hard-delete jobs must remove objects explicitly and be safe to retry. Prefer soft-removing listings during normal use.

### `favorites`

- `user_id uuid not null references auth.users(id) on delete cascade`.
- `listing_id uuid not null references listings(id) on delete cascade`.
- `created_at`.
- Primary key `(user_id, listing_id)`.

The current prototype keeps anonymous favourites in `sessionStorage`. Keep that behavior for signed-out visitors if desired; authenticated favourites should use this table. On sign-in, any merge from the browser session must be an explicit, validated action, not a trusted client write.

### `reports`

- `id uuid primary key`.
- `reporter_id uuid not null references auth.users(id) on delete restrict`.
- `target_listing_id uuid null references listings(id) on delete restrict`.
- `target_user_id uuid null references profiles(id) on delete restrict`.
- A check constraint requires exactly one target (listing or user).
- `reason text not null` constrained to a small allow-list such as `scam`, `prohibited_item`, `misleading`, `harassment`, or `other`.
- `details text null` with a strict length limit; warn users not to include unnecessary sensitive data.
- `status report_status not null default 'open'` with values `open`, `reviewing`, `resolved`, `dismissed`.
- `created_at`, `reviewed_at timestamptz null`.

Reports are private moderation records. Keep reporter identity and report details hidden from the reported user. Only a trusted moderation path can change report status. Report/account deletion and retention need a documented privacy process before launch.

## Listing Status and Ownership

| Status | Publicly visible | Seller can see | Meaning |
| --- | --- | --- | --- |
| `draft` | No | Yes | Created but not published. |
| `active` | Yes | Yes | Published and browseable. |
| `paused` | No | Yes | Temporarily hidden by its seller. |
| `sold` | No | Yes | Seller marked the item sold; terminal for that listing. |
| `removed` | No | Yes | Soft-hidden by the seller or trusted moderation. |

Suggested transitions: `draft -> active/removed`; `active -> paused/sold/removed`; `paused -> active/sold/removed`. `sold` and `removed` are terminal; create a new listing to relist. Server validation runs before publishing. Seller ownership is immutable: `seller_id` is set from the verified session, never from form input, and cannot be changed by an update. Status changes go through an authorized server action/RPC with transition checks; ordinary column grants should not allow clients to rewrite `seller_id`, timestamps, or moderation-controlled values.

## Indexes

Add indexes for expected browse and policy paths:

- Partial active-feed index on `listings(created_at desc)` where `status = 'active'`.
- Partial browse indexes on `(category_id, created_at desc)` and `(county, area, created_at desc)` where `status = 'active'`.
- `listings(seller_id, status)` for seller dashboards and ownership checks.
- `listing_images(listing_id, sort_order)` and an index on `listing_images.listing_id` if not covered by the unique index.
- `favorites(listing_id)` for reverse lookups and foreign-key maintenance; the primary key already indexes `user_id` first.
- `reports(reporter_id, created_at desc)` and target indexes for moderation queues.

Revisit indexes against real query plans rather than adding speculative indexes.