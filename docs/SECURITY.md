# K-Mark Security Design

Status: design only. These controls are requirements for a future backend; none of them should be treated as active in the current mock frontend.

## Security Boundaries

- Treat browser input, listing text, image files, URL parameters, and all client state as untrusted.
- The Supabase publishable key is an identifier, not an authorization mechanism. RLS and least-privilege Postgres grants must protect every exposed table.
- RLS does not remove SQL grants. Each migration must revoke unnecessary `anon`/`authenticated` privileges, grant only required operations, then add operation-specific policies.
- Keep profile email and Auth credentials in `auth.users`; public `profiles` contains only fields intended for every visitor. Never expose session tokens, database credentials, or service/secret keys to the browser.

## Authorization Policy Matrix

Enable RLS for every exposed public table. Policies below are the intended behavior, not executable policy SQL.

| Table | Signed-out visitor | Signed-in owner/reporter | Other signed-in user | Trusted moderation |
| --- | --- | --- | --- | --- |
| `profiles` | Read public fields only | Read/update own public fields | Read public fields; cannot update another profile | Restricted server operation only if needed |
| `categories` | Read active categories | Read active categories | Read active categories | Manage through migrations/trusted tooling |
| `listings` | Read `active` rows only | Read own rows in every status; create own `draft`; edit own allowed content | Read `active` rows only | May remove/restore only through controlled moderation path |
| `listing_images` | Read image metadata for active listings | Read/manage images for own listings | Read metadata for active listings | Cleanup/moderation as needed |
| `favorites` | No access | Read/insert/delete rows where `user_id = auth.uid()` | No access to another user's rows | No routine access needed |
| `reports` | No access | Insert reports as self; read only own submitted reports | No access to another reporter's reports | Read/review through a restricted server-side path |

For policies, name the Postgres role (`anon` or `authenticated`) and use `auth.uid()` for ownership. On `listings`, the public `active` read and the seller-owned read are separate SELECT policies; remember permissive policies combine with OR. Insert checks must bind seller/reporter IDs to `auth.uid()`. Update policies need both `USING` and `WITH CHECK` so ownership cannot be reassigned. Add tests proving both allowed and denied cases.

### Table-specific constraints

- **Profiles:** expose only deliberately public fields. Owner edits cannot change `id`, ownership, or timestamps. Do not copy Auth email into this table. If phone contact is later required, place it in a separate private table with owner-only policies and explicit consent.
- **Listings:** anonymous users see only `status = 'active'`. Sellers can read their own drafts/paused/sold/removed rows. A seller can never set `seller_id` to another account. Use column-level grants or a narrow server function so ordinary updates cannot change IDs, audit timestamps, or moderation-controlled state. Use a status-transition function/action for publish, pause, sold, and remove operations.
- **Listing images:** parent listing ownership determines writes. Require the referenced listing to belong to `auth.uid()` for insert/update/delete. The listing SELECT policy must not depend on `listing_images`, avoiding recursive RLS checks.
- **Favourites:** allow only the row owner to select, insert, or delete; do not expose a global favourite list or private favourite count. An insert should reference an active listing. Use the composite key to prevent duplicates.
- **Reports:** require `reporter_id = auth.uid()` and exactly one target. Reporter may read their own report, but cannot update/delete it or read another person's report. A reported seller must never see reporter identity or private report details. Only a trusted moderation path changes report status.
- **Categories:** client roles receive read-only access to active rows. Do not allow user metadata or a user-editable profile field to grant category-management privileges.

Supabase documents that secret/service keys bypass RLS. Use them only in a narrowly scoped server-only moderation or cleanup module; never pass a user JWT into an admin client and assume it bypasses RLS. Prefer the signed-in user's server client for ordinary reads and writes so RLS remains active.

## Authentication and Session Handling

