# LogiSync — Architecture

How the app is actually put together. For setup and deployment, see
[README.md](README.md).

---

## 1. The shape of it

```
Browser (one HTML file)
    |
    |  supabase-js  ->  HTTPS
    v
Supabase PostgREST
    |
    |  every call lands on a SECURITY DEFINER function
    v
Postgres  --(AFTER row triggers)-->  audit_log
```

There is no server of our own, no API layer, no build step. `src/index.html` is
shipped verbatim to the browser and is the whole client. Vercel is a static file
host. All logic that *matters* — who may see what, who may change what — lives in
Postgres functions.

### Why one file

It began as a single-file tool and stayed that way deliberately: there is no
toolchain to break, deploying is copying a file, and anyone can open it and read
top to bottom. The cost is a ~4,800-line file, so the conventions below exist to
keep it navigable.

### Finding your way around `index.html`

The inline `<script>` is divided by banner comments. Grep for them:

| Marker | Contains |
|---|---|
| `Session persistence` | localStorage session save/restore |
| `Hierarchy / task scoping` | `applyTaskScope`, role-based filtering |
| `Double-submit guard` | `_guard` / `_release` |
| `CSV EXPORT HELPERS` | CSV/XLSX row builders |
| `WEEKLY NUMBERS` | QA numbers grid |
| `Live Floor Status` | Shared floor board |
| `Global search` | Scoped task search |
| `COACHING` | Coaching records |
| `AUX TRACKER` | Break/aux tracking |
| `TRAINING TRACKER` | Training sessions |
| `ATTENDANCE` | Check in / check out |
| `SPIFF VALIDATION` | Spiff checks |
| `AUDIT LOG (leaders only)` | Audit viewer |
| `ADMIN (leaders only)` | Users, departments, aux limits |
| `IMPORT (Excel / CSV)` | Bulk task import |
| `BRANDED MONTHLY REPORT` | Monthly report generator |
| `LEADERSHIP MODE` | Leadership dashboard |
| `SMART INSIGHTS` | Derived insights |

Naming convention: functions prefixed `_` are internal helpers
(`_bizDate`, `_guard`, `_buildAuxRows`); unprefixed ones are user-facing actions
usually wired to an `onclick` (`startAux`, `checkIn`, `openAudit`).

---

## 2. Authentication

There are no passwords and no Supabase Auth. Identity is a **username + PIN**,
and the PIN is re-checked on the server for every privileged call.

```
verify_login(p_username, p_pin)      -- login screen; returns the user row
      |
      v
_auth_user(p_pin)                    -- called by every privileged RPC
      |                                 raises INVALID_PIN if wrong
      v
_auth_leader(p_pin)                  -- admin-only RPCs
                                        raises LEADER_REQUIRED if not a leader
```

**The chokepoint is the point.** All 37 RPCs funnel through `_auth_user`, so a
change there (rate limiting, logging, actor tagging) propagates everywhere at
once. That is how audit actor-tagging was added without touching 35 functions:
`_auth_user` was renamed `_auth_user_core` and wrapped by a new `_auth_user` that
calls the core then sets a transaction-local GUC.

> **Postgres gotcha, learned the hard way.** A function's `SET` clause saves and
> restores *all* GUCs on exit — which silently reverted the transaction-local
> `set_config('logisync.actor', ..., true)` and made every audit row's actor NULL.
> The wrapper therefore has **no `SET` clause**; it is safe because it only uses
> schema-qualified names and `pg_catalog` builtins. The core function keeps its own.

### Roles

`access_level` is one of `agent`, `manager`, `leader`.

| Role | Sees |
|---|---|
| `agent` | Only their own rows |
| `manager` | Their department |
| `leader` | Everything, plus Admin and Audit Log |

Scoping is applied **server-side** in the `*_visible` RPCs
(`tasks_visible`, `aux_visible`, `attendance_visible`, `training_visible`,
`coaching_visible`, `weekly_visible`, `audit_visible`).

> **Do not join a role-scoped result with `floor_status` on the client.**
> `floor_status` deliberately returns the *entire floor* so everyone can see who
> is available. The `*_visible` RPCs return only what your role permits. Joining
> them client-side silently drops people and produces wrong output — this caused
> a bug where checked-in agents were shown as "OOO".

