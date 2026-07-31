# KINO BILLAR — Complete File-Level Architecture

Server-authoritative in-app movie/anime clip-trivia, delivered as a bottom-nav tab across `soplay` (Flutter), `soplay-backend` (Express/Mongo/R2), and `soplay-admin-web` (React). Grounded in the real code: it reuses the `generateShorts` → R2 pipeline, extends `tmdb.js` person endpoints, bridges anime via AniList/Jikan, and mirrors the shorts feature-module + admin-page patterns exactly.

Internal code name = `trivia`; user-facing brand = **KINO BILLAR**.

---

## 0. Locked scoring & anti-cheat contract (drives every repo)

- **Correct answers never leave the server before an answer is submitted.** Round-create returns clip video URLs + 4 shuffled options (title hidden) + per-clip opaque `optionId`s only. `correctTmdbId` lives only in the `TriviaRound` doc.
- **Server timestamps every clip.** When the client fetches/starts clip *i*, the server stamps `serverShownAt`. On submit, elapsed is computed server-side: `elapsed = min(clientElapsedMs, now − serverShownAt)`, clamped to `[0, clipDurationMs]`. Client-reported time is display-only; it can never *lower* the server time.
- **Points** = `correct ? (BASE=1000 + speedBonus) : 0`, `speedBonus = round(500 * (1 − elapsed/deadlineMs))` floored at 0. Streak multiplier optional (server-side).
- **Submit is atomic + idempotent.** One `findOneAndUpdate` with a positional filter (`clips.$[c].answeredAt == null`) → no read-modify-write race, re-submits are no-ops. O(1), no freeze.
- **Round create precomputes everything** (clips + distractors chosen once), so submit does zero external calls. Round doc has a **TTL index** (`expiresAt`, ~30 min) so abandoned rounds self-clean.
- **Challenge fairness**: the challenge freezes the exact 10 clipIds *and* their option arrays; every participant's round is materialized from that frozen set. Speed is measured server-side per participant.
- **Rate limits** (reuse existing token-bucket middleware): round-create ≤ ~20/min/user; leaderboard reads cached 30–60s in-memory (SWR), same style as `tmdb.api`.

---

# 1) BACKEND — `soplay-backend`

Repo root = `C:\Users\azamo\WebstormProjects\soplay-backend`. Public routes mount in **`index.js`** (root, lines 86-99); admin routes in **`src\routes\admin\index.js`** (lines 4-15); `tmdb.js` exports object ends at **line 348**.

## 1.1 Models — FILES TO ADD (`src\models\`)

### `TriviaClip.js` (new collection — do NOT reuse `Short`, keeps shorts feed clean)
```
{
  provider: 'vidapi' (req),
  contentUrl: 'https://www.themoviedb.org/movie/<id>' (req),  // re-resolvable → "Watch full"
  mediaKind: 'movie'|'tv'|'anime' (req, indexed),
  answerTmdbId: Number (req),
  answerTitle: String (req),          // HIDDEN from clients until reveal
  answerPoster: String,
  videoKey: String (req),  videoUrl: String (req),   // R2 trivia/videos/<uuid>.mp4
  thumbnailKey, thumbnailUrl,                         // R2 trivia/thumbnails/<uuid>.jpg
  durationMs: Number (~15000),  startOffset: Number,
  // FAN-TEST index + distractor metadata:
  people:      [{ personId:Number, name:String, order:Number }],  // top cast (live-action)
  characters:  [{ malCharId:Number, anilistCharId:Number, name:String }], // anime
  genres:      [Number],  year: Number,
  popularity:  Number,  voteCount: Number,  difficulty: 1|2|3,
  active: Boolean (default true, indexed),
  source: 'auto'|'manual',
  createdBy: ObjectId→Admin (req),
} + timestamps
```
Indexes: `{ active:1, mediaKind:1 }`, `{ 'people.personId':1, active:1 }` (FAN-TEST filter), `{ 'characters.anilistCharId':1, active:1 }`, `{ answerTmdbId:1 }`, `{ genres:1, year:1 }` (distractor pool).

