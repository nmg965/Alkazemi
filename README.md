# Alkazemi Asset Management

A bilingual (English / Arabic) property and facilities management platform for GCC portfolios: buildings, units and leases, tenants, maintenance with a multi-step approval chain, guard tools, vacant-unit inspections, warehouse, fleet, rent collection, reports, a live wall display, email/WhatsApp alerts and automatic late-job escalation.

This package is the complete source of the live portal at **https://alkazemi.najmdev.workers.dev**. It includes the app, the database schema and server logic, the alert sender, a full export of the current demo data, and the building photos.

| | |
|---|---|
| Front end | One static page: vanilla JavaScript (`public/app.js`) and CSS (`public/app.css`). No build step, no framework, no npm install. |
| Back end | Supabase: Postgres tables, SQL functions (login, escalations), Realtime, Storage, one Edge Function, and pg_cron. |
| Hosting | Any static host. It currently runs as a Cloudflare Worker with static assets. |
| Languages | English and Arabic with full right-to-left layout. Switch with the EN/ع button. |
| Currency | KWD (Kuwaiti dinar) by default. |
| Themes | Light and dark, per user. |

---

## 1. What's in this folder

```
alkazemi/
├── README.md                  ← this file
├── wrangler.jsonc             ← Cloudflare Worker config (serves ./public)
├── public/                    ← THE APP: everything a browser loads
│   ├── index.html             ← page shell; loads config.js, supabase-js, app.css, app.js
│   ├── config.js              ← Supabase URL + anon key (edit this for a new database)
│   ├── app.js                 ← the whole application (~500 KB, readable, not minified)
│   ├── app.css                ← all styles (light/dark, RTL, mobile)
│   ├── _headers               ← cache rules for Cloudflare/Netlify
│   ├── manifest.webmanifest   ← install-to-home-screen (PWA) metadata
│   └── icon-192.png, icon-512.png
├── supabase/
│   ├── migrations/            ← run in order on a new Supabase project
│   │   ├── 001_core_tables.sql
│   │   ├── 002_auth_functions.sql
│   │   ├── 003_escalation_engine.sql
│   │   ├── 004_media_storage.sql
│   │   └── 005_schedule.sql
│   ├── functions/aqar-alerts/index.ts   ← Edge Function that sends email + WhatsApp
│   └── seed/
│       ├── import.mjs         ← loads the demo data + photos into a new project
│       └── data/*.json        ← export of the live demo data (4 MB)
├── assets/
│   ├── stock-photos/          ← 33 building photos used as placeholders (+ CREDITS.md)
│   └── brand/                 ← logo and app icons
└── docs/
    ├── FEATURES.md            ← every module, flow and report, and the roles matrix
    ├── DATA-MODEL.md          ← tables, record fields, SQL functions
    └── DEPLOYMENT.md          ← step-by-step hosting options and operations
```

---

## 2. Demo accounts

All demo accounts use the password **`demo123`**. The sign-in page also has one-tap buttons for each role.

| Role | Email | What they see |
|---|---|---|
| System administrator | admin@akam-demo.com | Everything, including users, permissions and settings |
| Owner / management | owner@akam-demo.com | Portfolio, final approvals, reports, live wall |
| Operations manager | manager@akam-demo.com | Approvals, assignment, inspections, fleet, reports |
| Building supervisor | supervisor@akam-demo.com | Their buildings only; pre-approval, tenants, rent |
| Procurement & stores | procurement@akam-demo.com | Purchases, warehouse, stock issues |
| Technician | technician@akam-demo.com | Their assigned jobs, stock issue, fleet work |
| Security guard | guard@akam-demo.com | Guard tools: patrols, visitors, reporting issues |

The demo data also includes more staff (imran@, sameer@, mohamed@, ashraf@, joseph@, anil@ the fleet mechanic, and so on, all `@akam-demo.com`) and a guard account for each building. **Change every password before real use** (Users & permissions → edit user → New password).

---

## 3. Quick start: run it locally in 1 minute

The app works against the existing live database as soon as you serve the `public` folder:

```bash
cd public
python3 -m http.server 8080        # or: npx serve .
# open http://localhost:8080
```

If the database can't be reached, the app shows a "database is not reachable" screen with **Try again** and **Open demo on this device**. The demo option generates the same demo portfolio inside the browser (localStorage only), which is useful for UI work without a database.

---

