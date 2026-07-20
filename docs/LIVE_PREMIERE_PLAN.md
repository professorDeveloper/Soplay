# Jonli Premyera — synchronized live watch events (design)

A scheduled, **server-clock-synchronized** public watch event: everyone watches
the same film at the same second, with live chat + floating reactions. Promoted
on Telegram with a countdown → **FOMO acquisition spikes** ("premiere at 8pm,
join to watch together"). An acquisition magnet, not just retention.

Status: DESIGN. Built directly on the existing **watch-party** infra
(`src/socket/watchPartyGateway.js`, `models/WatchParty.js`, socket.io) and the
device-side stream-resolution model.

---

## 1. Sync model — the heart

- **Server clock is authoritative.** A premiere has a `startAt`. The live
  position = `serverNow − startAt` (clamped to `[0, duration]`). Every viewer
  seeks to it and follows; late joiners jump straight to "live".
- **Admin can override** live (play / pause / seek / skip-intro). An override
  writes a new `{ positionSec, isPlaying, updatedAt }` anchor; clients recompute
  position from that anchor + elapsed time. This reuses watch-party's existing
  `playback` broadcast — the "host" is just replaced by *the schedule + an
  admin*, instead of a random user.
- Clients periodically re-sync (drift correction) to `anchor.position +
  (now − anchor.updatedAt) × rate` when playing.

## 2. Content / streams

- Reuse watch-party's rule: the premiere row stores **content identity only**
  (`provider, contentUrl, mediaRef, title, thumbnail`) — never a resolved
  stream URL (those are device/IP-bound).
- **Must be a server-resolvable provider (`vidapi`)** so *every* device — mobile,
  desktop, and brand-new users with no on-device plugins — resolves the same
  title. Each device calls the normal resolve path and seeks to live position.

## 3. Access — the acquisition hook

- **Public. Guests can watch** (no login) to maximise reach; login is required
  only to **chat / react**. This is deliberate: the barrier to *joining* must be
  zero so a shared link converts.
- Shareable link → **`sozo.azamov.me/premiere/<code>`** web page: poster +
  **countdown** + "Watch in Sozo" (deep link) / "Install to join". If live,
  shows viewer count for social proof.
- Push notification ("Premyera 10 daqiqada boshlanadi") + Telegram announcement.

## 4. Backend (`soplay-backend`)

### Model `Premiere` (or extend WatchParty with `kind:'premiere'`)
```
{ code, title, content:{provider,contentUrl,mediaRef,title,thumbnail,type},
  startAt, durationSec, status:'scheduled'|'live'|'ended',
  playbackAnchor:{ positionSec, isPlaying, rate, updatedAt },  // admin overrides
  stats:{ peakViewers, totalJoins },
  chat:{ enabled, slowModeSec }, createdBy }
```

### Socket (extend `watchPartyGateway.js`)
- A premiere is a big public room `premiere:<code>` (no 2-member cap).
- Events: `premiere:join` → snapshot (anchor, viewers, recent chat);
  `premiere:sync` (periodic anchor rebroadcast); `premiere:chat`;
  `premiere:react` (emoji, fire-and-forget, **sampled/aggregated** so a firehose
  of hearts doesn't melt the socket); `premiere:presence` (throttled count);
  admin-only `premiere:control` (play/pause/seek).
- **Scale:** presence as a periodic count (not per-user events); chat with
  **slow-mode + rate-limit + banned-words + report**; reactions aggregated
  server-side into counts emitted every ~1s.

### REST
- `GET /premieres/upcoming|live`, `GET /premieres/:code` (for the web page).
- `POST /admin/premieres` (schedule), `PATCH` (edit), admin live-control also via
  socket.
- On `startAt`, a job flips `status:'live'` and fires the push/Telegram announce.

### Admin
- `/admin/premieres`: schedule (title, pick content, time, poster), and a **live
  control panel** (play/pause/seek/skip-intro, viewer count, chat moderation:
  pin/delete/ban, toggle slow-mode).

## 5. Web countdown page (`sozo.azamov.me`)
- Static page reading `GET /premieres/:code`: poster, countdown, deep link,
  install CTA, live viewer count. This is the shareable acquisition surface.

## 6. Client (`lib/features/premiere`)

Screens:
1. **Premieres tab / home banner** — upcoming + live, countdown, "Set reminder".
2. **Countdown / lobby** — poster, timer, live viewer count, "share".
3. **Live player** — reuse the player; position driven by the socket anchor
   (seek to live, follow, drift-correct); **can't scrub past live**. Overlays:
   live chat, floating reactions, viewer count, "share".
- Reminder → local notification at `startAt − 10m`.

## 7. Scale & failure notes
- Stream is per-device (each resolves its own HLS via vidapi) — no central
  restream, so viewer count is bounded by the provider CDN, not our server.
- Our server only carries: socket presence, chat, reactions, anchor sync — all
  cheap and aggregatable. Chat is the main load → slow-mode + rate-limit.
- If a viewer's resolve fails, they see a retry (doesn't affect others).

## 8. Phases
1. **MVP:** admin schedules a premiere; server-clock sync + admin play/pause/seek;
   public guest viewing; live viewer count; basic chat (slow-mode). Reuse
   watch-party socket + player.
2. **V2:** web countdown page + deep link + push + Telegram announce; floating
   reactions; reminders.
3. **V3:** chat moderation tools, recurring "premiere nights", post-premiere
   Kino Billar round, analytics (peak viewers, install attribution).
