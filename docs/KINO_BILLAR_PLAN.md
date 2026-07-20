# Kino Billar — movie/anime clip trivia (design)

A viral, in-app **acquisition magnet**: guess the movie/anime from a short clip,
ranked by speed. The film/anime version of the "guess the song from a snippet"
music game. Every round ends in a shareable result + a friend-challenge deep
link, so players pull new users in. No coin/ad economy required.

Status: DESIGN. Built on existing infra — `generateShorts` clip pipeline (R2),
TMDB (`src/utils/tmdb.js`), `share_plus` + deeplink, streak (habit).

---

## 1. Modes

### A. Klip Top (Guess) — core
- Show a short clip (title hidden) → pick the correct movie/anime from **4
  options** → next clip. Distractors are same-genre/era so it's non-trivial.
- Round = **10 clips**, **~15s timer** each. Score = correctness + **speed
  bonus** (faster answer → more points). A round is a **fixed clip set** so two
  players' scores are directly comparable (the challenge loop depends on this).
- After answering (or timeout): reveal the title + **"Watch full on Sozo"** →
  converts a player into a viewer (ties trivia back into watching).

### B. Fan Test (actor / character) — the shareable hook
- User picks a **favourite actor** (movies) or **anime character** → the round's
  10 clips/questions all come from that person's filmography / that character's
  appearances → result is a **fandom %** ("You're a 92% DiCaprio fan").
- Actor picker: TMDB `/person/popular` + `/search/person`; show top cast with
  photos. Clips/questions from `/person/{id}/movie_credits` (+ `combined`).
- Anime characters: TMDB is weak here → use **AniList (GraphQL) or Jikan (MAL)**
  for character → media mapping. Ship movies/actors first; anime-character second.
- Shareable result card: "%, top-3 titles you nailed, the one you missed" +
  challenge deep link.

Both modes share: the clip engine, the 10×15s round, scoring, share/challenge,
and the leaderboards.

---

## 2. Content & clip pipeline

- **Clips reuse the `generateShorts` pipeline** (`scripts/generateShorts.js`):
  vidapi HLS → ffmpeg cut → R2. For trivia we generate **dedicated clips**:
  - shorter (~6–10s), **no title/credits frames** (avoid dead giveaways — seek
    to mid-runtime, skip intro/outro, run a quick "has burned-in title" heuristic
    or just avoid first/last 12%),
  - store on R2 as `trivia/clips/<uuid>.mp4`, linked to `{tmdbId, type, title,
    year, genres, difficulty}`.
- **Server-resolvable only** (vidapi): so every device — incl. a brand-new user
  with no plugins — can play the same clip. Popular anime that resolve via
  TMDB/vidapi are in; niche Aniyomi-only anime are out (documented gap).
- **Difficulty tiers** (iconic → obscure) from TMDB `popularity`/`vote_count`.

---

## 3. Backend (`soplay-backend`)

Prod Mongo is the Docker container (`mongo:27017/soplay`) — reachable only via
the server/admin API, NOT the dev Atlas. Seed via the admin API, like shorts.

### Models
- `TriviaClip`: `{ videoKey, videoUrl, thumbnailUrl, tmdbId, mediaType,
  title, year, genres[], difficulty, source:'vidapi', createdBy }` (mirrors the
  Short model; generated the same way).
- `TriviaRound`: a materialised fixed set of 10 clips + their 4-option choices,
  so a challenger replays the **identical** round. `{ _id, mode, seedActorId?,
  clips:[{clipId, options:[titles], correctIdx}], createdAt, expiresAt }`.
- `TriviaScore`: `{ userId, roundId, mode, score, correct, totalMs, createdAt }`
  — one per play; drives leaderboards.
- `TriviaChallenge`: `{ roundId, fromUserId, code, createdAt }` — the shareable
  challenge.

### Endpoints (`/trivia/*`, user-auth optional for guest play)
- `POST /trivia/round` `{mode, actorId?}` → creates/returns a `TriviaRound`
  (10 clips + options). Options/distractors generated from TMDB (same
  genre/era; for Fan Test, co-stars / other films of the actor).
- `GET  /trivia/round/:id` → replay an exact round (for challenges).
- `POST /trivia/round/:id/submit` `{answers:[{clipId, choiceIdx, ms}]}` →
  **server-authoritative** scoring (never trust client score); returns score,
  correct answers, reveal metadata, rank.
- `GET  /trivia/leaderboard?scope=daily|weekly|all|friends` → ranked scores.
- `POST /trivia/challenge` `{roundId}` → `{code, url}` (deep link).
- `GET  /person/popular`, `/person/search` → thin TMDB proxies for the picker.

### Question generation
- Distractors from TMDB: same genre + close year + similar popularity → plausible
  but wrong. Optional LLM pass to phrase text questions ("Who directed…") later.
- Cache generated rounds (SWR) so a viral spike doesn't hammer TMDB.

### Leaderboards
- Mongo aggregation for MVP (index `{mode, createdAt}` + `{userId, score}`).
- If it grows: Redis sorted sets per `daily/weekly/all` window.

### Admin
- `/admin/trivia`: generate/curate clips (run the trivia variant of
  `generateShorts`), flag bad clips, set difficulty, ban/replace.

---

## 4. Client (`lib/features/trivia`)

Clean-arch feature module (bloc / usecase / repo / datasource), like `shorts`.

Screens:
1. **Home / mode select** — Klip Top · Fan Test · Daily · Leaderboard.
2. **Actor/character picker** (Fan Test) — TMDB top cast grid + search.
3. **Gameplay** — full-screen clip player (reuse `ShortReelItem`/PlayerController),
   15s ring timer, 4 answer buttons, instant correct/wrong + speed feedback,
   auto-advance. Server-timed (client sends `ms`, server validates).
4. **Result** — score, X/10, per-clip recap with reveal + "Watch full", a
   **shareable card** (image via a widget→PNG) + "Challenge a friend".
5. **Leaderboard** — daily/weekly/all-time/friends tabs.

Viral loop: result card + challenge deep link (`sozo.azamov.me/trivia/<code>`)
→ friend opens → app (or install) → replays the **same 10** → scores compared.

Rewards (no economy): leaderboard rank, streak, badges, bragging rights.

---

## 5. Premiere tie-in
After a Live Premiere ends, offer a **trivia round about that film** (uses the
premiere audience while it's hot) — a natural bridge between the two magnets.

## 6. Anti-cheat
- Server-authoritative timing/scoring; clip+options delivered without the answer;
  per-clip timer enforced server-side; round replays are identical but scored
  independently.

## 7. Phases
1. **MVP:** Klip Top (movies, vidapi clips), 10×15s, MC, server scoring, result
   share + challenge, all-time + friends leaderboard.
2. **V2:** Fan Test (actors/TMDB), daily challenge, weekly leaderboard, "watch
   full" reveal.
3. **V3:** anime (TMDB + AniList/Jikan characters), premiere tie-in, badges.