### `TriviaRound.js`
```
{
  userId: ObjectId→User (req, indexed),
  mode: 'klip_top'|'fan_test' (req),
  actorRef: { id:Number, kind:'person'|'character', name:String, profile:String }, // fan_test
  challengeId: String (nullable, indexed),
  status: 'active'|'completed'|'expired' (default active),
  seed: String,
  clips: [{
    clipId: ObjectId, correctTmdbId: Number,
    options: [{ optionId:String, tmdbId:Number, title:String, poster:String }],
    serverShownAt: Date, answeredAt: Date,
    chosenOptionId: String, correct: Boolean, elapsedMs: Number, points: Number
  }],
  totalScore: Number (default 0), correctCount: Number (default 0),
  fandomPercent: Number,     // fan_test result
  completedAt: Date,
  expiresAt: Date (req),     // TTL
} + timestamps
```
Indexes: `{ userId:1, createdAt:-1 }`, `{ challengeId:1 }`, **TTL** `{ expiresAt:1 }, expireAfterSeconds:0`.

### `TriviaScore.js` (immutable leaderboard row, one per completed round — bucketed for O(1) board reads)
```
{
  userId (req), username, avatar,   // denormalized for board render w/o join
  roundId, mode (req),
  actorId: Number (nullable, indexed),  actorKind,
  score: Number (req), correctCount, totalTimeMs, fandomPercent,
  dayKey: 'YYYY-MM-DD' (req), weekKey: 'YYYY-Www' (req),   // computed w/ user tzOffset (reuse streak offset trick)
} + timestamps
```
Indexes: `{ mode:1, dayKey:1, score:-1, totalTimeMs:1 }`, `{ mode:1, weekKey:1, score:-1, totalTimeMs:1 }`, `{ mode:1, score:-1 }` (all-time), `{ actorId:1, score:-1, totalTimeMs:1 }` (top-fans), `{ userId:1, actorId:1, score:-1 }` (personal best per actor).

### `TriviaChallenge.js`
```
{
  code: String (req, unique, indexed),   // short base62 for deep link
  creatorUserId (req), mode (req),
  actorRef: {...},
  clips: [{ clipId, correctTmdbId, options:[{optionId,tmdbId,title,poster}] }], // FROZEN 10
  participants: [{ userId, username, avatar, roundId, score, completedAt }],
  expiresAt: Date (req),
} + timestamps
```
Indexes: `{ code:1 } unique`, TTL `{ expiresAt:1 }`.

### `ActorFanStat.js` (denormalized cache for actor hero + top-fans preview)
```
{
  actorId: Number (req, indexed), kind:'person'|'character',
  name, profile,
  roundsPlayed: Number, avgFandom: Number,
  topFans: [{ userId, username, avatar, bestScore, bestFandom, updatedAt }], // bounded 100
} + timestamps
```
Index: `{ actorId:1, kind:1 } unique`.

## 1.2 External APIs — FILES TO EDIT / ADD

### EDIT `src\utils\tmdb.js` — add + export (append to the `module.exports` object at line 348):
- `searchPeople(query, page=1)` → `GET /search/person` → cards `{ id, name, profilePath:poster(profile_path), knownForDept, knownFor:[title...], popularity }`. **This is the cast-search primitive the product owner wants** (today `resolvePersonId` only returns the first id, no cards).
- `getPopularPeople(page=1)` → `GET /person/popular` → same card shape. **Currently missing** — powers the "Popular now" grid.
- `getPersonProfile(id)` → `GET /person/{id}?append_to_response=combined_credits,images,external_ids` → `{ id, name, biography, birthday, placeOfBirth, profilePath, photos[], filmography:[cards], imdbId }`. **Currently missing** — powers the Actor Hero.
- `getClipCandidatesForPerson(id)` → filters `combined_credits.cast` to `vote_count >= 300` + released + has poster (same quality gate as `generateShorts.gatherMovieCandidates`) → the FAN-TEST clip source list.

`getActor` / `getDetail` (top-billed `cast`) already exist and are reused as-is.

### ADD `src\utils\anilist\characters.js` — the anime character bridge (the missing unification)
Wraps AniList GraphQL (`https://graphql.anilist.co`, reuse the 500ms rate-gate + cache style already in `src\utils\anikai\jikan.js`):
- `searchCharacters(query)` → AniList `Character(search:)` → `[{ anilistCharId, name, image, media:[{title, anilistMediaId, malId}] }]`. **Cast-search for anime** (TMDB is useless for animated characters).
- `getCharacterMedia(anilistCharId)` → the anime titles featuring that character → mapped to malIds (for the FAN-TEST clip filter).
- Fallback `jikan.getCharacters(malId)` (existing) when enriching clip metadata at gen time.