---

## 3. Server surface

The client never writes to tables directly. Two read-only table reads exist
(`departments`, `department_aux_limits`); everything else is an RPC.

**Auth & identity:** `verify_login`, `visible_members`

**Tasks:** `tasks_visible`, `secure_add_task`, `secure_update_task`,
`secure_archive_done`, `secure_park_stale`, `secure_purge_parked`,
`secure_append_briefing`

**Aux / breaks:** `aux_visible`, `aux_open_count`, `secure_start_aux`,
`secure_stop_aux`, `secure_delete_aux`

**Training:** `training_visible`, `secure_start_training`,
`secure_stop_training`, `secure_delete_training`

**Attendance:** `attendance_visible`, `floor_status`, `secure_check_in`,
`secure_check_out`, `secure_delete_attendance`

**Coaching:** `coaching_visible`, `secure_save_coaching`, `secure_delete_coaching`

**QA numbers & spiff:** `weekly_visible`, `secure_save_weekly`, `spiff_get`,
`spiff_save`

**Admin (leader-only):** `admin_list_users`, `admin_save_user`,
`admin_delete_user`, `admin_save_department`, `admin_delete_department`,
`admin_set_aux_limit`

**Audit (leader-only):** `audit_visible`

---

## 4. Screens

One `#main-app` shell swaps between hidden `*-view` divs. There is no router and
no URL state — reloading always returns to the task board.

Views: `overview-view`, `aux-view`, `training-view`, `attendance-view`,
`coaching-view`, `numbers-view`, `spiff-view`, `audit-view`.

Modals: `admin-modal`, `coach-modal`, `floor-modal`, `search-modal`,
`spiff-teams-modal`.

Navigation is duplicated for desktop (`tabAux`, `tabAudit`, …) and mobile
(`mTabAux`, `mTabAudit`, …). **Both sets must be updated together** — a new screen
needs a sidebar button *and* a mobile tab, and leader-only screens must be
hidden/shown in `login()` for both.

`showBoard()` and `_activateReportTab()` are responsible for hiding every view;
if you add a view and forget to register it there, it will bleed through on top
of other screens.

---

## 5. Session persistence

The session used to live only in a JavaScript variable, so any reload returned
the user to the login screen. On phones the OS discards backgrounded tabs
constantly, so agents were being logged out all day.

```
login()  --success-->  _saveSession(username, pin)     -> localStorage
page load ----------->  _restoreSession()              -> login({username, pin})
logout() ------------>  _clearSession()
```

Design decisions worth knowing:

- **`localStorage`, not `sessionStorage`.** `sessionStorage` is scoped to a single
  tab, so a phone opening the app from a bookmark or after a browser relaunch saw
  an empty store and never restored. `_readSession()` still reads the old
  `sessionStorage` key once so pre-existing sessions carry over.
- **The server still decides.** Restore re-runs `verify_login`, so a changed or
  revoked PIN kills the session.
- **A failed *connection* must not clear the session.** `login()` sets
  `_loginTransportError` to distinguish "the server said no" from "we never
  reached the server". Only a real rejection clears storage; transport failures
  retry three times and otherwise leave the session for the next load. Without
  this, one wifi-to-data handover signed an agent out permanently.

**Trade-off:** a shared floor PC now stays signed in as the last person until
someone presses logout. That is the accepted cost of not logging phones out.

There is also a known race: the restore retries for up to ~6 seconds, and a
manual login during that window can be overwritten by the restore completing
afterwards.

---

## 6. Time and timezones

The floor runs on the **US Eastern campaign day** while staff devices sit in other
zones (typically Africa/Cairo). If day boundaries came from each device's clock,
one shift would file under two different dates.

Everything therefore resolves through one business timezone, set by
`config.js -> timezone` and read lazily via `_bizTz()`:

| Helper | Purpose |
|---|---|
| `_bizDate(d)` | `YYYY-MM-DD` in business time (uses `en-CA` for that format) |
| `_bizDayStart(s)` | Midnight of a business day, DST-safe via a two-pass offset |
| `_bizRange(from, to)` | Start/end instants for a date range |
| `_bizOffsetMinutes(d)` | UTC offset derived from `Intl.formatToParts` |
| `_bizTime(iso)` / `_bizDateDisplay(iso)` | Display formatting |
| `_todayLocal()` | Today, in business time |

