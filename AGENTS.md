<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# K-Mark Development Instructions

- Project name: K-Mark.
- Purpose: A classifieds marketplace for Nairobi and Kiambu, Kenya.
- Use TypeScript and the existing framework's recommended conventions.
- Prefer small, focused, maintainable changes.
- Preserve existing working functionality.
- Use accessible, responsive UI patterns.
- Validate untrusted inputs and enforce authorization on the server.
- Never expose credentials or server-only secrets in client-side code.
- Use realistic Kenyan locations and KSh prices in sample data.
- Do not copy Jiji's branding, assets, or distinctive visual identity.
- Do not add a database, authentication provider, payments, or unnecessary dependencies without approval.
- Run the relevant lint, type-check, tests, and production build when available.
- Explain commands and important changes in beginner-friendly language.