## 4. Full setup on your own Supabase project

Do this to run the platform on infrastructure your team owns. It takes about 20 minutes.

### Prerequisites
- A Supabase account (a free plan works for testing; use Pro for production so the project isn't paused).
- Node.js 18+ (only for the data import script).
- Optional: the Supabase CLI (`npm i -g supabase`) for deploying the Edge Function.

### Step 1: Create the project
In supabase.com → **New project**. Pick a region near your users (the current one is `ap-south-1`, Mumbai). Note these from **Project Settings → API**:
- Project URL: `https://<PROJECT-REF>.supabase.co`
- `anon` public key: goes into the browser
- `service_role` key: **secret**. Use it only for the import script and never commit it.

### Step 2: Create the database
Open **SQL Editor** and run each file in `supabase/migrations/` **in order** (001 → 005). Paste the file, press Run, and wait for "Success". The files are safe to re-run.

| File | Creates |
|---|---|
| 001_core_tables.sql | 16 data tables (users, properties, units, tenants, tickets, rent, …), `outbox`, `alerts`, `credentials`, row-level security policies, Realtime publication |
| 002_auth_functions.sql | `login()`, `set_password()`, `ensure_password()` with bcrypt hashing |
| 003_escalation_engine.sql | `run_escalations()`, `escalate_now()`, `queue_alert()` (late-job alerts every 4 h) |
| 004_media_storage.sql | public Storage bucket `aqar-media` for photos and documents |
| 005_schedule.sql | `tick()` plus a pg_cron job every 5 minutes; `app_config` table |

> If 005 fails with "extension pg_cron not available", enable **pg_cron** and **pg_net** under Database → Extensions, then run it again.

### Step 3: Tell the scheduler where the alert function lives
Still in the SQL Editor (replace the two values):
```sql
insert into public.app_config(key, value) values
  ('functions_url', 'https://<PROJECT-REF>.supabase.co/functions/v1'),
  ('anon_key',      '<ANON KEY>')
on conflict (key) do update set value = excluded.value;
```

### Step 4: Deploy the alert sender (Edge Function)
```bash
supabase login
supabase link --project-ref <PROJECT-REF>
supabase functions deploy aqar-alerts --project-ref <PROJECT-REF>
```
Or in the dashboard: **Edge Functions → Deploy a new function → name `aqar-alerts`**, then paste `supabase/functions/aqar-alerts/index.ts`.

Optional secrets (**Edge Functions → Secrets**). Without them, messages queue in the app and show as "not configured":

| Secret | Purpose |
|---|---|
| `RESEND_API_KEY` | Email via resend.com |
| `ALERT_FROM_EMAIL` | Sender address, e.g. `Alkazemi Alerts <alerts@yourdomain.com>` (domain verified in Resend) |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` | WhatsApp via Twilio |
| `TWILIO_WHATSAPP_FROM` | e.g. `whatsapp:+14155238886` |

### Step 5: Load the demo data and photos
This copies the full current portfolio (40 buildings, 873 units, 757 tenants, 161 tickets, 7,080 rent records, fleet, stock, patrols, visitors, alerts and more) and uploads the building photos.

```bash
cd supabase/seed
SUPABASE_URL=https://<PROJECT-REF>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<SERVICE ROLE KEY> \
node import.mjs
```
Flags: `--dry-run` (check only), `--skip-history` (skip old notifications, outbox and audit log), `--photos-only` (re-upload photos and re-attach them to buildings).

*Alternative:* skip this step. When the app opens against an **empty** database, it generates a fresh demo portfolio and saves it automatically, but without the photos and history from the live site.

### Step 6: Point the app at your project
Edit `public/config.js`:
```js
window.AKAM_CONFIG = {
  supabaseUrl: 'https://<PROJECT-REF>.supabase.co',
  supabaseAnonKey: '<ANON KEY>'
};
```
That is the only file to change. Leave the `service_role` key out of it.

### Step 7: Host it
`public/` is a plain static site. Choose one:
- **Cloudflare Workers** (current): `npx wrangler deploy` from the repo root, or connect the Git repo in Cloudflare → Workers → Create → Import repository. The build command is empty and the deploy command is `npx wrangler deploy`.
- **Cloudflare Pages / Netlify / Vercel / GitHub Pages / S3 / IIS / nginx**: publish the `public` folder as-is. No rewrite rules are needed: the whole app is one page.

See `docs/DEPLOYMENT.md` for details on each option.

### Step 8: Check it
1. Open the site and sign in as `admin@akam-demo.com` / `demo123`.
2. The sync badge in the top bar should say **Live**. A "database is not reachable" screen means `config.js` is wrong or the project is paused.
3. Open Buildings: you should see 40 buildings with photos.
4. Open Alerts & messages: escalation alerts are produced by the cron job every 5 minutes. To check it in SQL, run `select * from cron.job_run_details order by start_time desc limit 5;`.

---

## 5. Making changes

- **Code**: edit `public/app.js` and `public/app.css` directly. No compiler is needed.
- **Cache busting (important)**: `index.html` loads `app.js?v=XXXX` and `app.css?v=XXXX`, and those are cached for a year. **After every change, update the `?v=` value in `index.html`**, or users keep the old file. For example:
  ```bash
  V=$(cat public/app.js public/app.css | sha1sum | cut -c1-10)
  sed -i -E "s/\?v=[a-f0-9]+/?v=$V/g" public/index.html
  ```
- **Translations**: the English → Arabic dictionary is the `AR` object at the top of `app.js`, with regex patterns in `AR_PAT` for text that contains numbers or names. New English text shows in English until you add its Arabic entry.
- **Fonts**: English uses Outfit. Arabic mode uses Comfortaa (for Latin characters and digits) plus GE Dinar One for Arabic letters **if installed on the device** (`'AK Dinar'` in `app.css`), with Tajawal from Google Fonts as the fallback. To self-host GE Dinar One (a licensed font), add the files to `public/fonts/` and an `@font-face { font-family:'AK Dinar'; src:url(/fonts/…) }` rule in `app.css`.
- **Roles and permissions**: `ROLES`, `MODULES` and `ACTIONS` in `app.js` set the defaults. Admins can override them per user in the UI.
- **SLA and alert timings**: change them in the UI (Settings), or the defaults in `DEFAULT_SETTINGS` in `app.js`: urgent 24 h, normal 48 h, repeat every 4 h, vehicles every 2 h.
- **Branding**: the logo and icons are in `assets/brand/` and `public/icon-*.png`. The organisation name is set in Settings.

---

## 6. Security notes: read before real data

The current setup is a **demo-grade** security model, so the IT team can take over quickly:

- Row-level security is on, but the policies allow the `anon` key to read and write the app tables. Anyone with the site URL could use the API directly. Fine for a demo; **not** for live tenant data.
- Passwords are bcrypt-hashed in `credentials`, which the browser can't read. Sign-in goes through the `login()` RPC. Sessions are kept in the browser, with no server-side session or JWT per user.
- Storage bucket `aqar-media` is public-read with anonymous upload.

**Recommended before production:**
1. Move sign-in to **Supabase Auth** (email/password or SSO), and map `auth.uid()` to the user record.
2. Replace the open policies with per-role and per-building policies (supervisors and guards only see their assigned buildings).
3. Make the bucket upload require authentication. Use signed URLs for documents (licences and contracts).
4. Change all demo passwords, or delete the demo users.
5. Keep the `service_role` key only in server-side secrets. Never put it in `config.js`, the repo or chat.
6. Turn on Point-in-Time Recovery / daily backups (Supabase Pro).

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| "Database is not reachable" screen | Check `config.js` URL and key. Check the Supabase project is not paused and the bill is paid. |
| Changes don't show after deploy | Bump `?v=` in `index.html` (see §5), then hard-refresh. |
| Login fails for imported users | Run `select public.ensure_password(id) from public.users;` to give every user the default password `demo123`. |
| No late-job alerts | `select * from cron.job;` should list `aqar-escalations-and-alerts`. Run `select public.tick();` manually and check `app_config`. |
| Emails/WhatsApp stay "queued" | Add the Edge Function secrets (Step 4). Look at the `outbox.error` column. |
| Photos missing | Run `node import.mjs --photos-only`, or upload new ones from Buildings → edit → Photos. |

---

## 8. Further reading
- `docs/FEATURES.md`: every module, workflow, report and permission.
- `docs/DATA-MODEL.md`: tables, JSON record fields and SQL functions.
- `docs/DEPLOYMENT.md`: hosting options, backups, updating and monitoring.
- `assets/stock-photos/CREDITS.md`: photo sources (Unsplash licence). Replace them with your own photos when ready.
