-- LogiSync anon grant hardening — 2026-09-16
--
-- Audit of the live DB (project fyvotlygsmqmkxwpcrzf) found that `anon` and
-- `authenticated` held INSERT/UPDATE/DELETE/TRUNCATE on EVERY table in public —
-- the signature of a blanket `grant all on all tables in schema public`. The
-- anon key is public by design (shipped to every browser in src/config.js), so
-- the only thing standing in front of those grants was RLS.
--
-- It was NOT exploitable via PostgREST: RLS is enabled on all 13 tables and the
-- only three policies that existed were SELECT-only with `with_check = null`, so
-- no write path existed. Two things still warranted fixing:
--   * TRUNCATE ignores RLS entirely. It was unreachable only because PostgREST
--     never issues TRUNCATE — a latent hole, not a closed one.
--   * `recurring_tasks` had an anon SELECT grant AND a `qual = true` policy, so
--     every row would have been public to anyone with the anon key as soon as
--     that table was populated. It happened to be empty.
--
-- Why revoking is safe: src/index.html contains exactly three `.from()` calls,
-- all `.select()`, against `departments` and `department_aux_limits`. There are
-- zero direct client writes. Every mutation goes through a SECURITY DEFINER RPC
-- (42 of them, all owned by `postgres`, which also owns all 13 tables), so the
-- RPCs execute as owner and ignore the anon role's grants entirely.
--
-- Everything below is idempotent and safe to re-run.


-- 1. Pin search_path on every SECURITY DEFINER function that is missing it.
--    Non-breaking: it only hardens name resolution against search_path attacks.
--    Matches the `public, extensions` convention set in 001_auth_hardening.sql.
do $$
declare r record; n int := 0;
begin
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prosecdef
       and (p.proconfig is null
            or not exists (select 1 from unnest(p.proconfig) x where x like 'search_path=%'))
  loop
    execute format('alter function public.%I(%s) set search_path = public, extensions',
                   r.proname, r.args);
    raise notice 'pinned search_path -> %(%)', r.proname, r.args;
    n := n + 1;
  end loop;
  raise notice 'search_path fixes applied: %', n;
end $$;


-- 2. Strip every WRITE privilege from anon/authenticated on all public tables.
--    SELECT is deliberately left alone here; step 3 handles reads table by table.
do $$
declare r record; n int := 0;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger '
      || 'on table public.%I from anon, authenticated', r.tablename);
    n := n + 1;
  end loop;
  raise notice 'write privileges revoked on % table(s)', n;
end $$;


-- 3. Reads. The app needs anon SELECT on exactly two tables; everything else
--    should be unreachable. Guarded so a missing table cannot abort the script.
do $$
declare t text;
begin
  -- Fully closed to the public key. `users`/`auth_throttle` in particular were
  -- returning HTTP 200 with an empty body before this (grant present, RLS
  -- filtering) — PIN hashes were protected by RLS alone. Now there is no grant.
  foreach t in array array[
    'users', 'auth_throttle', 'audit_log', 'tasks', 'weekly_numbers',
    'coaching_records', 'aux_logs', 'spiff_sheet',
    'recurring_tasks', 'attendance_logs', 'training_logs'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format('revoke all privileges on table public.%I from anon, authenticated', t);
    else
      raise notice 'skip (absent): public.%', t;
    end if;
  end loop;
end $$;

-- `recurring_tasks` also carried a permissive read policy. Drop it — the client
-- never reads this table directly; it is served through SECURITY DEFINER RPCs.
drop policy if exists recurring_tasks_anon_read on public.recurring_tasks;


-- 4. Verification. Expected results after applying this migration:
--
--    a) No write privileges remain for anon/authenticated  -> 0 rows
--       select table_name, grantee, privilege_type
--         from information_schema.role_table_grants
--        where table_schema = 'public' and grantee in ('anon','authenticated')
--          and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
--
--    b) anon SELECT survives on exactly the two tables the app reads -> 2 rows
--       select table_name, grantee, privilege_type
--         from information_schema.role_table_grants
--        where table_schema = 'public' and grantee = 'anon'
--          and privilege_type = 'SELECT';
--
--    c) No SECURITY DEFINER function is missing search_path -> still_missing = 0
--       select count(*) filter (where p.proconfig is null
--                or not exists (select 1 from unnest(p.proconfig) x
--                                where x like 'search_path=%')) as still_missing
--         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--        where n.nspname = 'public' and p.prosecdef;
--
-- Confirmed live against the anon key on 2026-09-16 after applying:
--   * departments -> 200 with rows; department_aux_limits -> 200. App reads OK.
--   * tasks_visible / floor_status / admin_list_users -> still execute, and a
--     wrong PIN raises INVALID_PIN. SECURITY DEFINER RPCs unaffected.
--   * DELETE on tasks / users / weekly_numbers -> 401, SQLSTATE 42501.
--   * The other 11 tables -> 401 to the anon key.
--
--
-- NOT changed by this migration, and worth knowing:
--
--   * RLS was already enabled on all 13 tables; this migration does not touch
--     RLS or add policies. `departments` and `department_aux_limits` keep their
--     SELECT-only `qual = true` policies, which the app depends on.
--   * zz_audit triggers cover 11 of 13 tables. The two without one are correct:
--     `audit_log` (a trigger there would recurse) and `auth_throttle` (a
--     single-row counter bumped on every login attempt — auditing it would
--     flood the log).
--
-- RECURRENCE RISK: if `pg_default_acl` holds an `alter default privileges`
-- entry for schema public, every NEW table will silently inherit the same
-- `grant all` and undo this. Check before adding tables:
--   select n.nspname, pg_get_userbyid(d.defaclrole), d.defaclobjtype, d.defaclacl
--     from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace;
