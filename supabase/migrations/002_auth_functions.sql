-- Alkazemi Asset Management · 002 · sign-in
-- Passwords are bcrypt hashes in public.credentials. New users get the default password demo123
-- until an administrator sets a new one (Users & permissions → user → New password).

create or replace function public.ensure_password(p_user_id text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.users where id = p_user_id) then return false; end if;
  insert into public.credentials(user_id, hash) values (p_user_id, extensions.crypt('demo123', extensions.gen_salt('bf')))
  on conflict (user_id) do nothing;
  return true;
end $$;

-- returns the user id when email + password match an active user, otherwise null
create or replace function public.login(p_email text, p_password text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare u record; h text;
begin
  select id, data into u from public.users
   where lower(data->>'email') = lower(trim(p_email)) and coalesce(data->>'active','true') <> 'false' limit 1;
  if u.id is null then return null; end if;
  select hash into h from public.credentials where user_id = u.id;
  if h is null then
    insert into public.credentials(user_id, hash) values (u.id, extensions.crypt('demo123', extensions.gen_salt('bf'))) on conflict do nothing;
    select hash into h from public.credentials where user_id = u.id;
  end if;
  if extensions.crypt(p_password, h) = h then return u.id; end if;
  return null;
end $$;

-- an administrator (or the user themself) sets a new password
create or replace function public.set_password(p_admin_email text, p_admin_password text, p_user_id text, p_new_password text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare a text; ar text;
begin
  a := public.login(p_admin_email, p_admin_password);
  if a is null then return false; end if;
  select data->>'role' into ar from public.users where id = a;
  if ar <> 'admin' and a <> p_user_id then return false; end if;
  if length(coalesce(p_new_password,'')) < 6 then return false; end if;
  insert into public.credentials(user_id, hash) values (p_user_id, extensions.crypt(p_new_password, extensions.gen_salt('bf')))
  on conflict (user_id) do update set hash = excluded.hash, updated_at = now();
  return true;
end $$;

revoke all on function public.ensure_password(text), public.login(text,text), public.set_password(text,text,text,text) from public;
grant execute on function public.ensure_password(text), public.login(text,text), public.set_password(text,text,text,text) to anon, authenticated, service_role;