- Use Supabase Auth email OTP/magic link initially; do not create a custom password table.
- Use `@supabase/ssr` cookie-aware clients and the Next.js 16 `proxy.ts` convention for refreshing sessions. Verify identity with `auth.getClaims()` or use `auth.getUser()` when a current user record is needed. `getSession()` alone reads cookie state and is not sufficient authorization proof.
- Do not trust `user_metadata` for ownership, roles, moderation status, or other authorization decisions; users can edit it. Derive ownership from verified `auth.uid()`.
- Restrict Auth redirect URLs to the local/production hosts actually in use. Set secure, HTTP-only cookie behavior through the supported SSR integration and avoid shared caching of responses that contain refreshed session cookies.
- Public env values may use `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. A server secret such as `SUPABASE_SECRET_KEY` is optional, server-only, and never prefixed `NEXT_PUBLIC_`. Do not create values or `.env` files for this documentation task.

## Server-Side Validation

Every Server Action/Route Handler must validate input before it calls Supabase. RLS is an authorization backstop, not a replacement for validation.

- Accept only expected object shapes; reject unknown/missing fields where appropriate, normalize whitespace, and enforce title/description/reason length bounds.
- Parse price as a safe integer number of KSh, reject negative, non-finite, or out-of-range values, and never use floating-point currency math.
- Resolve `category_id` from an active category row; validate county against Nairobi/Kiambu and area as bounded text or an approved location list.
- Generate slugs and storage paths on the server. Ignore client-supplied `seller_id`, `reporter_id`, status, moderation fields, timestamps, Storage URLs, and ownership claims.
- Enforce listing status transitions and ownership in both the server operation and database policy/function.
- Rate-limit Auth, listing creation, reports, and uploads at the server/edge before launch. Return generic public errors that do not leak whether a private user/listing/report exists.

No validation package is currently installed. Choose a schema validator during implementation only if it materially reduces duplication; do not install one as part of this architecture plan.

## Image Upload Controls

- Use a single public `listing-images` bucket only for images intended to be publicly visible. Public bucket reads are public by design; Storage RLS still protects write operations, not confidentiality of a public object URL.
- Use per-user/per-listing random object paths. Storage RLS must verify `auth.uid()` matches the first path segment and that the referenced listing belongs to that user. Do not allow arbitrary bucket writes or cross-user overwrites.
- Restrict MIME types and file size in both bucket configuration and server validation. Inspect actual file signatures rather than trusting filename or browser MIME alone; reject SVG/HTML and strip EXIF/GPS metadata.
- Limit the image count per listing and verify every image metadata row belongs to the listing. Clean up unreferenced objects with retryable server-side work; database cascades do not remove Storage files.
- Never put private documents, home addresses, or phone numbers in public listing images or metadata.

## Reporting, Moderation, and Privacy

- Reports are immutable to the reporter after submission and inaccessible to the public/reported user. Store only the minimum detail required to review a report and define retention/deletion rules before launch.
- Do not add a user-editable `is_admin` boolean. If a moderator role is introduced, set it only through trusted server-side Auth app metadata or a tightly controlled private role mechanism, and account for claim refresh. For the initial small system, a restricted server-only moderation operation is simpler than building a public admin-role table.
- Soft-remove listings so a report can still reference the target. Account deletion must first handle owned listings and report retention deliberately; do not cascade-delete evidence accidentally.
- Do not add payments, financial credentials, messaging content, or order data to this schema.

## Required Verification Before Launch

For every exposed table, write pgTAP RLS tests for anonymous, owner, another authenticated user, and trusted moderation as applicable. Test both grants and row policies; one does not replace the other. Include ownership reassignment, hidden listing reads, report privacy, favourite isolation, and storage path attacks. Test validation with malformed IDs, oversized text, invalid prices/categories, forged status/seller fields, unexpected file types, oversized uploads, duplicate images, and rate-limit behavior.

Official references:

- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control)
- [Supabase Auth with Next.js SSR](https://supabase.com/docs/guides/auth/server-side/nextjs)