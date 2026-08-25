# LogiSync — Operations Command

A single-page operations & QA command center for contact-center floor management.
Tracks shift tasks, coaching records, weekly QA numbers, AUX/break time, training,
attendance, and spiff validation. Client-only (no build step) — talks directly to
Supabase (Postgres + PostgREST/RPC) using the public anon key, with all privilege
enforcement done server-side in `SECURITY DEFINER` RPCs gated by a PIN.

## Structure

| Path | Purpose |
|------|---------|
| `src/index.html` | The entire app — markup plus one inline `<script>` with all logic (rendering, Supabase RPC calls, auth flow, CSV/XLSX import/export). |
| `src/config.js` | Per-client config: branding, Supabase URL + anon key, agents, categories, coaching dropdowns. **Git-ignored** — copy from `config.example.js`. |
| `src/config.example.js` | Template for `config.js`. |
| `src/sw.js` | Network-only service worker (no offline caching — avoids stale builds). |
| `src/tailwind.build.css` | Prebuilt Tailwind stylesheet. |
| `scripts/migrations/` | SQL migrations for the Supabase backend (auth RPCs, throttling, etc.). |
| `scripts/` | One-off maintenance/audit helpers. |

## Local development

The app is fully static. Serve `src/` with any static file server:

```bash
npx --yes serve -l 4173 src
```

Then open http://localhost:4173. It reads `src/config.js`, so create one from the
template first:

```bash
cp src/config.example.js src/config.js
```

## Deployment

Hosted on Vercel; production deploys from the `master` branch. Because `config.js`
is git-ignored, the deployed config is managed on the host (committed separately in
the Vercel project or provided at deploy time).

## Security model

- The Supabase **anon key is public by design** — it grants no direct table access.
- Every privileged action (task writes, admin user/department management, aux/training
  logging) goes through a `SECURITY DEFINER` RPC that re-validates the caller's PIN
  and role server-side. Client-side UI gating is convenience only, not the boundary.
- All user-supplied text is HTML-escaped before being rendered into the DOM.
