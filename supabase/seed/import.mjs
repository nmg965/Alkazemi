#!/usr/bin/env node
/*
  Alkazemi Asset Management · load the demo data and sample photos into a Supabase project.

  Requires Node.js 18+ (no npm packages). Run from the repository root:

    SUPABASE_URL=https://<project-ref>.supabase.co \
    SUPABASE_SERVICE_ROLE_KEY=<service role key> \
    node supabase/seed/import.mjs

  Options
    --photos-only   only upload the sample photos and attach them to buildings that have none
                    (use this if you let the app create its own demo data on first open)
    --skip-history  do not import notifications, outbox (email/WhatsApp log) and audit log
    --dry-run       show what would be loaded, change nothing

  The service role key is in Supabase → Project Settings → API. Keep it secret: never put it in
  public/config.js or commit it.
*/
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const args = new Set(process.argv.slice(2));
const DRY = args.has('--dry-run');
const SOURCE_URL = 'https://qekfkosslaninyqkptlz.supabase.co'; // project the snapshot was exported from

if (!DRY && (!URL_ || !KEY)) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first (see the comment at the top of this file).');
  process.exit(1);
}
const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };

async function api(method, p, body, extra = {}) {
  const r = await fetch(URL_ + p, { method, headers: { ...H, ...extra }, body });
  if (!r.ok) throw new Error(`${method} ${p} → ${r.status} ${(await r.text()).slice(0, 300)}`);
  const t = await r.text();
  return t ? JSON.parse(t) : null;
}

// 1 · sample photos → storage bucket aqar-media/stock/buildings/
async function uploadPhotos() {
  const dir = path.join(root, 'assets', 'stock-photos');
  const files = (await readdir(dir)).filter(f => f.endsWith('.jpg'));
  for (const f of files) {
    if (DRY) continue;
    const buf = await readFile(path.join(dir, f));
    await api('POST', `/storage/v1/object/aqar-media/stock/buildings/${f}`, buf, { 'Content-Type': 'image/jpeg', 'x-upsert': 'true' });
  }
  console.log(`photos: ${files.length} ${DRY ? 'would be uploaded' : 'uploaded'}`);
}

// 2 · table data
const ORDER = ['meta', 'users', 'properties', 'units', 'tenants', 'tickets', 'rent', 'inspections', 'items', 'stock_moves',
  'vehicles', 'vehicle_jobs', 'patrols', 'visitors', 'alerts', 'notifs', 'outbox', 'audit_log'];
const HISTORY = new Set(['notifs', 'outbox', 'audit_log', 'alerts']);

async function importTables() {
  for (const t of ORDER) {
    if (args.has('--skip-history') && HISTORY.has(t)) continue;
    let txt = await readFile(path.join(here, 'data', t + '.json'), 'utf8');
    if (URL_) txt = txt.split(SOURCE_URL).join(URL_); // photo links point at the new project
    let rows = JSON.parse(txt);
    if (t === 'outbox') rows = rows.map(r => ({ ...r, status: r.status === 'sent' ? 'sent' : 'failed', error: r.error || 'Imported history — not sent' }));
    for (let i = 0; i < rows.length; i += 500) {
      const chunk = rows.slice(i, i + 500);
      if (!DRY) await api('POST', `/rest/v1/${t}`, JSON.stringify(chunk), { 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' });
    }
    console.log(`${t}: ${rows.length} rows ${DRY ? 'would be loaded' : 'loaded'}`);
  }
  // default password demo123 for every user (change it later in Users & permissions)
  const users = JSON.parse(await readFile(path.join(here, 'data', 'users.json'), 'utf8'));
  for (const u of users) if (!DRY) await api('POST', '/rest/v1/rpc/ensure_password', JSON.stringify({ p_user_id: u.id }), { 'Content-Type': 'application/json' });
  console.log(`passwords: ${users.length} users set to demo123${DRY ? ' (dry run)' : ''}`);
}

// --photos-only: attach 3 sample photos to every building that has none
const POOLS = {
  'Residential': ['res1', 'res2', 'res3', 'res4', 'res5', 'res6', 'res7', 'res8'],
  'Office': ['off1', 'off2', 'off3', 'off4', 'off5', 'off6', 'com2', 'com3', 'com4', 'com7'],
  'Commercial': ['com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'off4'],
  'Retail': ['ret1', 'ret2', 'ret3', 'ret4', 'ret6', 'com1'],
  'Industrial & Logistics': ['ind1', 'ind5', 'ind6', 'ind7', 'ind8', 'ind9', 'ind10'],
  'Mixed Portfolio': ['com1', 'com6', 'ret6', 'res3', 'off4', 'res6'],
};
async function attachPhotos() {
  const props = DRY ? [] : await api('GET', '/rest/v1/properties?select=id,data&order=id');
  const seen = {}; let n = 0;
  for (const p of props.sort((a, b) => String(a.data.code).localeCompare(String(b.data.code)))) {
    if ((p.data.photos || []).length) continue;
    const pool = POOLS[p.data.type] || ['com1', 'res1', 'off1'];
    const rn = seen[p.data.type] = (seen[p.data.type] ?? -1) + 1;
    const photos = [0, 1, 2].map(k => {
      const img = pool[(rn * 3 + k) % pool.length];
      return { id: `ph-stock-${p.id}-${k}`, name: img + '.jpg', url: `${URL_}/storage/v1/object/public/aqar-media/stock/buildings/${img}.jpg`, sample: true, at: new Date().toISOString() };
    });
    await api('PATCH', `/rest/v1/properties?id=eq.${encodeURIComponent(p.id)}`, JSON.stringify({ data: { ...p.data, photos, coverId: photos[0].id } }), { 'Content-Type': 'application/json', Prefer: 'return=minimal' });
    n++;
  }
  console.log(`photos attached to ${n} buildings`);
}

try {
  await uploadPhotos();
  if (args.has('--photos-only')) await attachPhotos();
  else await importTables();
  console.log('Done. Open the app and sign in with admin@akam-demo.com / demo123.');
} catch (e) {
  console.error('Stopped:', e.message);
  process.exit(1);
}
