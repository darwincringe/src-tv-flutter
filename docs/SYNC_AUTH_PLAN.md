# Plan — Accounts + Library + cross-device sync (NoSQL)

Goal: log in on any device, resume what you were watching, keep a personal
**Library**, and have "watched" status shared everywhere. Devices stay
local-first and sync in the background. Database is **MongoDB (NoSQL)**.

## What already exists

- **Backend:** `vidsrc-scraper` (`/var/www/vidsrc-scraper`, Express 5, ESM) —
  stateless: `/extract`, `/hls-proxy`, subtitles. No auth/users/DB yet. Runs on
  WSL2 (dev) and the droplet `165.22.111.114:4000` (prod).
- **App:** `WatchProgress` (`lib/data/store/watch_progress.dart`) — one record
  per title keyed `type-tmdbId`; already has `updatedAt` (→ last-write-wins) and
  `completed` (→ watched). Local via `shared_preferences`; a `revision`
  ValueNotifier drives UI refresh.
- **App API client:** `StreamClient` (dio), `baseUrl = http://165.22.111.114:4000/`.
- **App UI:** login/register form already built in `settings_screen.dart`
  (`_AuthMode.login|register`) — currently a no-op. Continue Watching row +
  `CategoryRow` "See More" pager already exist.

## ⚠️ Prerequisites (blockers)

