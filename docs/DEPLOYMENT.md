# Deployment and operations

The app is two independent parts:

1. **Static front end** (`public/`): any web host.
2. **Supabase project**: database, functions, storage and scheduler (README §4).

They are connected only by `public/config.js` (the project URL and the **anon** key).

---

## Current production layout (handover snapshot)

| Part | Where |
|---|---|
| Front end | Cloudflare Worker `alkazemi` → https://alkazemi.najmdev.workers.dev, auto-deployed from GitHub `nmg965/alkazemi` (branch `main`) |
| Database | Supabase project `alkazemi-asset-management` (ref `qekfkosslaninyqkptlz`, region ap-south-1) |
| Scheduler | pg_cron job `aqar-escalations-and-alerts`, every 5 minutes |
| Alerts | Edge Function `aqar-alerts`. The Resend and Twilio keys are not set yet |

If your team takes over the **existing** Supabase project, you only need to be added to its organisation; nothing has to be re-created. To run a **separate copy**, follow README §4 on a new project and leave the live one untouched.

---

## Hosting options for `public/`

### Cloudflare Workers (current)
`wrangler.jsonc` is already set up:
```jsonc
{ "name": "alkazemi", "compatibility_date": "2026-09-01",
  "assets": { "directory": "./public", "not_found_handling": "single-page-application" } }
```
- From your machine: `npx wrangler login && npx wrangler deploy`. **Change `name`** if you deploy a second copy, so you don't overwrite the live Worker.
- From Git: Cloudflare dashboard → Workers & Pages → Create → Import a repository → leave the build command empty → deploy command `npx wrangler deploy`.

### Cloudflare Pages
Create the project → *Upload assets* → upload the `public` folder. The `_headers` file is honoured.

### Netlify
Drag and drop the `public` folder in app.netlify.com/drop, or connect Git with publish directory `public` and no build command. `_headers` is honoured.

### Vercel
Import the repo → Framework *Other* → Output directory `public` → no build command. Add a `vercel.json` with the cache headers if you want them (see `_headers`).

### GitHub Pages / S3 + CloudFront / Azure Static Web Apps / IIS / nginx
Serve the `public` folder. Recommended headers:
- `app.js`, `app.css`: `Cache-Control: public, max-age=31536000, immutable`
- `index.html`, `config.js`: `Cache-Control: no-cache`

The app is a single page with no URL routes (screens are switched in-app), so no rewrite rules are required.

### Custom domain
Add the domain in the host's dashboard (for example, Cloudflare → Worker → Settings → Domains & Routes). Nothing in the app depends on the domain.

---

## Releasing a change
1. Edit `public/app.js` or `public/app.css`.
2. Bump the version in `index.html`:
   ```bash
   V=$(cat public/app.js public/app.css | sha1sum | cut -c1-10)
   sed -i -E "s/\?v=[a-f0-9]+/?v=$V/g" public/index.html
   ```
3. Commit and push (auto-deploy), or run `npx wrangler deploy`.
4. Open the site, hard-refresh, and sign in to check.

Database changes: add a new file `supabase/migrations/006_….sql`, run it in the SQL Editor (or `supabase db push`), and commit it.

## Operations checklist

| Task | How |
|---|---|
| Keep the project awake | Free Supabase projects pause after 7 days without activity. Use the Pro plan for production and keep billing paid. |
| Backups | Supabase Pro has daily backups. Turn on PITR for point-in-time restore. |
| Check the scheduler | `select * from cron.job_run_details order by start_time desc limit 10;` |
| Check message delivery | `select status, count(*) from outbox group by 1;` and the `error` column |
| Run escalations by hand | `select public.tick();` |
| Reset a password | Users screen → edit → New password, or `select public.set_password(...)` |
| Logs | Supabase → Logs (Postgres, Edge Functions); Cloudflare → Worker → Logs |

## Secrets: where each one lives

| Secret | Location | Never put it in |
|---|---|---|
| anon key | `public/config.js` (it's public by design) | n/a |
| service_role key | Your password manager; an env var for `import.mjs` only | Git, `config.js`, chat |
| RESEND_API_KEY, TWILIO_* | Supabase → Edge Functions → Secrets | Git, `config.js` |
| Database password | Supabase dashboard | Git |
