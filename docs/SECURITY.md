# K-Mark Security Design

Status: security requirements are encoded in initial local migration files but have not been executed or tested in a database. They are not active in the mock frontend, and no hosted project has been changed.

## Security Boundaries

- Treat all browser input, images, URL values, and client state as untrusted.
- Every exposed table has RLS enabled and explicit least-privilege grants. RLS does not remove grants; do not rely on policies alone.
- Server Actions provide validation and user-friendly errors, not authorization. Ownership, status transitions, and moderation are enforced again in database functions/RLS so direct PostgREST calls cannot bypass them.
- Keep email in Supabase Auth. Public profile projections contain only display name and broad controlled location. Never include phone, exact address, account secrets, or report data in public listing queries.
- The publishable key is not a secret and grants no authority without policy; secret/service keys bypass RLS and are not used for normal user operations.

## Roles and Moderator Capability

Postgres request roles remain `anon` and `authenticated`; “seller” and “moderator” are capabilities of an authenticated user, not client-selected roles. Store moderator membership in `private.moderator_roles`, outside exposed API schemas. Only a trusted operator can provision or revoke a role; never accept a role from a form, profile, URL, or user-editable Auth metadata.

RLS/functions call `private.is_moderator()` to check `auth.uid()` against that table. The helper and privileged mutation functions use `SECURITY DEFINER` only where needed, set `search_path = ''`, fully qualify every object, avoid dynamic SQL, and revoke `EXECUTE` from `PUBLIC` and `anon`. Grant function execution only to `authenticated`; each function still verifies the caller, moderator capability, input, row, and legal transition. Keep the `private` schema unexposed. Hidden admin UI is never authorization.

## Grants and RLS Permissions Matrix

RLS is enabled on all listed API tables. Unless noted, `anon` and `authenticated` receive no direct mutation grants on privileged data. Function grants are separate from table grants.

| Table | Role | Table/column grant | RLS/operation rule |
| --- | --- | --- | --- |
| `profiles` | `anon`, `authenticated` | `SELECT` only on public profile columns | Public display name and broad location only; profile projection contains no email/private fields. |
| `profiles` | `authenticated` owner | `UPDATE(display_name, location_id)` only; no `INSERT`, `DELETE`, ID/Auth-link or timestamp writes | `USING` and `WITH CHECK` require `auth_user_id = auth.uid()` and non-anonymized profile. Signup trigger creates row. |
| `categories`, `locations` | `anon`, `authenticated` | `SELECT` only | Read active rows only. No client `INSERT/UPDATE/DELETE`; migrations/trusted operator seed changes. |
| `listings` | `anon`, `authenticated` | `SELECT` only; no direct `INSERT/UPDATE/DELETE` or protected-column grants | `anon` sees active rows only. `authenticated` sees active rows plus rows whose seller profile maps to `auth.uid()`. |
| `listings` | `authenticated` seller | `EXECUTE` on seller mutation functions only | Each function verifies `auth.uid()` owns row, locks it, validates input and transition. No client can write `seller_profile_id`, `status`, IDs, approval/audit values, or timestamps directly. |
| `listings` | `authenticated` moderator | Same function-level grant, no direct table writes | Moderator functions check `private.is_moderator()` and write a moderation event. Non-moderator calls fail even if invoked directly. |
| `listing_images` | `anon` | `SELECT(id, listing_id, alt_text, sort_order, published_path)` only | RLS exposes only published metadata for active listings. |
| `listing_images` | `authenticated` | Same public columns plus `staging_path`; no direct `INSERT/UPDATE/DELETE` | RLS exposes own seller metadata and moderator review metadata. Never exposes another seller's paths. |
| `listing_images` | `authenticated` owner/moderator | `EXECUTE` on checked image attach/remove/publish functions | Function verifies parent ownership or moderator capability, path, ordering, and eight-image count. |
| `favorites` | `anon` | No table grants | No server-side anonymous favourite data. Browser session favourites remain local. |
| `favorites` | `authenticated` | `SELECT`, `INSERT`, `DELETE`; no `UPDATE` | Every operation requires `user_id = auth.uid()`. Insert also requires an active listing. Composite primary key prevents duplicates. |
| `reports` | `anon` | No table grants | No access. |
| `reports` | `authenticated` reporter | `SELECT`, `INSERT`; no `UPDATE/DELETE` | Read only own report rows; insert `reporter_user_id` must equal `auth.uid()` and exactly one target must exist. |
| `reports` | `authenticated` moderator | `SELECT` and `EXECUTE` on review function; no direct `UPDATE/DELETE` | RLS checks moderator capability; review function checks capability again and writes private audit. |
| `private.moderator_roles`, `private.listing_moderation_events`, `private.report_moderation_events`, `private.image_upload_reservations`, `private.storage_cleanup_queue` | `anon`, `authenticated` | No table grants | No Data API exposure. Role changes are operator-only; checked functions write audit, reservation, and cleanup rows. |
| `storage.objects` in `listing-staging` | `anon` | No grants/policies | No object reads, writes, or listings. |
| `storage.objects` in `listing-staging` | `authenticated` owner | `SELECT` and reserved `INSERT`; no direct `UPDATE/DELETE` | RLS checks user UUID path prefix, reservation, and listing state. Checked server functions queue object deletion. |
| `storage.objects` in public `listing-images` | `anon`, `authenticated` | Public object `GET` only; no object-listing or write grants | Public bucket reads are inherently public after approval. Only trusted publication/cleanup can create/delete objects; use random paths and do not expose them before activation. |
| `storage.objects` completion RPC | `service_role` only | `EXECUTE` on `complete_listing_image_upload(text)` | A server-only endpoint must validate actual bytes and enforce the 5 MB limit before calling it. Never expose the service-role key to a browser. |