1. **HTTPS** — API is plain HTTP; passwords/tokens must not go cleartext. Put it
   behind a domain + Caddy (auto Let's Encrypt) or Cloudflare, then switch the
   app `baseUrl` to `https://…`. (Waiting on your domain.)
2. **A DB host with real RAM** — see "Where it runs": the 1 GB droplet is full
   (~130 MB free, already swapping) and **cannot** also run MongoDB.

## Accounts

Register/login require **username + email + password**.
- `username`: unique, display name.
- `email`: unique, for login + recovery.
- `password`: bcrypt/argon2 hashed.
Login accepts email (or username) + password → returns a JWT. The app's existing
Settings form gets a third field (username) and is wired to these endpoints.

## Database — MongoDB (NoSQL)

NoSQL fits: everything is per-user documents, no joins. Collections:

**`users`**
```
{ _id, username (unique), email (unique), passwordHash, createdAt }
```

**`watch_progress`** — one doc per user+title (matches the app's keying)
```
{ userId, mediaType: 'movie'|'tv', tmdbId,
  season, episode, positionMs, durationMs, completed,
  title, posterPath, updatedAt (epoch ms) }
```
Unique compound index `{ userId:1, mediaType:1, tmdbId:1 }`; secondary index
`{ userId:1, updatedAt:-1 }` for Continue Watching / delta pulls.
LWW upsert: `updateOne(filter, {$set:doc}, {upsert:true})` guarded so a write
only applies when `incoming.updatedAt >= stored.updatedAt`.

**`library`** — titles the user saved to their Library
```
{ userId, mediaType, tmdbId, title, posterPath,
  addedAt (epoch ms), lastWatchedAt (epoch ms) }
```
Unique `{ userId:1, mediaType:1, tmdbId:1 }`; index `{ userId:1, lastWatchedAt:-1 }`.
`lastWatchedAt` is updated from watch-progress saves so the Library can sort by
most-recently-watched.

## API (add to the scraper; all under HTTPS, JWT-protected except /auth)

Auth: `POST /auth/register {username,email,password}`,
`POST /auth/login {emailOrUsername,password}` → `{token, user}`.

Sync (Bearer JWT):
- `GET  /progress?since=<ms>` → progress docs with `updatedAt > since`.
- `PUT  /progress {record}` → LWW upsert.
- `POST /progress/batch {records:[…]}` → bulk LWW upsert (initial push / queue).
- `DELETE /progress/:mediaType/:tmdbId`.

Library (Bearer JWT):
- `GET    /library` → user's library, sorted `lastWatchedAt` desc.
- `POST   /library {mediaType,tmdbId,title,posterPath}` → add (upsert).
- `DELETE /library/:mediaType/:tmdbId` → remove.

Harden: JWT middleware, tighten the open `cors()`, rate-limit `/auth/*`.

## App changes (Flutter)

1. **AuthService** — register/login; store JWT in `flutter_secure_storage` (new
   dep); expose `isSignedIn`, `token`, `signOut()`. Add the username field to
   the existing Settings form and wire it up.
2. **SyncService** over `WatchProgressStore` (local stays the offline cache):
   - Push on save (debounced) → `PUT /progress`; on failure queue to a
     persistent pending list and retry.
   - Pull on start / resume / login → `GET /progress?since=lastSyncMs`, merge
     **LWW**, flush queue, bump `revision`.
   - On first login: `POST /progress/batch` all local records, then pull.
3. **Library feature (signed-in only):**
   - `LibraryService` + local cache; add/remove calls the `/library` API and
     also updates the local cache + `revision`.
   - Details screen: an "Add to Library" / "In Library" toggle button.
   - A **Library** section/tab listing saved titles **sorted by last watched**
     (`lastWatchedAt` desc). Hidden/empty when signed out.
4. **Continue Watching — seamless lazy load (replace the "More" button):**
   - Load the first 10; when focus/scroll reaches the end of the loaded items,
     auto-append the next 10 (infinite scroll), repeating until exhausted.
   - Implement via the row's scroll/focus reaching the last tile → fetch next
     page (`GET /progress?...&limit=10&offset=N`, or page the local+synced
     list). Show a small trailing spinner tile while the next page loads.
   - Works the same signed-out (pages the local list) and signed-in (pages the
     synced list).

## Conflict resolution & edge cases

- **LWW by `updatedAt`** everywhere (already on the model). No merge UI.
- **Deletes:** a hard delete gets re-created by a pull from another device — use
  soft-delete (a `deleted` flag + `updatedAt`) if deletes must propagate; v1 can
  skip syncing deletes.
- **TV text entry** is painful on a remote → v1 type once (token persists);
  fast-follow: phone→TV device-pairing code.

## Where it runs (RAM-driven)

- The **1 GB droplet is full** (130 MB free, swapping) — the video proxy already
  needs it. **Do not** put MongoDB there. Options:
  - **A) Resize the droplet to ≥2 GB** (you do it in the DO panel; then I install
    Mongo there) — simplest for a single-box prod.
  - **B) DO Managed MongoDB** (separate, backups, ~$15/mo) — best for prod.
  - **C) Dev now in WSL2:** install Mongo in your WSL2 (home) so you can develop
    and make changes locally *today* without risking the stream box; move to A/B
    for production later.
- **Local access to the DB:** never expose the Mongo port to the internet
  (exposed Mongo gets ransomed by bots). For a droplet/remote DB, use an **SSH
  tunnel** (`ssh -L 27017:localhost:27017 …`) → connect Compass to
  `localhost:27017`. WSL2 Mongo is already local (no tunnel needed).
- Nightly `mongodump` backups once it holds real user data.

## Rollout order

1. Pick a DB host (A/B/C above) → I install + secure MongoDB there.
2. HTTPS on the API (needs your domain).
3. Add `/auth`, `/progress`, `/library` to the scraper; test with curl.
4. App: AuthService + wire the (username/email/password) login form.
5. App: SyncService (push/pull/offline queue) + Continue-Watching lazy load.
6. App: Library UI (add/remove + last-watched-sorted list).
7. Cross-device verify; add `mongodump` backups; (later) TV pairing.

## New dependencies

- Backend: `mongodb` (driver), `bcrypt`/`argon2`, `jsonwebtoken`,
  `express-rate-limit`; Caddy for TLS.
- App: `flutter_secure_storage`. dio + shared_preferences already present.
