-- Alkazemi Asset Management · 003 · late-job escalation engine
-- Every job must be fixed within Settings.slaUrgentH (Emergency/Urgent, default 24 h) or
-- Settings.slaNormalH (Normal/Planned, default 48 h) from the time it was reported.
-- Late jobs alert the building supervisor, managers, owners and admin (Settings.escalateRoles)
-- in the app, by email and by WhatsApp, repeating every Settings.repeatH hours until closed.
-- Vehicle repairs that run past their expected hours alert the worker and the managers.

create or replace function public.fmt_dur(i interval) returns text language plpgsql immutable as $$
declare s bigint := greatest(0, floor(extract(epoch from i))); h bigint := s / 3600; m bigint := (s % 3600) / 60;
begin
  if h >= 48 then return (h/24)::text || 'd ' || (h%24)::text || 'h'; end if;
  if h > 0 then return h::text || 'h ' || lpad(m::text, 2, '0') || 'm'; end if;
  return m::text || 'm';
end $$;

create or replace function public.stage_waiting(t jsonb) returns text language plpgsql stable set search_path = public as $$
declare st text := t->>'status';
begin
  if st = 'reported' then return coalesce((select data->>'name' from users where id = t->>'supId'), 'Supervisor'); end if;
  if st in ('mgr_approval','job_done') then return 'Operations manager'; end if;
  if st = 'owner_approval' then return 'Owner'; end if;
  if st in ('assigned','in_progress') then return coalesce((select data->>'name' from users where id = t->>'techId'), 'Technician'); end if;
  if st = 'procurement' then return 'Procurement'; end if;
  return '';
end $$;

