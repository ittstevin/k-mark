This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## Local Supabase Database

The backend foundation runs locally only. It does not connect to a hosted Supabase project and does not need a committed `.env` file. Install Docker Desktop and the Supabase CLI separately before running these commands:

```powershell
supabase start
supabase db reset
supabase test db
supabase stop
```

`supabase start` launches local services. `supabase db reset` resets the local database, applies ordered migrations, and loads `supabase/seed.sql`; it deletes data in that local database. `supabase test db` runs pgTAP tests against the local database. `supabase stop` shuts the services down.

The CLI prints local development URLs and keys. Keep them local; never commit a service/secret key or place one in browser code. Draft and pending-review images use the private staging bucket. Only approved listing images are readable from the public bucket. The upload-completion RPC requires `service_role`; a future server must inspect/decode the actual image bytes before calling it. Database tests cover SQL permissions/RLS; they do not replace HTTP-level validation of image bytes and upload size.

The migration set creates the moderator-role table but does not grant anyone moderator access. Provisioning the first moderator requires a trusted local operator action after a user signs up; do not add a user-editable admin flag. The cleanup queue is only a database queue at this stage; no worker is included yet.

The local configuration, migrations, and seeds contain no project credentials. A production Supabase project is not created or configured by these instructions.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