At migration time, revoke default table/function privileges from `PUBLIC`, `anon`, and `authenticated`, then grant only the operations in the matrix. Use explicit column grants for public profile fields. Keep `USING` and `WITH CHECK` aligned; permissive SELECT policies combine with OR. A public active-listing policy must not expose owner-only moderation fields. Do not create a view that bypasses RLS; any exposed view must be security-invoker and separately reviewed.

## Listing Lifecycle Enforcement

See the canonical state-transition table in [DATABASE.md, “Listing State-Transition Table”](DATABASE.md#listing-state-transition-table). Essential rules:

- `draft -> pending_review` is seller submission; only moderator approval can begin publication.
- `approved` is a non-public state while approved media is copied and verified. A restricted publication function alone changes it to `active`.
- Only `active` rows are public. Seller content edits to active/paused rows immediately return them to review and hide them.
- Seller pause/resume/sold functions require ownership. Sellers cannot reject, approve, remove, restore, or rewrite protected fields.
- Moderator removal sets `removed`; archive its photos privately before deleting public objects. Only a moderator can restore, and restoration returns the listing to `paused`, not directly to public `active`. Seller resume may republish unchanged approved content; edits go back to review.
- Row locks and transition checks prevent races and replaying stale approvals. A moderation audit row records actor, action, reason, and time.

## Private Images and Publication

- `listing-staging` is private; draft and pending-review bytes are not publicly readable. Storage RLS permits upload/delete only when path user UUID equals `auth.uid()` and the parent listing belongs to that user in an uploadable state.
- Enforce a 5 MB maximum (exactly 5,000,000 bytes) and JPEG/PNG/WebP at bucket settings and server validation. Inspect file signatures and decode/re-encode to reject spoofed types, malformed images, SVG/HTML, and embedded EXIF/GPS. Do not trust a browser MIME header.
- Limit to eight images per listing in a locked database/server operation. Use random server-generated object keys; clients cannot supply bucket paths or overwrite another user's object.
- After explicit moderator approval, copy to random paths in public `listing-images`; verify all copies before the publication function records paths and marks the listing active. If any step fails, leave it non-public and run idempotent cleanup. Public bucket URLs are public by design; unpublished source files remain only in the private bucket.
- Pausing, selling, and account deletion withdraw public metadata and enqueue public-object deletion. Removal first verifies a private archive copy, then deletes the public object; moderator restore uses the private copy. A restricted purge operation may delete archives after a future approved retention/cost decision. Previously shared/downloaded public bytes cannot be recalled instantly; state this clearly in product privacy terms. Delete abandoned non-archive staging uploads after a documented grace period.

## Authentication, Profile Provisioning, and Account Deletion

- Use Supabase Auth email OTP/magic link and `@supabase/ssr` request-specific clients. Next.js 16 uses `proxy.ts` for refresh. Verify server identity with `getClaims()` or `getUser()`; `getSession()` alone is not a server authorization check.
- Signup's Auth-user trigger creates a minimal profile atomically with a safe default display name and incomplete-onboarding marker. Trigger failure rolls back signup; onboarding is idempotent/retryable. Never trust signup metadata for permissions.
- `profiles.auth_user_id` references `auth.users` with `ON DELETE SET NULL`; listings reference stable profile UUIDs with `ON DELETE RESTRICT`. A server-side deletion workflow first takes listings offline, deletes favourites/revokes moderator membership, anonymizes the retained profile, removes media, then deletes the Auth account. Report Auth/profile FKs use `SET NULL` so report evidence can survive without a live identity. Do not physically remove referenced profile tombstones.
- Retain only necessary report evidence for a period confirmed against applicable Kenyan legal/privacy requirements. The period and exact evidence fields remain unresolved; obtain qualified advice before launch and publish the retention/deletion policy.
- Keep Auth redirect allow-lists exact and prevent shared caching of responses with refreshed cookies. Secrets belong only in encrypted host settings/local ignored env files; do not commit them. Do not create env files for this plan.

## Input Validation and Low-Cost Controls

Validate in every Server Action before database calls, then enforce invariants again in functions/constraints:

- Require expected object shapes; trim and length-bound title (100) and description (5,000).
- Parse `price_kes` as an integer in `[0, 100000000]`; this fits safely in JavaScript's integer range.
- Resolve active `category_id` and `location_id` server-side. County/area come from controlled Nairobi/Kiambu location rows, not arbitrary text.
- Generate slug and random storage paths server-side; ignore supplied seller/reporter IDs, role, listing status, moderation fields, timestamps, and object URLs.
- Rate-limit sign-in, submissions, reports, and uploads with the hosting/Supabase facilities available to the selected plan. Do not add a paid queue or validation dependency without demonstrated need.

## Required Security Tests

Run pgTAP with local Supabase before connecting the UI. Every exposed table test asserts RLS is enabled and grants are least-privilege. Include:

- Anonymous reads only active listings, active categories/locations, and public profile columns; no private report/favourite/draft/image access.
- Owner can create draft, submit, edit own permitted fields, pause/resume/sell, and cannot write another seller's row.
- Direct table/API attempts to forge owner IDs, UUIDs, status, approval, moderation, or timestamps fail; all invalid transitions fail, including seller approval and removed-listing restoration.
- Moderator can approve/reject/remove/restore; ordinary authenticated users cannot invoke those operations successfully. Role revocation takes effect according to the chosen role lookup design.
- Favourites: owner-only select/insert/delete, no duplicate pair, no inactive listing insert, and cross-user read/delete denial.
- Reports: reporter-only read, immutable reporter writes, exactly one existing target, private reporter identity, moderator-only review, and FK behavior on account/target deletion.
- Storage: owner path allowed; cross-user/listing path denied; draft bytes unreadable anonymously; only approved publication creates public paths; test 8/9 image boundary, MIME/signature mismatch, 5,000,000/5,000,001-byte files, overwrite/delete, and cleanup retry.
- Signup trigger atomicity/idempotency; deletion anonymization and all FK actions; validation boundaries and rate limits.

Official references:

- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control)
- [Supabase Auth with Next.js SSR](https://supabase.com/docs/guides/auth/server-side/nextjs)