### ADD `src\services\castResolver.service.js` — the single unified resolver the study says is missing
- `search({ q, kind })` → `kind==='person' ? tmdb.searchPeople : anilist.searchCharacters`.
- `popular({ kind })` → `tmdb.getPopularPeople` (person) / AniList trending characters (anime).
- `profile({ id, kind })` → `tmdb.getPersonProfile` / AniList character page + media.
- `clipFilterFor({ id, kind })` → returns the Mongo filter (`{'people.personId':id}` vs `{'characters.anilistCharId':id}`) used by round-build.

## 1.3 Service — ADD `src\services\trivia.service.js` (all game logic; no freeze)
- `buildRound({ userId, mode, actorRef })`:
  - Klip Top: `TriviaClip.aggregate([{$match:{active:true}},{$sample:{size:10}}])` (bounded, indexed).
  - Fan Test: `$match` on `castResolver.clipFilterFor` + `$sample:10`; if actor has <10 clips, top up with genre-adjacent clips.
  - `buildOptions(clip)` — 1 correct + 3 distractors sampled from same `mediaKind`/genre/year band (a small in-memory SWR-cached candidate pool per genre, refreshed like `tmdb.api`; never a live TMDB call at request time). Shuffle, assign opaque `optionId`s.
  - Persist `TriviaRound` with `expiresAt = now + 30m`, `serverShownAt=null`.
- `startClip(roundId, userId, clipIndex)` → atomic set `serverShownAt=now` if unset; returns nothing sensitive.
- `submitAnswer(roundId, userId, clipIndex, chosenOptionId, clientElapsedMs)`:
  - single `findOneAndUpdate` guarded by `clips.$[c].answeredAt == null`; computes `elapsed` (clamped), `correct`, `points`; `$inc totalScore/correctCount`. Returns `{ correct, correctTmdbId, title, poster, points, runningScore }` (reveal payload). Idempotent.
- `completeRound(roundId, userId)` → compute `fandomPercent` (`correct/10*100` weighted by speed for fan_test), write `TriviaScore` (with `dayKey/weekKey` from user tzOffset), upsert `ActorFanStat.topFans` (bounded insert-sort), return `{ score, fandomPercent, rank }` (rank via `countDocuments({score:{$gt}})+1`).
- `leaderboard({ scope, mode, actorId, userId, friendIds })` → indexed `find().sort().limit(100)`; friends scope adds `userId:{$in:friendIds}`; **30-60s in-memory cache** keyed by `scope|mode|actorId`.
- `topFans({ actorId, kind })` → read `ActorFanStat.topFans` (cached), fallback aggregate on `TriviaScore`.
- `createChallenge` / `getChallenge` / `materializeChallengeRound` (frozen clips).

## 1.4 Public routes — ADD `src\routes\trivia.js` + `src\controllers\trivia.controller.js`
Mount in **`index.js`** after line 97: `app.use('/api/trivia', require('./src/routes/trivia'));`. All behind existing `auth` middleware + 30s timeout wrapper (like admin routes).

| Method | Path | Body/Query | Returns |
|---|---|---|---|
| POST | `/trivia/rounds` | `{ mode, actorId?, kind? }` | round meta + clips (title-hidden, options) |
| POST | `/trivia/rounds/:id/start-clip` | `{ clipIndex }` | `{}` (stamps serverShownAt) |
| POST | `/trivia/rounds/:id/answers` | `{ clipIndex, chosenOptionId, clientElapsedMs }` | reveal `{ correct, correctTmdbId, title, poster, points, runningScore }` |
| POST | `/trivia/rounds/:id/complete` | — | `{ score, fandomPercent, rank }` |
| GET | `/trivia/rounds/:id` | — | resume active round |
| POST | `/trivia/challenges` | `{ mode, actorId?, kind? }` or `{ roundId }` | `{ code, deepLink, webLink }` |
| GET | `/trivia/challenges/:code` | — | challenge meta + participants |
| POST | `/trivia/challenges/:code/rounds` | — | round from frozen 10 |
| GET | `/trivia/leaderboard` | `?scope=daily\|weekly\|all\|friends&mode=&actorId=` | top 100 + my rank |
| GET | `/trivia/actors/top-fans` | `?actorId=&kind=` | ranked fans |
| GET | `/trivia/cast/search` | `?q=&kind=person\|character` | person/character cards |
| GET | `/trivia/cast/popular` | `?kind=` | popular cards |
| GET | `/trivia/cast/:id` | `?kind=` | actor profile + filmography |

