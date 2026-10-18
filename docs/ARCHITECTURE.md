# K-Mark Backend Architecture

Status: approved MVP plan, documentation only. The frontend remains a local-data prototype; no Supabase project, API, migration, or environment configuration has been added.

## Existing Application

- **Framework:** Next.js 16.4.2 App Router, React 19, TypeScript, Tailwind CSS 4; npm package manager.
- **Routes:** `/`, `/listings/[slug]`, `/sign-in`, `/sell`, `/help`.
- **Mock data/types:** `app/data/listings.ts` exports `Listing`, `ListingCategory`, `categoryOptions`, and `listings`.
- **Reusable UI:** `ListingCard`, `SearchControls`, `Brand`, `DetailImage`, `ComingSoon`, and the `Marketplace` client component.
- **Current state:** search/filters use the local array; favourites use `sessionStorage`; auth and selling routes are placeholders.
- **Backend:** no Supabase package/config, SQL, API route handler, `.env` file, Auth client, or database exists. No test script is configured.

## Request and Authorization Flow

1. Keep App Router Server Components as the default. Use the browser only for UI state.
2. Create one cookie-aware server client per request. Public search/detail queries return only `status = 'active'` listings and their deliberately public profile fields. A seller's dashboard may query their rows of any status after verified authorization.
3. Use Server Actions for validation and friendly errors, but never treat the action or a hidden route as the authorization boundary. Exposed tables have least-privilege grants and RLS. Listing state changes and moderator decisions go through database functions that check `auth.uid()`, role, row ownership, and legal transitions under a row lock. Direct PostgREST calls to those functions must face the same checks.
4. For highly restricted operations, use `SECURITY DEFINER` functions only with `SET search_path = ''`, fully qualified object names, no dynamic SQL, and `EXECUTE` revoked from `PUBLIC`/`anon`; grant only the needed function to `authenticated`. Moderator functions also call the private moderator-role helper. Keep the helper/role table in a non-exposed schema.
5. Keep signed-in favourites in `favorites`; anonymous favorites may remain local. Explicitly validate any session-favourite merge after sign-in.

## Reuse Existing Frontend Work

- Keep `ListingCard` as a presentation component. A server mapper converts database listing/category/location/profile/image rows to its view model.
- Map UUID `id` to a string; keep `slug` for `/listings/[slug]`; map `price_kes` integer to KSh; map `category_id` and `location_id` to display name/county/area; select images ordered by `sort_order`; derive relative `posted` from `created_at`.
- Demo IDs such as `camera-01` are not database UUIDs. Never use them as persistent IDs. Keep emoji, image fallback, category icons, and relative timestamp formatting in UI code.
- The current `ListingCategory` union and `categoryOptions` are useful display/seed fixtures, not authorization. Use active database categories for filtering after integration.
- Keep existing card/filter interfaces and empty states; replace the array source with a paginated server query. Start with category/location/date filtering; full-text search can wait until measured need.

## Auth, Profile Provisioning, and Roles

- Use Supabase Auth email OTP/magic link; do not store passwords. Configure exact local/staging/production callback allow-lists.
- Use `@supabase/ssr` with `@supabase/supabase-js`; these packages are not installed. Next.js 16 uses `proxy.ts` for cookie refresh. Use the current SSR cookie adapter, preserve refreshed cookies/cache headers, and prevent shared caching of session-bearing responses.
- Verify identity server-side with `getClaims()` or `getUser()` as appropriate. `getSession()` alone is not authorization proof. Ignore client role claims and user-editable `user_metadata`.
- Create a minimal profile using an idempotent `auth.users` insert trigger in the same transaction. Use a validated display name or a safe default and mark onboarding incomplete. If profile creation fails, let signup roll back; provide a retryable authenticated onboarding action. Metadata never grants roles.
- Moderator membership is stored in private `moderator_roles`, provisioned/revoked only by a trusted operator. Direct table access is revoked. Do not use a hidden admin page or client-supplied role as proof.

Future public configuration names: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. A server-only `SUPABASE_SECRET_KEY` is not needed for normal user operations and should only exist if a narrowly scoped trusted maintenance function requires it. No values or `.env` files are introduced by this plan.

## Listing Publication and Images

New listings are drafts. Sellers submit drafts into review; only a moderator can approve them. Content edits to an active/paused listing immediately hide it and require review again. Sellers may pause/resume unchanged approved listings and mark their own listings sold. A moderator removal cannot be undone by a seller; moderator restore returns a listing to paused.

Use a private `listing-staging` bucket for all drafts and pending-review images. Enforce a per-object 5 MB limit (exactly 5,000,000 bytes) and JPEG/PNG/WebP allow-list in bucket configuration and server validation. Validate file signatures and decode/re-encode server-side, strip EXIF/GPS, generate random object paths under the authenticated user's and listing's UUIDs, and enforce at most eight images under a listing lock. Storage RLS checks ownership and permissible listing state for upload/delete.

After moderator approval, a trusted server operation copies validated staging images to random paths in public `listing-images` and verifies all copies. The final database function accepts only a recorded moderator approval event, confirms the complete image set, and atomically records the public paths and activates the listing; an arbitrary authenticated caller cannot activate an `approved` row. A failure leaves it non-public; retries are idempotent and delete orphan copies. Public image bytes are intentionally public only after approval. Hiding a listing removes public references and starts object cleanup; public images already downloaded or shared cannot be recalled instantly. Keep staging sources only as long as needed for retries, then delete them.

## Local, Staging, Production, and Operations

- Use Supabase CLI/local Postgres for development and pgTAP tests; do not develop against production.
- Use separate local, staging, and production projects with distinct project URLs/keys, Auth callback allow-lists, Storage buckets, and data. Never copy production personal data to local/staging.
- Keep secrets in ignored local environment files for development and the deployment provider's encrypted secret store for hosted environments. Rotate exposed keys; never commit service/secret keys. Publish only URL and publishable key to the browser after RLS is verified.
- Commit ordered migrations and category/location seed data. Promotion is local tests -> staging migration and policy tests -> review -> production migration. Do not make undocumented dashboard-only schema edits.
- Before production migrations, take/verify a backup appropriate to the chosen Supabase plan. Document who can restore, test recovery in staging, and take a fresh backup before destructive schema/data changes. Confirm retention/PITR availability and cost with the selected plan; do not assume it is included.
- Keep early hosting low-cost: Supabase Auth/Postgres/Storage and the current Next.js host are sufficient. Avoid a separate search service, message queue, paid moderation platform, or extra validation package until a measured requirement justifies it.

## Migration and Test Sequence

1. Confirm remaining policy assumptions listed in `SECURITY.md`.
2. Migration 1: enums, locations/categories, profiles, listings, image metadata, favorites, reports, moderation roles/events, constraints, indexes, and idempotent profile provisioning.
3. Migration 2: non-exposed private schema, fixed-search-path role helper, protected listing/moderator functions, explicit table/column/function grants, and RLS policies.
4. Migration 3: private staging/public approved-image buckets, bucket size/MIME limits, and `storage.objects` ownership/read policies.
5. Migration 4: seed the current seven categories and controlled Nairobi/Kiambu areas; keep seed operations repeatable.
6. Add pgTAP RLS/grant tests with each relevant migration. Add server validation/integration tests for signup profile creation, listing workflow, media publication/cleanup, and Auth deletion. Only connect UI reads after local tests pass; add writes after staging security review.

No payments, messaging, orders, or live Supabase integration are part of this MVP plan.