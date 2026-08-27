# LogiSync — project notes for Claude Code

See global `~/.claude/CLAUDE.md` first for machine-level quirks (network-drive git, missing CLI tools, PowerShell issues) — those apply here too.

## What this is
A single-page operations/QA tool for a call-center floor (tasks, coaching, weekly QA numbers, AUX/break tracking, training, attendance, spiff validation). No build step — `src/index.html` is the entire app (markup + one inline `<script>`). Backed by Supabase (Postgres + PostgREST/RPC), auth is a username+PIN system where every privileged action goes through a `SECURITY DEFINER` RPC that re-validates the PIN server-side.

## Deploy pipeline
- GitHub: `github.com/muhammedkhaled664-jpg/logisync` — **public**, `master` branch, auto-deploys to Vercel on push.
- Vercel project `logisync` (owner `muhammedkhaled664-jpg`), production domain `logisync-muhammed-khaled.vercel.app`. **Root Directory is set to `src`** (was `null` originally — that made the first git-based deploy 404 by serving the repo root instead of `src/`; don't let it drift back).
- `src/config.js` is **intentionally tracked in git** (not ignored) — it holds only the Supabase anon/public key, which is safe to commit and already served to every browser. Git-based Vercel deploys need it in the repo or the build ships with no Supabase connection. Never put a `service_role` key here.
- CLI deploy alternative: `npx vercel --prod` (authed as muhammedkhaled664-jpg) — uploads local files directly, bypassing git entirely.

## `tailwind.build.css` is a static, hand-patched file — treat it carefully
This CSS was pulled from a Vercel deployment (see `scripts/pull-source.js` and the "Recover current production source" commit) — there's no original Tailwind config, and it was missing **88 utility classes** the app actually uses (confirmed by diffing every class in `index.html` against the compiled CSS with correct Tailwind selector-escaping — see the `TAILWIND BUILD GAP PATCH` block in `index.html`'s `<style>`). If you add a new Tailwind utility class to the HTML that isn't already used elsewhere in the file, **it will not exist in the CSS and will silently no-op** (no error, just broken/missing styling). Before shipping a new class, grep `tailwind.build.css` for it first, or verify visually in the browser — don't assume Tailwind classes "just work" here like they would with a real build pipeline.

## Security model
- The Supabase anon key is public by design — RLS + the `SECURITY DEFINER` RPCs (in `scripts/migrations/001_auth_hardening.sql` and the live DB) are the actual boundary, not the client.
- **Always HTML-escape user-controlled strings before `innerHTML`** — use the existing `esc()`/`_esc()` helpers. A stored-XSS bug (unescaped task descriptions in the shared live feed) was found and fixed; it's an easy pattern to reintroduce in a new render function if you copy-paste without checking.
- Auth flow: `verify_login` → `_auth_user` (PIN check) → `_auth_leader` (role gate, used by admin RPCs). Confirmed server-side: an invalid PIN is rejected before reaching any privileged logic.

## Supabase access for Claude
The connected Supabase MCP connector previously pointed at the wrong project ("QA-Alex", not this app's `fyvotlygsmqmkxwpcrzf`) — it was disconnected/reconnected via the Claude Code desktop app's Connectors settings. If `list_projects` still doesn't show `fyvotlygsmqmkxwpcrzf` / "logisync" under the "Muhammed khaled" org, the fix is *not* a different account — that account already has access (confirmed via the Supabase dashboard) — it's re-authorizing the connector with the right org selected. A brand-new chat session is needed to pick up a connector reconnected mid-session.

## Known dead-code pattern
Before this session, `parkStaleTasks()` and `importTasks()` were fully implemented (real RPC calls, tested logic) but had zero UI callers — silently unreachable features. Both are now wired to buttons (leader-only, gated via the `isLeader` toggle in `login()`). If you find another function with no `onclick`/caller anywhere in the file, don't assume it's unused cruft — check whether it's a real feature that just never got a button.