## 1.5 Admin routes — ADD `src\routes\admin\trivia.js` + `src\controllers\admin\trivia.controller.js`
Mount in `src\routes\admin\index.js`: `router.use('/trivia', require('./trivia'));`. Mirror `shorts.js` exactly:
- `GET /admin/trivia?page=&limit=20&mediaKind=` → `{ items, total, totalPages }`
- `GET /admin/trivia/resolve-content?url=` (reuse detectProvider/getDetail)
- `POST /admin/trivia/upload-url` `{ type:'video'|'thumbnail', contentType }` → presigned R2 (reuse `r2Service.getPresignedUploadUrl`, keys under `trivia/`)
- `POST /admin/trivia` (create manual clip; controller composes `videoUrl`, auto-fills `people` from `tmdb.getDetail` cast, `characters` via `castResolver` for anime)
- `PUT /admin/trivia/:id` (toggle active / edit)
- `DELETE /admin/trivia/:id` (delete + R2 objects, like shorts.remove)
- `POST /admin/trivia/generate` `{ count, mediaKind }` → enqueues a bounded batch (optional; the CLI script is the primary path)

## 1.6 Clip generation + PROD seed — ADD `scripts\generateTriviaClips.js`
Clone `scripts\generateShorts.js` with these deltas:
- `CLIP_DUR` default **15s**; write to R2 `trivia/videos/…`, `trivia/thumbnails/…`.
- Candidate gathering extended to `movie` + `tv` + anime (via existing anime providers/AniList).
- After `tmdb.getDetail`: store top-billed `cast` → `clip.people`; for anime, `castResolver` → `clip.characters`.
- Persist to **`TriviaClip`** (not `Short`); keep `answerTitle` server-only.
- Same `createdBy` Admin lookup; same vidapi header replay to ffmpeg (no 403s).

**PROD seed procedure (the documented gotcha):** port 27017 is not exposed; prod Mongo is the Docker volume. Run on the server inside the compose network:
```
docker compose exec app node scripts/generateTriviaClips.js --count=300 --dur=15 --concurrency=2
```
Seeded `TriviaClip` docs persist across deploys (deploy recreates only `app`, not `mongo`). Never run locally against prod — `MONGODB_URI` there points at dev Atlas.

**Backend files summary — ADD:** `src\models\{TriviaClip,TriviaRound,TriviaScore,TriviaChallenge,ActorFanStat}.js`, `src\services\{trivia.service,castResolver.service}.js`, `src\utils\anilist\characters.js`, `src\routes\trivia.js`, `src\controllers\trivia.controller.js`, `src\routes\admin\trivia.js`, `src\controllers\admin\trivia.controller.js`, `scripts\generateTriviaClips.js`. **EDIT:** `src\utils\tmdb.js` (add person fns + export), `index.js` (mount `/api/trivia`), `src\routes\admin\index.js` (mount `/trivia`).

---

# 2) APP — `soplay` (Flutter)

