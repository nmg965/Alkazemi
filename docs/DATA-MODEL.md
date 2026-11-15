# Data model

All app data is in the Supabase Postgres `public` schema.

## Storage pattern

Each business table has the same shape:

```sql
id         text primary key       -- e.g. 'u-admin', 'p-KW-001', 'TK-1042'
data       jsonb not null         -- the full record (fields below)
updated_at timestamptz            -- set automatically by trigger
```

The browser loads the tables at sign-in, keeps them in memory, writes changes back through `upsert`, and listens on Supabase Realtime so every open screen updates live. The large history tables load only the most recent rows: notifs 900, outbox 500, audit log 500, patrols 600, visitors 400, stock moves 600.

This "document per row" design keeps the schema stable while features evolve. For reporting in SQL, use JSON operators, e.g. `select data->>'name', data->>'city' from properties;`.

## Tables and record fields

| Table | Rows in demo | Fields in `data` |
|---|---:|---|
| `meta` | 2 | Settings row (`id='settings'`): slaUrgentH, slaNormalH, repeatH, vehicleRepeatH, ownerThreshold, escalateRoles, channels, lowStock, orgName, seq (number counters), lastReminderRun, v |
| `users` | 58 | name, email, phone, title, role, perms[], props[] (assigned buildings), skills[] (trades), active, prefs (lang, theme, channels), tour |
| `properties` | 40 | code, name, type, country, city, address, area, plot, paci, bua, yearBuilt, owner, currency, supId, guardId, floors, photos[], coverId, docs[] (name, kind, number, issued, expiry, file), ppm[] (planned maintenance), createdAt |
| `units` | 873 | propId, code, no, floor, kind, area, rent, tenancy (rental/lease), status, tenantId, start, end, nextMaint |
| `tenants` | 757 | name, kind (individual/company), nationality, idNo, email, phone, unitId, deposit, payFreq, regNo |
| `tickets` | 161 | propId, unitId, location, category, title, desc, priority (P1–P4), emergency, status, reporterId, supId, managerId, techId, estCost, dueAt, media[], history[] (stage, by, at, note), arrivals[], job (notes, materials, labour, cost, photos), proc (purchase), rejectReason, createdAt |
| `rent` | 7,080 | unitId, month (YYYY-MM), due, amount, cur, paidOn, method, ref, receipt, by |
| `inspections` | 12 | propId, unitId, type, inspectorId, rooms[] (name, condition, photos, damages[]), meters, keys, summary, totalCost, currency, status, reviewedBy, reviewedAt, ticketIds[], at |
| `items` | 41 | sku, name, cat, unit, store, bin, qty, min (reorder level), cost, supplier |
| `stock_moves` | 140 | itemId, type (receive/issue/count), qty, ref, propId, note, by, at |
| `vehicles` | 14 | plate, make, model, year, type, driverId, odo, status, nextService, nextServiceKm, regExp (Daftar), insExp |
| `vehicle_jobs` | 40 | vehicleId, kind, issue, workerId, garage, expectedH, status, openedAt, startedAt, doneAt, odo, cost, notes, alerts |
| `patrols` | 165 | propId, guardId, checks[] (point, result OK/Issue/N/A, note), durationMin, at |
| `visitors` | 70 | propId, guardId, name, company, idNo, purpose, unitNo, ticketId, inAt, outAt |
| `notifs` | 941 | userId, kind, text, link, read, at |
| `audit_log` | 21 | text, by, at |

### Tables with real columns

| Table | Columns | Purpose |
|---|---|---|
| `outbox` | id, data (to, toName, userId, channel email/whatsapp, subject, body, ref, at), status (queued / waiting_keys / sent / failed), error, sent_at, attempts | Message queue read by the `aqar-alerts` Edge Function |
| `alerts` | id (`tk-<ticket>` / `vj-<vehicle job>`), kind (ticket_sla / vehicle_overtime), ref, count, first_at, last_at, resolved, resolved_at | Escalation state |
| `credentials` | user_id, hash (bcrypt) | Passwords. Not readable by the browser |
| `app_config` | key, value | `functions_url`, `anon_key` for the scheduler. Not readable by the browser |

## SQL functions (RPC)

| Function | Called by | Does |
|---|---|---|
| `login(p_email, p_password)` → user id or null | Sign-in screen | Checks the bcrypt hash and that the user is active |
| `set_password(p_email, p_password, p_user, p_new)` → bool | Users screen, profile | The admin, or the user themselves, sets a new password |
| `ensure_password(p_user)` → bool | App and import | Gives a user without a password the default `demo123` |
| `run_escalations(p_ref default null, p_force default false)` → int | `tick()` | Finds late tickets and over-time vehicle jobs, writes `notifs` and `outbox` rows to the escalation roles, and updates `alerts` |
| `escalate_now(p_ref)` | "Send alert now" button | Forces an alert for one job straight away |
| `queue_alert(...)` | internal | Writes one in-app plus email and WhatsApp message, respecting each user's preferences |
| `stage_waiting(...)`, `fmt_dur(...)` | internal | "Waiting on" text and "3 h 20 m late" formatting |
| `tick()` | pg_cron every 5 min | `run_escalations()`, then HTTP POST to the `aqar-alerts` function |

## Storage

Bucket **`aqar-media`** (public read):
- `stock/buildings/*.jpg`: the placeholder building photos (from `assets/stock-photos`)
- uploads from the app: building photos, documents (licences and certificates), ticket and inspection photos and videos

The photo URLs are stored inside `properties.data.photos[]` and `tickets.data.media[]`. The import script rewrites them to your new project URL.

## Realtime

Every business table, plus `outbox` and `alerts`, is in the `supabase_realtime` publication.

## Backups and exports

- The full data export used for the demo is in `supabase/seed/data/*.json`, with one file per table as `[{id, data}]`.
- For a fresh export from any project: `select json_agg(json_build_object('id',id,'data',data)) from public.<table>;`, or use the Supabase dashboard's backup feature (Pro plan).
