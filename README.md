# Alkazemi Asset Management

Property and asset operations platform for Al-Kazemi Group (buildings, maintenance approvals, inspections, warehouse, fleet, rent), in English and Arabic.

- **Hosting:** Cloudflare Workers static assets (`public/`), deployed automatically from `main`.
- **Data:** Supabase project `daftr` (schema `aqar`) — database, file storage, scheduled late-job alerts and the `aqar-alerts` edge function.
- `public/app.js` and `public/app.css` are the built app (version a5d498df7c).
