-- LogiSync auth hardening — 2026-08-24
-- 1. Global auth throttle: after repeated failed PIN attempts in a rolling
--    window, add an increasing delay before the next check. Blunt but
--    effective against unlimited scripted PIN guessing over the public
--    anon RPC endpoints, without requiring per-user/per-IP tracking
--    (PostgREST calls don't expose the original client IP to Postgres).
-- 2. Close the silent weak-default-PIN bug in admin_save_user: creating a
--    user without an explicit PIN used to fall back to bcrypt('changeme').

create table if not exists public.auth_throttle (
  id boolean primary key default true check (id),
  fail_count int not null default 0,
  window_start timestamptz not null default now()
);
insert into public.auth_throttle (id) values (true) on conflict do nothing;
alter table public.auth_throttle enable row level security;
-- no policies -> no direct anon/authenticated access; only SECURITY DEFINER
-- functions (owner-privileged) touch this table.

create or replace function public._auth_user(p_pin text)
returns public.users
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  u public.users;
  v_fail_count int;
  v_window_start timestamptz;
begin
  if p_pin is null or length(p_pin) = 0 then
    raise exception 'AUTH_REQUIRED';
  end if;

  select fail_count, window_start into v_fail_count, v_window_start
    from public.auth_throttle where id = true for update;

  if v_window_start < now() - interval '10 minutes' then
    update public.auth_throttle set fail_count = 0, window_start = now() where id = true;
    v_fail_count := 0;
  end if;

  if v_fail_count >= 20 then
    perform pg_sleep(least(2 + (v_fail_count - 20) * 0.5, 15));
  end if;

  select * into u from public.users where pin = crypt(p_pin, pin) limit 1;
  if not found then
    update public.auth_throttle set fail_count = fail_count + 1 where id = true;
    raise exception 'INVALID_PIN';
  end if;

  return u;
end
$function$;

create or replace function public.verify_login(p_username text, p_pin text)
returns table(manager_name text, department text, is_leader boolean, email text, access_level text)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_fail_count int;
  v_window_start timestamptz;
begin
  select fail_count, window_start into v_fail_count, v_window_start
    from public.auth_throttle where id = true for update;

  if v_window_start < now() - interval '10 minutes' then
    update public.auth_throttle set fail_count = 0, window_start = now() where id = true;
    v_fail_count := 0;
  end if;

  if v_fail_count >= 20 then
    perform pg_sleep(least(2 + (v_fail_count - 20) * 0.5, 15));
  end if;

  return query
    select u.manager_name, u.department, u.is_leader, u.email, u.access_level
    from public.users u
    where lower(u.manager_name) = lower(p_username)
      and u.pin = crypt(p_pin, u.pin)
    limit 1;

  if not found then
    update public.auth_throttle set fail_count = fail_count + 1 where id = true;
  end if;
end
$function$;

create or replace function public.admin_save_user(
  p_pin text, p_id bigint, p_name text, p_email text, p_department text,
  p_role text, p_access_level text, p_is_leader boolean, p_new_pin text
)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare rid bigint;
begin
  perform public._auth_leader(p_pin);
  if p_id is null then
    if nullif(p_new_pin, '') is null then
      raise exception 'PIN_REQUIRED';
    end if;
    insert into public.users (manager_name, email, department, role, access_level, is_leader, pin)
    values (p_name, nullif(p_email,''), nullif(p_department,''), nullif(p_role,''),
            coalesce(nullif(p_access_level,''),'agent'), coalesce(p_is_leader,false),
            crypt(p_new_pin, gen_salt('bf')))
    returning id into rid;
  else
    update public.users set
      manager_name = p_name,
      email        = nullif(p_email,''),
      department   = nullif(p_department,''),
      role         = nullif(p_role,''),
      access_level = coalesce(nullif(p_access_level,''),'agent'),
      is_leader    = coalesce(p_is_leader,false),
      pin          = case when nullif(p_new_pin,'') is null then pin
                          else crypt(p_new_pin, gen_salt('bf')) end
    where id = p_id
    returning id into rid;
  end if;
  return rid;
end
$function$;