-- in-app notification + email/WhatsApp outbox rows for one person, honouring their preferences and the channel settings
create or replace function public.queue_alert(p_user text, p_text text, p_subject text, p_body text, p_link jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare u jsonb; ch jsonb; at text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'); sfx text := to_hex((extract(epoch from clock_timestamp())*1000)::bigint) || substr(md5(random()::text), 1, 4);
begin
  select data into u from users where id = p_user;
  if u is null or coalesce(u->>'active','true') = 'false' then return; end if;
  select coalesce(data->'channels', '{}'::jsonb) into ch from meta where id = 'settings';
  ch := coalesce(ch, '{}'::jsonb);
  insert into notifs(id, data) values ('n-' || sfx, jsonb_build_object('id','n-'||sfx,'userId',p_user,'text',p_text,'at',at,'read',false,'link',p_link,'kind','late'));
  if coalesce(ch->>'email','true') <> 'false' and coalesce(u->'prefs'->>'email','true') <> 'false' and coalesce(u->>'email','') <> '' then
    insert into outbox(id, data) values ('e-' || sfx, jsonb_build_object('id','e-'||sfx,'at',at,'channel','email','to',u->>'email','toName',u->>'name','userId',p_user,'subject',p_subject,'body',p_body,'ref',p_link->>'id'));
  end if;
  if coalesce(ch->>'whatsapp','true') <> 'false' and coalesce(u->'prefs'->>'whatsapp','true') <> 'false' and coalesce(u->>'phone','') <> '' then
    insert into outbox(id, data) values ('w-' || sfx, jsonb_build_object('id','w-'||sfx,'at',at,'channel','whatsapp','to',u->>'phone','toName',u->>'name','userId',p_user,'subject',p_subject,'body','*'||p_subject||E'*\n'||p_body,'ref',p_link->>'id'));
  end if;
end $$;

create or replace function public.run_escalations(p_ref text default null, p_force boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; urgent_h numeric; normal_h numeric; rep interval; vrep interval; roles jsonb;
  t record; p jsonb; a record; due timestamptz; sla numeric; n int; cnt int := 0; who text; recips text[]; late text;
  j record; v jsonb; over text;
begin
  select data into s from meta where id = 'settings';
  s := coalesce(s, '{}'::jsonb);
  urgent_h := coalesce((s->>'slaUrgentH')::numeric, 24);
  normal_h := coalesce((s->>'slaNormalH')::numeric, 48);
  rep := make_interval(secs => coalesce((s->>'repeatH')::numeric, 4) * 3600);
  vrep := make_interval(secs => coalesce((s->>'vehicleRepeatH')::numeric, 2) * 3600);
  roles := coalesce(s->'escalateRoles', '["supervisor","manager","owner","admin"]'::jsonb);

  -- close alerts for jobs that are finished
  update alerts al set resolved = true, resolved_at = now()
   where al.kind = 'ticket_sla' and not al.resolved
     and exists (select 1 from tickets tk where tk.id = al.ref and tk.data->>'status' in ('closed','rejected'));
  update alerts al set resolved = true, resolved_at = now()
   where al.kind = 'vehicle_overtime' and not al.resolved
     and exists (select 1 from vehicle_jobs vj where vj.id = al.ref and vj.data->>'status' <> 'in_progress');

  for t in select id, data from tickets where data->>'status' not in ('closed','rejected') and (p_ref is null or id = p_ref) loop
    sla := case when t.data->>'priority' in ('P1','P2') then urgent_h else normal_h end;
    due := coalesce((t.data->>'dueAt')::timestamptz, (t.data->>'createdAt')::timestamptz + make_interval(secs => sla * 3600));
    continue when due is null or now() <= due;
    select * into a from alerts where id = 'tk-' || t.id;
    if not p_force and a.id is not null and not a.resolved and now() - a.last_at < rep then continue; end if;
    insert into alerts(id, kind, ref, count, first_at, last_at, resolved)
      values ('tk-' || t.id, 'ticket_sla', t.id, 1, now(), now(), false)
      on conflict (id) do update set count = alerts.count + 1, last_at = now(), resolved = false, resolved_at = null
      returning count into n;
    select data into p from properties where id = t.data->>'propId';
    late := fmt_dur(now() - due);
    who := stage_waiting(t.data);
    recips := array[]::text[];
    if roles ? 'supervisor' then recips := recips || coalesce(t.data->>'supId', p->>'supId'); end if;
    recips := recips || array(select id from users where data->>'role' in (select jsonb_array_elements_text(roles)) and data->>'role' <> 'supervisor' and coalesce(data->>'active','true') <> 'false');
    perform queue_alert(r,
      'LATE ' || late || ' · ' || t.id || ' · ' || coalesce(t.data->>'title','') || ' at ' || coalesce(p->>'code','') || ' (alert #' || n || ')',
      'LATE JOB · alert #' || n || ' · ' || t.id || ' · ' || coalesce(p->>'code',''),
      t.id || ' · ' || coalesce(t.data->>'title','') || E'\nBuilding: ' || coalesce(p->>'code','') || ' ' || coalesce(p->>'name','') ||
        E'\nLocation: ' || coalesce(t.data->>'location','') || E'\nThis job is ' || late || ' past its ' || trim(to_char(sla,'FM999')) || '-hour deadline.' ||
        case when who <> '' then ' Waiting on: ' || who || '.' else '' end || E'\n\nOpen Alkazemi Asset Management to act on it.',
      jsonb_build_object('view','tickets','id',t.id))
    from (select distinct unnest(recips) r) x where r is not null;
    cnt := cnt + 1;
  end loop;

  for j in select id, data from vehicle_jobs where data->>'status' = 'in_progress' and data->>'startedAt' is not null and (p_ref is null or id = p_ref) loop
    continue when now() <= (j.data->>'startedAt')::timestamptz + make_interval(secs => coalesce((j.data->>'expectedH')::numeric, 4) * 3600);
    select * into a from alerts where id = 'vj-' || j.id;
    if not p_force and a.id is not null and not a.resolved and now() - a.last_at < vrep then continue; end if;
    insert into alerts(id, kind, ref, count, first_at, last_at, resolved)
      values ('vj-' || j.id, 'vehicle_overtime', j.id, 1, now(), now(), false)
      on conflict (id) do update set count = alerts.count + 1, last_at = now(), resolved = false, resolved_at = null
      returning count into n;
    update vehicle_jobs set data = data || jsonb_build_object('alerts', n) where id = j.id;
    select data into v from vehicles where id = j.data->>'vehicleId';
    over := fmt_dur(now() - (j.data->>'startedAt')::timestamptz - make_interval(secs => coalesce((j.data->>'expectedH')::numeric, 4) * 3600));
    perform queue_alert(r,
      'Repair overtime ' || over || ' · ' || coalesce(v->>'plate','') || ' ' || coalesce(v->>'make','') || ' ' || coalesce(v->>'model','') || ' · ' || coalesce(j.data->>'issue',''),
      'Vehicle repair over time · ' || coalesce(v->>'plate',''),
      'Repair job ' || j.id || ' on ' || coalesce(v->>'plate','') || ' was expected to take ' || coalesce(j.data->>'expectedH','?') || ' h and is now ' || over || E' over.\nIssue: ' || coalesce(j.data->>'issue','') || E'\nGarage: ' || coalesce(j.data->>'garage',''),
      jsonb_build_object('view','fleet','id',j.id))
    from (select distinct r from unnest(array[j.data->>'workerId'] || array(select id from users where data->>'role' = 'manager' and coalesce(data->>'active','true') <> 'false')) r) x where r is not null;
    cnt := cnt + 1;
  end loop;
  return cnt;
end $$;

-- "Send late-job alerts now" / "Alert now" buttons in the app
create or replace function public.escalate_now(p_ref text default null) returns int
language sql security definer set search_path = public as $$ select public.run_escalations(p_ref, true) $$;

revoke all on function public.run_escalations(text, boolean), public.queue_alert(text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.escalate_now(text) to anon, authenticated, service_role;
