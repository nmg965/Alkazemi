-- Alkazemi Asset Management · 001 · core tables
-- Every business table stores one record per row: id (text) + data (jsonb) + updated_at.
-- The browser app reads and writes these tables through the Supabase API (schema public).

create extension if not exists pgcrypto with schema extensions;

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['users','properties','units','tenants','tickets','rent','notifs','audit_log','inspections','items','stock_moves','vehicles','vehicle_jobs','patrols','visitors','meta'] loop
    execute format('create table if not exists public.%I (id text primary key, data jsonb not null default ''{}''::jsonb, updated_at timestamptz not null default now())', t);
    execute format('drop trigger if exists %I on public.%I', t||'_touch', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.touch_updated_at()', t||'_touch', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "app read" on public.%I', t);
    execute format('drop policy if exists "app write" on public.%I', t);
    execute format('create policy "app read" on public.%I for select to anon, authenticated using (true)', t);
    execute format('create policy "app write" on public.%I for all to anon, authenticated using (true) with check (true)', t);
    execute format('create index if not exists %I on public.%I (updated_at desc)', t||'_updated_idx', t);
  end loop;
end $$;

-- email / WhatsApp queue (sent by the aqar-alerts edge function)
create table if not exists public.outbox (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'queued',      -- queued | waiting_keys | sent | failed
  error text,
  sent_at timestamptz,
  attempts int not null default 0,
  updated_at timestamptz not null default now());
drop trigger if exists outbox_touch on public.outbox;
create trigger outbox_touch before update on public.outbox for each row execute function public.touch_updated_at();
create index if not exists outbox_updated_idx on public.outbox (updated_at desc);
create index if not exists outbox_status_idx on public.outbox (status);
alter table public.outbox enable row level security;
drop policy if exists "app read" on public.outbox;
drop policy if exists "app write" on public.outbox;
create policy "app read" on public.outbox for select to anon, authenticated using (true);
create policy "app write" on public.outbox for all to anon, authenticated using (true) with check (true);

-- late-job and vehicle-overtime alert tracker (written by run_escalations)
create table if not exists public.alerts (
  id text primary key,                         -- tk-<ticket id> or vj-<vehicle job id>
  kind text not null,                          -- ticket_sla | vehicle_overtime
  ref text not null,
  count int not null default 0,
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  resolved boolean not null default false,
  resolved_at timestamptz);
create index if not exists alerts_last_idx on public.alerts (last_at desc);
alter table public.alerts enable row level security;
drop policy if exists "app read" on public.alerts;
drop policy if exists "app resolve" on public.alerts;
create policy "app read" on public.alerts for select to anon, authenticated using (true);
create policy "app resolve" on public.alerts for update to anon, authenticated using (true) with check (true);

-- password hashes: never readable through the API
create table if not exists public.credentials (
  user_id text primary key,
  hash text not null,
  updated_at timestamptz not null default now());
alter table public.credentials enable row level security;
revoke all on public.credentials from anon, authenticated;

-- live updates for every screen
do $$
declare t text;
begin
  foreach t in array array['users','properties','units','tenants','tickets','rent','notifs','outbox','inspections','items','stock_moves','vehicles','vehicle_jobs','patrols','visitors','meta','alerts'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