Durations are unaffected — those come from server timestamps.

> `_bizTz()` is a **function**, not a constant, on purpose. As an eagerly-evaluated
> `const` it read `CFG` before `config.js` had applied and silently fell back to
> the device zone.

> **The Supabase `<script>` tag must stay eager.** Adding `defer` to it once made
> `supabase.createClient()` throw, which aborted the *entire* inline script — the
> visible symptom was an unrelated timezone bug. Chart.js is deferred and that is
> fine.

---

## 7. Live updates and optimistic writes

Trackers poll every 8 seconds; the task board every 10. All pollers are guarded
so a hidden tab does no work:

```js
setInterval(() => { if (!document.hidden) loadAux(); }, 8000);
```

Timers are stored (`_auxSync`, `_trainSync`, `_attSync`, `_floorTimer`,
`liveSyncInterval`) and cleared by their matching `_stopXTicker` on view change or
logout. **Forgetting to clear one leaks a timer per view switch.**

Actions that felt slow (stopping a break, checking out) use optimistic updates:

```
_guard(key)  ->  mutate the local row  ->  re-render  ->  await RPC
                                              |
                                        on error: restore previous value,
                                        re-render, surface the error
```

`_guard` / `_release` also act as a double-submit mutex — `_guard` returns false
if the same key is already in flight, with a 3-second auto-release as a backstop.

---

## 8. Audit log

Auditing is enforced at the **data layer**, not in the app, so it cannot be
bypassed by any client:

- An `AFTER INSERT / UPDATE / DELETE ... FOR EACH ROW` trigger named `zz_audit`
  is attached to every public table except `audit_log` (would recurse) and
  `auth_throttle` (pure noise).
- `_audit_trigger()` records `to_jsonb(old)` and `to_jsonb(new)` minus the
  `pin`, `password` and `new_pin` keys.
- The actor comes from the transaction-local GUC `logisync.actor`, set by the
  `_auth_user` wrapper described in §2.
- `audit_log` has RLS enabled and all privileges revoked from `anon` and
  `authenticated`. Leaders read it only through `audit_visible(p_pin, …)`, which
  calls `_auth_leader`.

Client side, `renderAudit()` shows a human-readable diff via `_auditChangeText()`
(e.g. `access_level: agent -> manager`), and `exportAuditExcel()` includes a
`Before (raw)` column holding the full pre-change row, which makes an accidental
delete recoverable.

---

## 9. Reports and exports

Each tracker has paired builders — `_buildAuxRows` / `_buildAuxSummaryRows`, and
the same for attendance, training, coaching, numbers and audit. Exports write a
**Summary** sheet and a **Detail** sheet, with `_autoFitCols()` sizing columns.

`_setRange(prefix, span, loader)` drives the Today / 7 days / Month presets shared
by the aux, training and attendance screens.

There is also a branded monthly report, a leadership dashboard, smart insights,
and WhatsApp/email sharing, plus `copyEOD(period)` for end-of-day summaries
(daily and weekly, cut at business-local midnight).

---

## 10. Service worker

`sw.js` has **no `fetch` handler by design.** It claims clients and deletes every
cache left by older versions. Cache-first and stale-while-revalidate both caused
the UI to load stale builds after a deploy. The app is online-only, so offline
support isn't worth the stale-content risk.

If you reintroduce caching, you own the cache-busting problem.

---

## 11. Known architectural debt

- **Migrations are incomplete.** The audit-log schema lives only in the live
  database, not in `scripts/migrations/`. The repo cannot rebuild the backend.
- **`tailwind.build.css` is unmanaged.** A static, hand-patched artifact with no
  source config. Classes not already present silently do nothing.
- **Names are not consistently escaped.** Several `onclick="fn('name')"`
  attributes escape only single quotes, so a name containing `"` or `<` breaks
  out. Writing names requires leader access, which limits but does not remove it.
- **No tests.** Verification is manual, done in a browser against production.
- **Dead code has been mistaken for cruft before.** `parkStaleTasks()` and
  `importTasks()` were fully implemented with no UI caller for a long time. If you
  find a function with no `onclick` anywhere, check whether it is a real feature
  missing a button before deleting it.