Root = `C:\Users\azamo\AndroidStudioProjects\soplay`. Feature dir = `lib\features\trivia\`. Follows the shorts Clean-Architecture template verbatim (DataSource throws → Repository → `Result` → UseCase → Bloc; entities `Equatable`; `const` ctors; DataSources get `dio: getIt<Dio>()`).

## 2.1 Domain — `lib\features\trivia\domain\`
- `entities\trivia_clip_entity.dart` (videoUrl, durationMs, options — NO answer)
- `entities\trivia_option_entity.dart` (optionId, title, poster)
- `entities\trivia_round_entity.dart` (roundId, mode, clips, index, actorRef)
- `entities\reveal_result_entity.dart` (correct, correctTitle, poster, points, runningScore, contentUrl)
- `entities\trivia_result_entity.dart` (score, fandomPercent, rank, correctCount)
- `entities\cast_person_entity.dart` (id, name, profileUrl, knownFor, kind)
- `entities\actor_profile_entity.dart` (bio, birthplace, photos, filmography, kind)
- `entities\actor_fan_stat_entity.dart` / `entities\top_fan_entity.dart`
- `entities\leaderboard_entry_entity.dart`, `entities\challenge_entity.dart`
- `repositories\trivia_repository.dart` — all methods `Future<Result<T>>`
- `usecases\` (one file each): `create_round_usecase`, `start_clip_usecase`, `submit_answer_usecase`, `complete_round_usecase`, `resume_round_usecase`, `search_cast_usecase`, `get_popular_cast_usecase`, `get_actor_profile_usecase`, `get_leaderboard_usecase`, `get_top_fans_usecase`, `create_challenge_usecase`, `get_challenge_usecase`, `join_challenge_usecase`.

## 2.2 Data — `lib\features\trivia\data\`
- `datasources\trivia_remote_data_source.dart` — `const ...({required this.dio})`, one method per endpoint in §1.4, defensive `response.data is Map ? …` parsing, returns Models, throws `DioException`.
- `models\` — mirror each entity as `*_model extends *Entity` with `factory fromJson` + `_str/_int/_bool` helpers.
- `repositories\trivia_repository_impl.dart` — `implements TriviaRepository`, `try / on DioException / catch` → `Success`/`Failure(Exception(_messageFrom(e)))`, copy `_messageFrom`.

## 2.3 Presentation — Blocs (`presentation\bloc\`)
- `hub\trivia_hub_bloc` — mode select + my rank teaser.
- `cast\cast_bloc` (`_event`,`_state`) — search-as-you-type with **300ms debounce** (`EventTransformer` / `restartable`), popular grid load, kind toggle.
- `game\game_bloc` (`_event`,`_state`) — owns the round + **15s timer** (`Ticker`/`Timer.periodic` → `TimerTicked`), events `RoundStarted`, `ClipShown`(→start-clip), `OptionSelected`(→submit), `Revealed`, `NextClip`, `RoundCompleted`. Timeout auto-submits a null answer.
- `leaderboard\leaderboard_bloc` — scope tabs (daily/weekly/all/friends).
- `topfans\top_fans_bloc`.
- `challenge\challenge_bloc`.
Blocs = `registerFactory`; consume `Result` via exhaustive `switch (case Success<T>(:final value) / Failure<T>(:final error))`.

## 2.4 Presentation — Pages & the beautiful UI (`presentation\pages\` + `widgets\`)

### `kino_billar_hub_page.dart` — the bottom-nav TAB
Brand-red gradient hero header "KINO BILLAR", two big mode cards:
- **Klip Top** (speed-race icon, "10 clips · 15s each") → pushes game.
- **Fan Test** (star/heart icon, "Pick your favorite") → pushes `cast_picker_page`.
Below: my daily-rank chip + "View leaderboards". Uses `AppColors.background/surface/primary`, `CupertinoIcons`, matching frosted-card aesthetic.

### `cast_picker_page.dart` + widgets — THE showcase surface (product-owner priority)
Layout, top→bottom:
1. **Pinned glass search bar** (`BackdropFilter`, `rounded-xl`, `AppColors.surface`): leading `CupertinoIcons.search`, hint "Search actor or character", trailing clear (×), and a segmented **Movies · Anime** toggle (person vs AniList character). Debounced 300ms via `cast_bloc`.
2. **Empty-query state → "Popular now" grid** (`popular_cast_grid.dart`): 3-col `GridView`, each `cast_card.dart` = circular profile photo (`CachedNetworkImage`, shimmer placeholder) with a subtle red ring on focus, name (1 line), known-for subtitle (fade). `TMDB /person/popular` for movies, AniList trending for anime.
3. **As-you-type results** replace the grid: same `cast_card` grid, matched substring bolded; graceful "No results" + shimmer skeletons during load.
4. Tap → hero transition to `actor_hero_page` (shared `Hero` tag on the profile photo).

### `actor_hero_page.dart` — selected-actor hero
- Full-bleed **blurred backdrop** (actor's top known-for poster), gradient scrim to `AppColors.background`.
- Centered **circular profile** (red `AppColors.primary` ring) + name + birthplace/known-for-dept + "N titles".
- **Top Fans preview strip** (`top_fans_strip.dart`): top-3 avatars w/ medal accents + "You: #rank" chip → tap opens full `top_fans_page`.
- **Filmography rail**: horizontal poster carousel (informational).
- Sticky bottom bar: primary CTA **"Start Fan Test"** (brand-red gradient, haptic) → game; secondary **"Challenge a friend"** → creates challenge + share sheet.

### `game_page.dart` — gameplay (reuses the app video player, title hidden)
- Full-screen vertical clip; **progress dots 1…10** top; **circular 15s countdown ring** (turns red < 4s) around a timer badge.
- Bottom **2×2 option chips** (`option_chip.dart`), tap locks → immediate optimistic disable, calls submit.
- **Reveal**: correct chip → green, wrong pick → red; poster + real title slide up; floating "+1350" points; **"Watch full"** button → `context.push('/detail', extra: contentUrl)` (works because `contentUrl` re-resolves via vidapi). Auto-advance ~2s → next clip → `start-clip`.
- Back-press guarded (confirm forfeit). No ANR: timer + player disposed on pop.

### `result_page.dart` + `share_card.dart`
- **Fan Test**: big circular **fandom %** gauge, correct count, avg speed, rank delta, actor mini-hero.
- **Klip Top**: score, rank, streak.
- **Share card**: a `RepaintBoundary` composed card (actor photo + fandom % + brand) → `toImage` → `share_plus` with the challenge deep link. Buttons: Share, Challenge a friend, Play again, Leaderboard.

### `leaderboard_page.dart` (scope tabs daily/weekly/all-time/friends; my row pinned/highlighted) and `top_fans_page.dart` (ranked, medals top-3, fandom % + best score, my row pinned).

### `challenge_landing_page.dart` — deep-link target
Shows challenger's name + score-to-beat, "Play the same 10 clips" → `join_challenge` → game with frozen set.

## 2.5 DI — EDIT `lib\core\di\injection.dart`
Add imports; inside `configureDependencies()` in dependency order (mirror shorts block ~L244-324):
`registerSingleton<TriviaRemoteDataSource>(TriviaRemoteDataSource(dio: getIt<Dio>()))` → `registerSingleton<TriviaRepository>(TriviaRepositoryImpl(getIt<TriviaRemoteDataSource>()))` → each `registerSingleton<…UseCase>(…(getIt<TriviaRepository>()))` → `registerFactory(() => CastBloc(...))`, `registerFactory(() => GameBloc(...))`, `registerFactory(() => LeaderboardBloc(...))`, etc.

## 2.6 Router — EDIT `lib\core\router\app_router.dart`
Add `GoRoute`s (each page wraps itself in `BlocProvider(create: (_) => getIt<Bloc>())`):
- `/trivia/cast` → CastPickerPage
- `/trivia/actor` (extra: CastPersonEntity) → ActorHeroPage
- `/trivia/game` (extra: GameArgs{mode, actorRef?, challengeCode?})
- `/trivia/result` (extra: TriviaResultEntity)
- `/trivia/leaderboard`, `/trivia/top-fans` (extra: actorId)
- `/trivia/challenge/:code` → ChallengeLandingPage (read `state.pathParameters['code']`) — **deep link target**.

Deep-link registration: add `soplay://trivia/challenge/<code>` + `https://sozo.azamov.me/trivia/challenge/<code>` to the existing Android intent-filter / iOS associated-domains (same mechanism used for other links).

