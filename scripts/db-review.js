// Read-only Supabase security/RLS review via the Management API.
// Token is read from scripts/.supabase-token (git-ignored) so it never
// touches the command line or the repo. Run: node scripts/db-review.js
const https = require("https");
const fs = require("fs");
const path = require("path");

const REF = "fyvotlygsmqmkxwpcrzf";
const tokenPath = path.join(__dirname, ".supabase-token");
if (!fs.existsSync(tokenPath)) {
  console.error("Missing scripts/.supabase-token — paste your sbp_... token into that file first.");
  process.exit(1);
}
const TOKEN = fs.readFileSync(tokenPath, "utf8").trim();

function runSQL(query) {
  const body = JSON.stringify({ query });
  return new Promise((resolve) => {
    const req = https.request(
      {
        hostname: "api.supabase.com",
        path: `/v1/projects/${REF}/database/query`,
        method: "POST",
        headers: {
          Authorization: `Bearer ${TOKEN}`,
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => resolve({ status: res.statusCode, data }));
      }
    );
    req.on("error", (e) => resolve({ status: 0, data: String(e) }));
    req.write(body);
    req.end();
  });
}

const CHECKS = [
  ["Tables + RLS enabled (public)",
    `select tablename, rowsecurity as rls_enabled
       from pg_tables where schemaname='public' order by tablename;`],
  ["Tables in public with RLS DISABLED (risk)",
    `select tablename from pg_tables
       where schemaname='public' and rowsecurity=false order by tablename;`],
  ["RLS policies (public)",
    `select tablename, policyname, cmd, roles::text
       from pg_policies where schemaname='public' order by tablename, policyname;`],
  ["Direct table grants to anon/authenticated (public)",
    `select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privs
       from information_schema.role_table_grants
       where table_schema='public' and grantee in ('anon','authenticated')
       group by table_name, grantee order by table_name, grantee;`],
  ["SECURITY DEFINER functions + search_path (public)",
    `select p.proname, p.prosecdef as security_definer, p.proconfig as config
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prosecdef order by p.proname;`],
  ["Definition of _auth_leader (the admin gate)",
    `select pg_get_functiondef(p.oid) as def
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='_auth_leader';`],
  ["Does anon/authenticated have SELECT on users (PIN exposure)?",
    `select grantee, privilege_type from information_schema.role_table_grants
       where table_schema='public' and table_name='users'
         and grantee in ('anon','authenticated');`],
];

(async () => {
  for (const [label, sql] of CHECKS) {
    const r = await runSQL(sql);
    console.log("\n========== " + label + " ==========");
    if (r.status !== 200 && r.status !== 201) {
      console.log("HTTP " + r.status + ": " + r.data);
      continue;
    }
    try {
      console.log(JSON.stringify(JSON.parse(r.data), null, 2));
    } catch {
      console.log(r.data);
    }
  }
})();
