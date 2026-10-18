# K-Mark Backend Architecture

Status: planning document. The frontend remains a local-data prototype. No backend, Supabase project, API, migrations, or environment configuration has been added.

## Existing Application

- **Framework:** Next.js 16.4.2 App Router, React 19, TypeScript, Tailwind CSS 4.
- **Package manager:** npm (`package-lock.json`).
- **Routes:** `/`, `/listings/[slug]`, `/sign-in`, `/sell`, and `/help`.
- **Mock data and view types:** `app/data/listings.ts` exports `Listing`, `ListingCategory`, `categoryOptions`, and `listings`.
- **Reusable UI:** `app/components/marketplace.tsx`, `listing-card.tsx`, `search-controls.tsx`, `brand.tsx`, `detail-image.tsx`, and `coming-soon.tsx`.
- **Current state:** Search/filtering runs in the browser over the mock array; favourites are held in `sessionStorage`. Sign-in and selling are placeholders.
- **Backend configuration:** No Supabase packages, Supabase directory, SQL, API route handlers, `.env` files, Auth client, or database config exists. `package.json` has no test script.

## Target Request/Data Flow

1. Keep the App Router and Server Components as the default.
2. Public page/detail reads use a request-scoped Supabase server client and rely on database RLS. The `/listings/[slug]` route queries only a public `active` listing and returns not-found for hidden rows unless the verified seller is viewing their own listing.
3. Use Next.js Server Actions for form mutations such as profile edits, listing create/edit/status changes, report submission, and favourite changes. Add a Route Handler only where a protocol boundary needs one, such as a signed upload grant or external webhook.
4. Validate every mutation on the server, derive `user_id`/`seller_id` from verified Auth claims, and let RLS enforce the same ownership rule in the database.
5. Keep browser-only interactions small. The existing cards and filters can receive serializable view data from a Server Component; do not move database secrets or privileged clients into their client bundle.

### Proposed future structure

```text
app/
  actions/                  # validated user mutations
  lib/supabase/client.ts    # browser client, only if a client-side feature needs it
  lib/supabase/server.ts    # request-scoped server client
  proxy.ts                  # refreshes cookie-backed Auth sessions (Next.js 16)
  data/listings.ts          # keep as demo fixture or replace with a query adapter
supabase/
  migrations/               # reviewed schema, grants, RLS and seed changes
  tests/                    # pgTAP RLS allow/deny tests
```

Keep this structure prospective; do not create it until implementation is approved. Do not add a generic repository layer until there is real query duplication to remove.

## Reuse Existing Frontend Work

- Keep `ListingCard` as a presentation component. Add a server-side mapper from `listings`, `categories`, `profiles`, and the cover `listing_images` row into a UI view model.
- Map database `price_kes` to the card's KSh `price`; map category ID/slug to its display name; map ordered image paths to the current image/alt fields; derive the relative `posted` label from `created_at`.
- The demo `id` values such as `camera-01` are not UUIDs. Use database UUIDs for persistence and the existing `slug` for `/listings/[slug]` URLs.
- Keep category icon choices in frontend configuration keyed by category slug. The current `categoryOptions` array becomes a seed/fixture or is replaced by active database categories.
- Preserve anonymous search and filter interactions. Replace the array source with paginated server results, keeping the same controls and empty-state view.
- Replace session-only signed-in favourites with `favorites` rows. Anonymous session favourites can remain local; make any sign-in merge explicit.
- Do not store mock-only `emoji`, display-relative timestamps, seller demo labels, or a seller-editable `featured` flag as authoritative database fields.

## Authentication and Supabase Clients

- Start with Supabase Auth email OTP/magic link; do not build custom password storage. Confirm redirect allow-lists and production callback URLs before launch.
- Use `@supabase/ssr` clients for Next.js App Router cookie sessions and `@supabase/supabase-js` as the underlying client. These dependencies are not installed now.
- Next.js 16 calls the session-refresh file `proxy.ts`, not `middleware.ts`. Use the current official Supabase SSR pattern; refresh cookies in Proxy and return the response that carries refreshed cookies/cache headers.
- Verify identity server-side with `supabase.auth.getClaims()` (or `getUser()` when a fresh Auth user record is required). Do not authorize using `getSession()` alone or user-editable `user_metadata`.
- A publishable key and project URL may be exposed to the browser only with RLS correctly enabled. An optional Supabase secret/service key must be server-only and limited to trusted moderation/cleanup paths; normal user requests should use their cookie-authenticated client.

Expected variable names when integration is approved: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and, only if a trusted server task needs it, `SUPABASE_SECRET_KEY`. No values belong in source control; no variables are needed by the current frontend.

## Image Storage

Use one `listing-images` Storage bucket and `listing_images` rows that store bucket-relative paths. Suggested object names are `<auth-user-uuid>/<listing-uuid>/<random-uuid>.<extension>`. Storage policies must confirm the signed-in user owns the referenced listing before upload, overwrite, or delete. Restrict content type and size; accept a small raster set such as JPEG, PNG, and WebP, reject SVG/HTML, and strip EXIF/GPS metadata before public delivery.

Listing photographs are intentionally public marketplace content. A public bucket makes image bytes readable to anyone with a URL, including for a draft if its path leaks; never place identity documents, contact details, or private images in it. If drafts must have confidential images, use a private bucket and server-issued signed reads instead. Removing a database row does not automatically delete its Storage object, so implement retryable cleanup.

## Implementation Sequence

1. Review this proposal and confirm product choices: email OTP, direct publishing after server validation versus manual review, profile fields, image limits, retention, and the initial moderator workflow.
2. Add Supabase CLI/local development setup only after approval; create ordered migrations for tables, constraints, indexes, minimal grants, RLS, and category seeds. Do not create or mutate a hosted project as part of this plan.
3. Add pgTAP tests for every table and Storage policy. Test anonymous, owner, other-user, and moderator cases before connecting the UI.
4. Add environment validation and cookie-aware browser/server clients plus Next.js 16 `proxy.ts`. Keep secrets out of client imports and test cache headers/session refresh.
5. Add read-only server queries and map rows to the existing UI view model. Replace mock listing reads without changing card/filter interaction contracts.
6. Add Auth, then validated listing/favourite/report Server Actions and owner-scoped image upload. Keep publishing, moderation, and account deletion state transitions explicit.
7. Test RLS, validation, Auth redirects, upload abuse cases, accessibility, and mobile browse flows in local Supabase before any production rollout.

No payments, orders, messaging, or database integration is proposed for this foundation.