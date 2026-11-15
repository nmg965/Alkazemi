-- Alkazemi Asset Management · 005 · every-5-minutes job
-- Runs the escalation engine, then asks the aqar-alerts edge function to send queued email/WhatsApp messages.
-- After running this file, store your project's details once (see README → Database setup → step 4):
--   insert into public.app_config(key, value) values
--     ('functions_url', 'https://<PROJECT-REF>.supabase.co/functions/v1'),
--     ('anon_key', '<ANON KEY>')
--   on conflict (key) do update set value = excluded.value;

create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.app_config (key text primary key, value text not null);
alter table public.app_config enable row level security;
revoke all on public.app_config from anon, authenticated;

create or replace function public.tick() returns void language plpgsql security definer set search_path = public, extensions as $$
declare fn text; k text;
begin
  perform public.run_escalations();
  select value into fn from public.app_config where key = 'functions_url';
  select value into k from public.app_config where key = 'anon_key';
  if fn is not null and k is not null then
    perform net.http_post(
      url := fn || '/aqar-alerts',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || k),
      body := '{}'::jsonb);
  end if;
end $$;
revoke all on function public.tick() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'aqar-escalations-and-alerts';
select cron.schedule('aqar-escalations-and-alerts', '*/5 * * * *', 'select public.tick()');
