# LIVE PREMIERE — Complete File-Level Architecture (3 repos)

Grounded entirely in the four studies. Design is locked: server-clock authoritative timeline with admin-override anchor, identity-only content, public+guest, scalable tick-based fan-out, separate bottom-nav tab, reuse watch-party infra.

The single load-bearing primitive throughout: **one throttled per-room "tick" frame replaces all per-event fan-out**, and **a counter replaces the roster**. Everything below preserves the existing invariants (identity-only content, try/catch-guarded handlers, per-socket token buckets, bounded in-memory maps).

---

## PART 0 — Shared contracts (the spine both ends implement)

**The clock.** `position = (serverNow − anchor.startAtEpochMs)/1000 × rate + anchor.startPositionSec`, valid only when `anchor.isPlaying`. When paused, `position = anchor.startPositionSec`. `startAtEpochMs` is fixed wall-clock (unlike watch-party's transient `anchorTs`). This replaces the app's `receivedAt`-relative math (§app gap 1).

**Clock-offset handshake** (new, NTP-style): client emits `premiere:ping{t0}`, server replies `premiere:pong{t0, serverTime}`; client computes `offset = serverTime + rtt/2 − now`. `serverNowEstimate = Date.now() + offset`. Run 3× on join, keep the median; refresh from every `tick.serverTime`.

**Anchor** = `{ startAtEpochMs, startPositionSec, rate, isPlaying, contentRef }`. `contentRef` is identity-only (provider, contentUrl, mediaRef, title, thumbnail, type, lang, season, episode) — **never a stream URL** (reuses `sanitizeContent`).

**Statuses:** `scheduled → live → paused(live substate) → ended` (+ `canceled`).

---

## PART 1 — BACKEND (`soplay-backend`)

Separate `/premiere` namespace (keeps `watchPartyGateway.js` untouched — the study's recommended clean path). Separate `Premiere` model (roster-free shape).

### 1.1 Files to ADD

```
src/models/Premiere.js
src/services/premiere/premiereManager.js        // pure in-memory live-state (no socket/mongo)
src/services/premiere/premiereService.js         // mongo persistence + sanitizeContent reuse
src/socket/premiereGateway.js                    // /premiere nsp handlers + per-room tick loop
src/controllers/premiereController.js            // public REST
src/controllers/admin/premiere.controller.js     // admin CRUD + live control
src/routes/premiere.js                           // public router
src/routes/admin/premiere.js                     // admin router
scripts/generatePremiere.js                      // optional seed helper (mirrors generateShorts.js)
```

### 1.2 Files to EDIT

```
src/socket/index.js                 // registerPremiereGateway(io) on new /premiere nsp; (optional) redis adapter
src/models/WatchPartyConfig.js      // add premiere knobs
<app router index>                  // mount routes/premiere.js + routes/admin/premiere.js where watchParty routers mount
src/services/watchParty/watchPartyService.js   // export sanitizeContent for reuse (or import from shared util)
```

### 1.3 `src/models/Premiere.js`

```js
{
  title, description, posterUrl, posterKey,            // R2 poster (reuse r2.service upload-url flow)
  contentRef: {                                        // identity-only, sanitized on write
    provider, contentUrl, mediaRef, type,              // 'movie'|'tv'
    lang, season, episode, contentTitle, contentThumbnail
  },
  scheduledStartEpochMs: Number,                       // planned start (countdown target)
  anchor: {                                            // live timeline; null until first go-live
    startAtEpochMs, startPositionSec: {default:0},
    rate: {default:1}, isPlaying: {default:false}
  },
  status: {enum:['scheduled','live','ended','canceled'], default:'scheduled', index:true},
  code: {unique, index},                               // normCode ^[A-Z0-9]{4,12}$ — socket room key, reuse normCode
  chatSlowModeSec: {default: 8},
  premiereHardCap: {default: 100000},
  reactionsEnabled:{default:true}, chatEnabled:{default:true},
  peakViewers: {default:0},                            // updated from tick sampling
  telegram: { channelMsgId, announced:Bool },
  audit: [{ adminId, action, at, meta }],              // override/pause/seek/close log
  createdBy: {ref:'Admin', required:true}
}
// indexes: {status:1, scheduledStartEpochMs:1}, {code:1}
```
Cold store only. Live truth is `premiereManager`. Content is written through `sanitizeContent` (never a URL). Poster upload reuses the exact `/upload-url` presigned-R2 pattern from Shorts.

### 1.4 `src/services/premiere/premiereManager.js` (pure, `now`-injectable — mirrors `roomManager.js`)

Module-level `Map<code, PremiereRoom>`. No socket/mongo imports. `PremiereRoom`:

```
{ code, status, anchor,
  presenceCount: int,                 // ++ on join, -- on disconnect (NOT a roster)
  reactionAcc: Map<emoji,count>,      // accumulate; reset each tick
  chatBuffer: [{userId,username,photoURL,text,ts,clientId}],   // cap 20, drop oldest
  slowMap: Map<userId,lastTs>,        // bounded; slow-mode cooldown (mirror _inviteCooldown pattern)
  tickTimer, closeTimer,
  peakViewers }
```

Exposes pure helpers:
- `effectivePosition(room, now)` — reuses existing drift math anchored to `startAtEpochMs`.
- `playbackView(room, now)` → `{positionSec, isPlaying, rate, serverTime: now}`.
- `applyAnchor(room, {startPositionSec,isPlaying,rate}, now)` — sets `startAtEpochMs=now`, recomputes anchor (this is the admin override; play/pause/seek/reschedule all funnel here).
- `pushChat(room, msg, now, slowSec)` → bool (false if within cooldown → silently dropped; matches existing flood behavior).
- `addReaction(room, emoji)`, `drainReactions(room)`, `drainChat(room)`.
- `canJoin(room)` → `presenceCount < premiereHardCap` (NO maxMembers — study §6a).

### 1.5 `src/socket/premiereGateway.js`

Registered on `nsp = io.of('/premiere')` with the **same JWT middleware pattern** as `/watch` — but auth is **optional** (public guest viewing). Middleware:
- If `handshake.auth.token` present → `verifyAccess` → `socket.data.user = {id,username,photoURL}`.
- If absent/invalid → `socket.data.user = null` (guest). **Do not reject.** Guests may join + receive ticks; they cannot chat/react (enforced per-event).

Per-socket token buckets (reuse pattern): `premiereJoin`, `premiereChat` (tight), `premiereReaction`.

**Inbound events** (all try/catch-guarded, all bucketed):

| Event | Payload | Auth | Action |
|---|---|---|---|
| `premiere:join` | `{code}` | guest ok | `socket.join(code)`; `presenceCount++`; start tick if first; reply `premiere:state` (status + anchor + serverTime + config) |
| `premiere:leave` | `{code}` | guest ok | leave, `presenceCount--`, schedule close if drained |
| `premiere:ping` | `{code,t0}` | guest ok | reply `premiere:pong{t0, serverTime: Date.now()}` |
| `premiere:chat` | `{code,text,clientId}` | **login required** | slow-mode check → `pushChat`; drop silently if cooldown or guest |
| `premiere:reaction` | `{code,emoji}` | **login required** | `addReaction` (accumulate only; NOT fanned out) |
| `disconnect` | — | — | for each joined code: `presenceCount--`, schedule close |

**Outbound events:**

| Event | Payload | When |
|---|---|---|
| `premiere:state` | `{status, anchor, playback, serverTime, presence, config:{chatSlowModeSec,chatEnabled,reactionsEnabled}}` | on join / cold-load |
| `premiere:tick` | `{playback:{positionSec,serverTime,isPlaying,rate}, presence, reactions:{'❤️':1200,...}, chat:[...≤20], status}` | every `tickIntervalMs` (1–2s) |
| `premiere:anchor` | `{anchor, playback, serverTime}` | immediately on admin override (don't wait for tick) |
| `premiere:status` | `{status}` | go-live / pause / end |
| `premiere:closed` | `{reason}` | force-close / end |
| `premiere:error` | `{message}` | join failures only |

**The tick loop** — one `setInterval(tickIntervalMs)` **per active room**:
```
const room = mgr.get(code);
const presence = nsp.adapter.rooms.get(code)?.size ?? room.presenceCount;  // socket.io's own count, sampled
room.peakViewers = max(room.peakViewers, presence);
nsp.to(code).emit('premiere:tick', {
  playback: mgr.playbackView(room, Date.now()),
  presence,
  reactions: mgr.drainReactions(room),   // reset accumulator
  chat: mgr.drainChat(room),             // flush buffer
  status: room.status
});
```
Egress = `O(rooms × socketsPerRoom)` at fixed cadence — bounded regardless of inbound volume. Clear the interval + persist `peakViewers` when the room drains (reuse `EMPTY_GRACE_MS` grace).

Gateway exposes `emitAnchor(code, anchor)`, `emitStatus(code, status)`, `emitClosed(code, reason)`, `getPresence(code)` — called by the admin controller (mirrors `gateway.emitClosed`).

### 1.6 Public REST — `routes/premiere.js` + `premiereController.js`

```
GET  /api/premieres              → upcoming+live list [{id,title,poster,scheduledStartEpochMs,status,code}]
GET  /api/premieres/:id          → detail + join info {code, status, anchor, serverTime, contentRef, config}
GET  /api/premieres/:code/live   → lightweight poll fallback {status, anchor, serverTime, presence}
```
`:id/detail` returns `serverTime: Date.now()` so an HTTP-only client can bootstrap the countdown even before websocket. No create/join-by-code (public event; code is discovered via list/detail).

### 1.7 Admin REST — `routes/admin/premiere.js` + `admin/premiere.controller.js`

All behind `adminAuth` + timeout + token buckets (reuse Shorts wiring).

```
GET    /admin/premieres?page=&limit=20&status=       list {items,total,totalPages}
GET    /admin/premieres/:id                          getOne
POST   /admin/premieres/resolve-content?url=         reuse detectProvider/getDetail/normalizeDetail (verbatim from shorts.controller)
POST   /admin/premieres/upload-url {type,contentType} presigned R2 (poster)
POST   /admin/premieres           create (schedule)  → generates code, status=scheduled, sanitizeContent(contentRef)
PUT    /admin/premieres/:id        edit metadata/schedule
DELETE /admin/premieres/:id        cancel/delete → gateway.emitClosed

// LIVE CONTROL (drives premiereManager + broadcasts immediately):
POST   /admin/premieres/:id/go-live  {startPositionSec?}  status=live, applyAnchor(isPlaying:true), emitStatus+emitAnchor
POST   /admin/premieres/:id/pause                          applyAnchor(isPlaying:false), emitAnchor
POST   /admin/premieres/:id/resume                         applyAnchor(isPlaying:true), emitAnchor
POST   /admin/premieres/:id/seek     {positionSec}         applyAnchor(startPositionSec=positionSec), emitAnchor
POST   /admin/premieres/:id/rate     {rate}                applyAnchor(rate), emitAnchor
POST   /admin/premieres/:id/end                            status=ended, emitStatus+emitClosed
PUT    /admin/premieres/:id/slow-mode {chatSlowModeSec}    update + push into room config
GET    /admin/premieres/:id/stream?token=                 SSE: viewer count + recent chat (moderation) + status
DELETE /admin/premieres/:id/chat/:msgId                    (optional) moderation — evict from buffer
```
Every control action appends to `audit[]`, persists anchor to Mongo (throttled 15s, forced on pause/seek/end like `PLAYBACK_PERSIST_MS`), and calls the gateway to broadcast **one** `premiere:anchor`. Late joiners get the anchor in `premiere:state` and compute their own position — zero per-viewer sync traffic.

The SSE endpoint mirrors `NotificationsContext` server side (token as query param, `text/event-stream`, 5s reconnect tolerance) — it feeds the admin LIVE panel's viewer count + moderated chat tail. Not socket.io (admin app has no socket client).

### 1.8 `WatchPartyConfig.js` additions
`premiereEnabled`, `premiereHardCap` (100000), `chatSlowModeSec` (8), `tickIntervalMs` (1500), `reactionWindowMs` (=tick), `chatBufferSize` (20).

### 1.9 Scale plan (summary)
1. **Presence**: integer counter + `nsp.adapter.rooms.get(code)?.size` sampled on tick. No Set of ids, no roster event.
2. **Chat**: per-user slow-mode cooldown (`slowMap`, bounded, drop-silent) + buffer flushed on tick capped at 20 → egress bounded.
3. **Reactions**: accumulate to `Map<emoji,count>`, emit one frame/tick, reset. Arbitrary inbound → one small fixed frame.
4. **Playback**: admin override emits **once**; timeline is math, not traffic.
5. **Multi-node (HA, later)**: only `src/socket/index.js` changes — add `@socket.io/redis-adapter`; move `presenceCount`/accumulators to Redis (`INCR`/hash), one elected node emits the tick. Everything else premiere-specific is unchanged.

### 1.10 Prod seed/read (Docker Mongo, per be_content study)
- Content resolution reuses `vidapi.resolveMedia` — but premieres store **identity only**; no ffmpeg/R2 clip needed (unlike Shorts). Only the poster hits R2.
- Admins create premieres through the **admin API against prod** (apisozo.azamov.me/api), which writes to the Docker Mongo directly — no local seeding gotcha.
- `scripts/generatePremiere.js` (optional) mirrors `generateShorts.js` for bulk-scheduling test premieres; **must run on the server** (`docker compose exec app node scripts/generatePremiere.js`) because port 27017 isn't exposed — same constraint as Shorts seeding. Deploy path unchanged (push `clean-master` → SSH → rebuild `app`).

---

## PART 2 — APP (`soplay`) — feature module `lib/features/premiere/`

Follows the Clean-Architecture template exactly. A **parallel `PremiereService`** mirroring `WatchPartyService`'s ValueNotifier+broadcast-stream shape, but **receive-only for playback** (server is the clock). Reuse the socket wrapper, identity+on-device resolve chain, reactions overlay, chat panel, and `PlayerController` verbatim.

### 2.1 Files to ADD

```
domain/entities/premiere_entity.dart            // Equatable: id,title,poster,scheduledStartEpochMs,status,code,contentRef
domain/entities/premiere_anchor.dart            // startAtEpochMs,startPositionSec,rate,isPlaying + livePositionAt(serverNow)
domain/entities/premiere_content.dart           // reuse PartyContent shape (identity-only)
domain/entities/premiere_feed_result.dart
domain/repositories/premiere_repository.dart    // Future<Result<...>>
domain/usecases/get_premieres_usecase.dart
domain/usecases/get_premiere_detail_usecase.dart
data/models/premiere_model.dart                 // .fromJson + _str/_int/_bool
data/models/premiere_anchor_model.dart
data/datasources/premiere_remote_data_source.dart   // dio: getIt<Dio>(); GET /premieres, /premieres/:id
data/repositories/premiere_repository_impl.dart

// realtime (NOT bloc — mirrors WatchPartyService, a live controller):
data/premiere_socket_client.dart                // thin subclass/copy of WatchPartySocketClient, namespace /premiere, guest-capable
data/premiere_service.dart                      // ValueNotifier<PremiereRoomState> + broadcast streams (chat/reactions/anchor)
domain/premiere_clock.dart                      // NTP offset handshake: ping/pong → serverNowEstimate

presentation/bloc/premiere_list_bloc.dart|_event|_state.dart   // the TAB list (Initial/Loading/Loaded/Error)
presentation/pages/premieres_tab_page.dart      // bottom-nav tab: upcoming + live rails
presentation/pages/premiere_lobby_page.dart     // countdown-before-start + join-mid-stream
presentation/pages/premiere_live_page.dart      // player + chat + reactions (host-less)
presentation/widgets/premiere_countdown.dart
presentation/widgets/premiere_card.dart
presentation/widgets/premiere_presence_pill.dart   // live viewer count
presentation/widgets/premiere_chat_panel.dart      // reuse party_chat_panel styling
presentation/widgets/premiere_reactions_overlay.dart // reuse PartyReactionsOverlay
presentation/premiere_sync_controller.dart      // seek-to-live + drift + rate-nudge, premiere-mode gating
```

### 2.2 Files to EDIT

```
lib/core/di/injection.dart                              // register datasource→repo→usecases→list bloc; PremiereService as lazySingleton
lib/core/router/app_router.dart                         // GoRoute /premiere/:code (lobby) + /premiere/:code/live; deeplink via queryParameters
lib/features/main/presentation/pages/main_page.dart     // add Premieres as a bottom-nav TAB (BlocProvider(getIt<PremiereListBloc>()..add(Load)))
lib/core/constants/app_constants.dart                   // (if needed) premiere path consts
```

### 2.3 The sync client — `premiere_sync_controller.dart` (the real new behavior; app gaps 1–3,6)

Everyone is a guest of a virtual host; playback is **receive-only**.
- **Clock authority**: uses `PremiereClock.serverNowEstimate` (offset handshake), NOT `receivedAt`. `livePosition = anchor.livePositionAt(serverNowEstimate)`.
- **Premiere-mode gating** (replaces `_isLive` suppression): a VOD premiere has finite duration but must behave like live → new `_premiereMode` flag **allows programmatic seek-to-live, forbids user scrubbing**. `canControl` forced `false`; all control emits removed; `_partyBlockLocal()` always true; episode-nav locked.
- **Seek-to-live**: on join and on drift timer (2s cadence, reuse), target `anchor.livePositionAt(now)`:
  - drift > 4s → hard `seekTo` (large gap / just joined).
  - 0.5s–4s → **rate-nudge** ±5% via existing `setPlaybackSpeed` to absorb without visible jump (app gap 6 — plumbing exists, policy new), then restore rate.
  - < 0.5s → leave.
- **Anchor apply**: on `premiere:anchor` / `premiere:tick`, update anchor; play/pause **only on actual state mismatch** (reuse the anti-thrash rule); if `!isPlaying` → pause and hold at `startPositionSec`.
- **Content resolve**: identical to watch-party — `PartyResolveGate.canResolve(provider)`, `cs:`/`an:` plugin gate, `ResolveMediaUseCase`, `PartyPluginRequiredView`. Each device resolves its own stream (never a URL over the wire).

### 2.4 Screens
- **`premieres_tab_page.dart`**: bottom-nav tab. LIVE rail (status=live, red "LIVE" badge + presence pill) + Upcoming rail (countdown chips). Card tap → lobby.
- **`premiere_lobby_page.dart`**: if `scheduled` → big `PremiereCountdown` to `scheduledStartEpochMs`, share button (deep link), "Notify me" (push opt-in). On `status→live` (via socket or poll) → auto-navigate to live, seeking to live edge. Handles plugin-required + connecting/retry/closed UX (reuse `party_error_views.dart`).
- **`premiere_live_page.dart`**: `PlayerController` video (reused), `PremiereReactionsOverlay` (login-gated picker), `PremiereChatPanel` (login-gated composer, slow-mode countdown on send button), `PremierePresencePill`. Guest sees video+chat read-only with a "Login to chat" affordance.

### 2.5 Guest mode
Socket connects **without token** when logged out (client passes `token:null` in handshake; server treats as guest). Guests receive `premiere:state`/`tick`, render video+chat+counts. Chat/react buttons route to login. On login → token refresh → reconnect handshake (reuse the handler-reattach reconnect pattern) upgrades to full participant.

### 2.6 DI + router wiring
- injection.dart: `registerSingleton` datasource/repo/usecases; `registerLazySingleton<PremiereService>` (app-wide live controller); `registerFactory(() => PremiereListBloc(...))`.
- app_router.dart: `GoRoute('/premiere/:code')` → lobby (reads `state.pathParameters['code']`, supports deeplink), `GoRoute('/premiere/:code/live')` → live page.
- main_page.dart: insert Premieres tab into the bottom nav bar array + PageView.

### 2.7 Shareable countdown deep link + push + Telegram
- Deep link: `soplay://premiere/<code>` and `https://sozo.azamov.me/premiere/<code>` → router `/premiere/:code`.
- Push: backend fires FCM on go-live to opted-in users (reuse existing notifications infra); tap → deeplink.
- Telegram: backend posts the countdown/go-live to the channel (`telegram.channelMsgId`), link → web countdown page (Part 4).

---

## PART 3 — ADMIN-WEB (`soplay-admin-web`)

Three edits + two pages, matching Shorts.jsx / WatchParty.jsx.

### 3.1 Files to ADD
```
src/pages/Premieres.jsx        // list + schedule CRUD (Shorts skeleton: table + AddPremiereModal)
src/pages/PremiereLive.jsx     // LIVE CONTROL panel (WatchParty.jsx + NotificationsContext SSE skeleton)
```
### 3.2 Files to EDIT
```
src/App.jsx                    // import + <Route path="premieres" .../> and <Route path="premieres/:id/live" .../>
src/components/Layout.jsx      // nav item { to:'/premieres', label:'Premyeralar', icon:<svg/> } + LIVE badge (copy unseenCount badge branch, driven by live-count)
```

### 3.3 `Premieres.jsx` (schedule CRUD)
Copy `Shorts.jsx` shape. `data={items,total,totalPages}`, `page`, `useCallback` fetch `GET /admin/premieres?page=&limit=20&status=`. **AddPremiereModal**:
- `POST /admin/premieres/resolve-content?url=` → auto-fills provider/title/thumbnail.
- Poster: `POST /admin/premieres/upload-url {type:'poster',contentType}` → `uploadToR2(url,file,setProgress)` → `posterKey`.
- Schedule: `<input type="datetime-local">` via `toLocalInput`/`fromLocalInput` (lift from Banners) → `scheduledStartEpochMs`.
- `chatSlowModeSec`, `premiereHardCap` fields.
- Submit → `POST /admin/premieres` (or `PUT` on edit).
- Row actions: Edit, Delete (`DELETE /admin/premieres/:id`), and **"Boshqarish" (Control)** → navigate `/premieres/:id/live`.

### 3.4 `PremiereLive.jsx` (LIVE CONTROL panel)
Closest precedent WatchParty.jsx (config + live list). Layout:
- **State header**: status pill, live **viewer count**, peak — fed by SSE `GET /admin/premieres/:id/stream?token=` (EventSource, token as query param, 5s reconnect — copy NotificationsContext skeleton).
- **Transport controls** → plain `api.post`:
  - Go Live → `POST /admin/premieres/:id/go-live`
  - Pause / Resume → `.../pause` `.../resume`
  - Seek: numeric position input → `POST .../seek {positionSec}` (also a "+30s / −10s" jog)
  - Rate select → `POST .../rate {rate}`
  - End → `POST .../end` (confirm)
- **Slow-mode**: number input → `PUT .../slow-mode {chatSlowModeSec}`.
- **Chat moderation**: live chat tail from the SSE stream; per-message delete → `DELETE .../chat/:msgId`.
- **Audit trail**: render `audit[]` from `GET /admin/premieres/:id`.

All auto-authenticated by the axios `Authorization: Bearer` interceptor — no per-page auth code.

---

## PART 4 — WEB COUNTDOWN PAGE (`sozo-web` landing site)

Static site at sozo.azamov.me (Pages branch-serving from master, push from Webstorm `prof` remote — per memory). Add:

```
/premiere/index.html    (or /premiere/[code] via a small JS router on a single premiere.html)
premiere.js
premiere.css
```
- Reads `code` from URL path/query → `GET https://apisozo.azamov.me/api/premieres/:code/live` → `{status, scheduledStartEpochMs, serverTime, presence, title, poster}`.
- Renders poster + **live countdown** (client uses returned `serverTime` to correct local clock skew, same offset trick, HTTP-only).
- Two CTAs: **Open in app** (`soplay://premiere/<code>`, fallback to store) + **Watch on web** (if a web player exists; otherwise app-only).
- When `status=live` → swap countdown for "LIVE NOW — open app". Brand red `#ad4343`.
- This is the Telegram/share landing target.

---

## PART 5 — PHASED BUILD ORDER (MVP first)

**Phase 0 — Contracts.** Lock the anchor math + event names (Part 0). Add `Premiere.js` model + `WatchPartyConfig` knobs. No behavior yet.

**Phase 1 — MVP backend (single-node, no chat/reactions).**
- `premiereManager.js` (anchor + presence counter + tick), `premiereGateway.js` on `/premiere` nsp (join/leave/ping/tick, anchor broadcast), `premiereService.js` persistence.
- Public REST (list/detail/live), admin REST (CRUD + go-live/pause/seek/end).
- Verify: create → go-live → position math correct → pause/seek reflected in tick.

**Phase 2 — MVP app tab + player sync (receive-only).**
- Feature module (entities/model/datasource/repo/usecases/list bloc), Premieres tab in main_page, lobby countdown, live page with `PlayerController` + `premiere_sync_controller` (clock offset + seek-to-live + hard-seek drift only). Guest viewing works (no login).
- Reuse identity resolve chain + plugin gate verbatim.
- Verify end-to-end: schedule in admin → go-live → app device joins mid-stream → seeks to live edge → follows pause/seek.

**Phase 3 — MVP admin live control.** `Premieres.jsx` (CRUD + poster + schedule) and `PremiereLive.jsx` (transport controls, viewer count via SSE). Nav item + routes.

**Phase 4 — Chat + reactions at scale.**
- Backend: slow-mode `slowMap`, `chatBuffer` flushed on tick, `reactionAcc` aggregated frame. `premiereChat`/`premiereReaction` buckets. Login-required enforcement.
- App: `premiere_chat_panel` + `premiere_reactions_overlay` (reuse party widgets), login-gated composer, slow-mode countdown, aggregated floating-emoji burst sized to tick counts.
- Admin: chat moderation tail + slow-mode control in `PremiereLive.jsx`.

**Phase 5 — Distribution.** Web countdown page, shareable deep link (`/premiere/:code`), FCM push on go-live, Telegram announce. Rate-nudge drift refinement (±5% playbackSpeed).

**Phase 6 — HA (only when needed).** `@socket.io/redis-adapter` in `src/socket/index.js`; move presence/accumulators to Redis; elected tick emitter. Nothing else changes.

---

### Invariants preserved throughout
Identity-only content (never a stream URL, `sanitizeContent` reused) · all socket handlers try/catch-guarded · per-socket token buckets (+ new `premiereChat`/`premiereReaction`) · bounded in-memory maps (`slowMap`, `chatBuffer`, `reactionAcc`) · **single throttled per-room tick as the only fan-out** — the load-bearing scalability primitive · `watchPartyGateway.js` untouched (separate `/premiere` nsp) · app reuses socket wrapper, resolve chain, chat/reaction widgets, `PlayerController`; rebuilds only the clock authority, seek-to-live/premiere-mode gating, and countdown lobby.