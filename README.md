# LogiSync — Operations Command

A single-page operations & QA command center for contact-center floor management.
Tracks shift tasks, coaching records, weekly QA numbers, AUX/break time, training,
attendance, spiff validation, and a leader-only audit log.

Client-only, **no build step**. The browser talks straight to Supabase
(Postgres + PostgREST/RPC) with the public anon key; every privileged action is
re-authorised server-side inside a `SECURITY DEFINER` RPC gated by the user's PIN.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how it actually works internally.

---

## Get running in two minutes

```bash
git clone https://github.com/muhammedkhaled664-jpg/logisync.git
cd logisync
npx --yes serve -l 4173 src
```

Open <http://localhost:4173>. That's it — no `npm install`, no bundler, no `.env`.

`src/config.js` is **committed to the repo** (it holds only the Supabase URL and
the public anon key), so a fresh clone connects to the live database immediately.
You are talking to production data — there is no staging environment.

## Repo layout

| Path | Purpose |
|------|---------|
| `src/index.html` | **The entire app.** ~4,800 lines: all markup, all CSS, and one inline `<script>` holding every bit of logic. |
| `src/config.js` | Branding, Supabase URL + anon key, business timezone, agent roster, categories, coaching dropdowns. **Tracked in git** — see below. |
| `src/config.example.js` | Template, for standing up a different client. |
| `src/tailwind.build.css` | Prebuilt Tailwind stylesheet. **Hand-patched, incomplete — read the warning below.** |
| `src/sw.js` | Network-only service worker. Deliberately caches nothing. |
| `src/logo.svg`, `logo.png` | Branding. The SVG is what the app loads. |
| `src/manifest.webmanifest` | PWA manifest (installable on phones). |
| `scripts/migrations/` | SQL migrations for the Supabase backend. **Incomplete — see Known gaps.** |
| `scripts/` | One-off maintenance and audit helpers, not part of the app. |
| `CLAUDE.md` | Notes for AI assistants working in this repo. |

### Why `config.js` is committed

It was git-ignored originally. Vercel deploys from git, so an ignored `config.js`
shipped a build with no database connection at all. It contains only the **anon**
key, which is public by design and already served to every browser that opens the
app. **Never put a `service_role` key in it.**

## Deploying

Production is <https://logisync-muhammed-khaled.vercel.app>, served from the
`master` branch. Push and Vercel builds automatically:

```bash
git push origin master
```

The Vercel project's **Root Directory is `src`**. If that ever resets to blank,
the site 404s because it serves the repo root instead. Don't let it drift.

To deploy local files without going through git:

```bash
npx --yes vercel --prod
```

## Things that will bite you

**1. Tailwind classes silently do nothing.**
`tailwind.build.css` is a static file pulled from an old deployment — there is no
Tailwind config and no build step regenerating it. If you add a utility class that
isn't already used elsewhere in the file, **it will not exist in the CSS and will
silently no-op.** No error, just missing styling.

A class can live in *either* `tailwind.build.css` or the `TAILWIND BUILD GAP
PATCH` block inside `index.html`'s `<style>` (~88 utilities that were missing and
had to be hand-written). So check **both** files — searching only the stylesheet
will report working classes as missing:

```bash
grep -l 'sm\\:grid-cols-2' src/tailwind.build.css src/index.html
```

Note the backslash: Tailwind escapes `:`, `.`, `/` and `[` `]` in selectors, so
`sm:grid-cols-2` is written `.sm\:grid-cols-2` in the CSS. Searching for the
unescaped name finds nothing and looks like a missing class.

The only fully reliable check is the browser: apply the class to an element and
confirm the computed style actually changes.

**2. Always escape user text before `innerHTML`.**
Use the existing `esc()` / `_esc()` helpers. A stored-XSS bug (unescaped task
descriptions in the shared feed) was found and fixed here; it is very easy to
reintroduce by copy-pasting a render function.

**3. The client is not the security boundary.**
Hiding a button does nothing. If an action must be restricted, it must be enforced
inside the RPC.

**4. Pushing requires the right GitHub account.**
This repo is owned by `muhammedkhaled664-jpg`. If `gh` has more than one account
logged in, git uses whichever is **active**, and pushes 403 with a confusing
"denied to <other-account>" error even though you appear authenticated:

```bash
gh auth status                                          # read the "Active account" line
gh auth switch --user muhammedkhaled664-jpg             # if it's the wrong one
```

## Known gaps

- **The migrations can't rebuild the database.** `001_auth_hardening.sql` and
  `002_anon_grant_hardening.sql` are in the repo, but the audit-log schema
  (`audit_log`, `_audit_trigger()`, the `zz_audit` triggers, `audit_visible()`,
  and the `_auth_user` wrapper) was applied directly in the Supabase SQL Editor
  and exists **only in the live database**. If that project were lost, git could
  not restore it.
- **Dead CSS.** `disabled:opacity-40`, `divide-y`, `first:ml-0` and several hover
  utilities are used in the markup but missing from the stylesheet, so disabled
  buttons look enabled and some lists render without separator lines.
- **Unescaped names.** Roster names are still interpolated raw into a few
  `onclick="fn('name')"` attributes with only single quotes escaped.
- **Shared-PC auto-login.** Sessions persist in `localStorage`, so a shared floor
  machine stays signed in as the last person until someone signs out.

## Security model

- The anon key is public by design and grants no useful direct table access.
- Auth chain: `verify_login` → `_auth_user(p_pin)` → `_auth_leader(p_pin)`.
  Every privileged RPC funnels through `_auth_user`, so the PIN is re-validated
  server-side on every single call. UI gating is convenience only.
- Row visibility is scoped **server-side** by role: agents see themselves,
  managers see their department, leaders see everything.
- Every table write is captured by an `AFTER INSERT/UPDATE/DELETE` trigger into
  `audit_log`, with PIN and password fields stripped. Triggers can't be bypassed
  from the client.