## 2.7 Bottom-nav TAB integration — EDIT `lib\features\main\presentation\pages\main_page.dart`
Per the nav study, keep the **two parallel lists index-aligned**:
- Insert `KinoBillarHubPage()` into the tabs `List<Widget>` (build, ~L161-170).
- Insert a matching `_NavItem` (icon `CupertinoIcons.film`/gamecontroller, `activeIcon`, `labelKey:'navigation.kino_billar'`) into `_SoplayGlassCapsule._items` (~L333-359) at the **same index**.
- If inserted before Shorts, bump `_shortsIndex` (L40) and any hardcoded `goTo(n)` accordingly — safest is to append the tab **after Shorts** (index 3, pushing MyList→4, Profile→5) and update the magic indices in `app.dart:111`, `streak_badge.dart`, `home_top_bar.dart`, `home_content.dart`, `my_list_page.dart`. (Recommended: adopt the study's `TabId` registry in `lib\core\navigation\app_tab.dart` to de-magic these once.)

EDIT `assets\translations\{en,ru,uz}.json` → add `navigation.kino_billar` + all `trivia.*` UI keys.

**App files summary — ADD:** the full `lib\features\trivia\` tree above. **EDIT:** `injection.dart`, `app_router.dart`, `main_page.dart`, 3 translation JSONs (+ the 5 magic-index call sites if inserting before Shorts).

---

# 3) ADMIN-WEB — `soplay-admin-web`

Root = `C:\Users\azamo\WebstormProjects\soplay-admin-web`. Three edits (the standard add-a-page recipe).

### ADD `src\pages\Trivia.jsx`
Clone `src\pages\Shorts.jsx` (upload + table + pagination). Specifics:
- `import api, { uploadToR2 } from '../api/client';`
- List: `api.get('/admin/trivia', { params:{ page, limit:20, mediaKind } })` → `{items,total,totalPages}`; filter dropdown movie/tv/anime; columns thumbnail, answerTitle, mediaKind, cast count, active toggle, delete.
- Add-clip modal (like `AddShortModal`): `GET /admin/trivia/resolve-content?url=` → preview; `POST /admin/trivia/upload-url {type:'video',contentType}` → `uploadToR2(uploadUrl, file, setProgress)` (reuse `ProgressBar`); same for thumbnail; `POST /admin/trivia` with `{videoKey, thumbnailKey, contentUrl, mediaKind, durationMs, answerTitle}` (server backfills cast).
- Toggle active via `PUT /admin/trivia/:id` (Banners `toggleActive` pattern); delete via `DELETE /admin/trivia/:id`.
- Optional "Generate batch" button → `POST /admin/trivia/generate {count, mediaKind}`.

### EDIT `src\App.jsx`
`import Trivia from './pages/Trivia';` + inside the `<Layout/>` PrivateRoute block: `<Route path="trivia" element={<Trivia />} />`.

### EDIT `src\components\Layout.jsx`
Add to the `nav` array: `{ to:'/trivia', label:'Kino Billar', icon:(<svg className="w-5 h-5" stroke="currentColor" .../>) }`.

**Admin files summary — ADD:** `src\pages\Trivia.jsx`. **EDIT:** `src\App.jsx`, `src\components\Layout.jsx`.

---

# 4) Phased build order

**Phase 0 — Data & pipeline (backend, no app dependency).** `TriviaClip` model; `scripts\generateTriviaClips.js`; seed ~50 movie clips to **dev** Mongo. Verify R2 keys + "Watch full" re-resolve. Extend `tmdb.js` person fns.

**Phase 1 — Cast/actor read APIs.** `castResolver.service.js` + `anilist\characters.js`; `/trivia/cast/{search,popular,:id}`. Ship the **Cast Picker + Actor Hero** app screens first (they're the design-forward centerpiece and fully testable without gameplay).

**Phase 2 — Rounds & scoring (Klip Top).** `TriviaRound`, `trivia.service` (buildRound/startClip/submitAnswer/completeRound), `/trivia/rounds/*`. App `game_bloc` + `game_page` + `result_page`. Wire the **bottom-nav tab**. End-to-end Klip Top playable.

**Phase 3 — Fan Test + fandom + top fans.** Fan-Test round build (person/character filter), `TriviaScore`, `ActorFanStat`, `/trivia/actors/top-fans`. App: Actor Hero → Start Fan Test → fandom % result + Top Fans board.

**Phase 4 — Leaderboards.** `/trivia/leaderboard` (daily/weekly/all/friends, cached). App leaderboard page + hub rank teaser.

**Phase 5 — Challenge-a-friend.** `TriviaChallenge`, `/trivia/challenges/*`, frozen 10; app deep link + challenge landing + share card.

**Phase 6 — Admin + PROD seed.** `admin\trivia` routes + `Trivia.jsx` page. Run `docker compose exec app node scripts/generateTriviaClips.js --count=300` **on the server** to seed PROD (persists across deploys). Anti-cheat hardening pass (rate limits, TTL, idempotency verification) + leaderboard cache tuning.

---

### Key correctness guarantees (why it won't freeze)
Round-create is the only heavy op and it precomputes distractors from an in-memory SWR pool (no live TMDB at request time); submit is a single atomic idempotent `findOneAndUpdate`; leaderboards are covered-index `sort+limit(100)` with 30-60s caching; abandoned rounds self-expire via TTL; all routes wrapped in the existing 30s timeout + token-bucket limiter. Correct answers are structurally unreachable client-side until an answer is recorded, and elapsed time is server-clamped — so speed ranking and fandom % cannot be spoofed.