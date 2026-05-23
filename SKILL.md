---
name: zooop
description: |
  Generate or edit images / videos / audio via the ZOOOP AI platform — t2i,
  i2i, t2v, i2v, lipsync, upscale, remove-background, TTS, voice-clone,
  sound-effect, music. Use whenever the user asks to generate, create, make,
  edit, or transform any of those media types.
---

# ZOOOP AI generation

Public REST API host: `https://api.zooop.ai` (override via `$ZOOOP_API_HOST`).
Auth: `Authorization: Bearer $ZOOOP_API_KEY` on every request.

`scripts/{upload,quote,submit,poll,download,ai-tools,describe}.sh` ship with
this skill. Inline `curl` recipes below work the same way if the bundle isn't
cloned. Full request / response / error reference:
[`references/api-docs.md`](./references/api-docs.md) — read it whenever this
guide doesn't cover a field.

## API key — setup

**The token must NEVER appear in the agent conversation.** Token in chat
risks leaking into training corpora, telemetry, or shared transcripts —
once leaked it spends the user's credits until revoked. Always have the
**user** set the env var themselves, in their own terminal.

Agent: check `$ZOOOP_API_KEY` (or OS-equivalent). If empty, give the user
these instructions **verbatim** — do not ask them to paste the token back:

1. Visit https://zooop.ai/user#apiKeys → **Create token** → pick project
   (immutable) → **set a daily credit cap** → copy token (shown ONCE).
2. In their **own terminal** (NOT this chat), set the env var:
   - macOS / Linux / WSL / Git Bash —
     `echo 'export ZOOOP_API_KEY=zpk_live_…' >> ~/.zshrc && source ~/.zshrc`
   - Windows PowerShell —
     `[Environment]::SetEnvironmentVariable('ZOOOP_API_KEY','zpk_live_…','User')`
   - Windows cmd — `setx ZOOOP_API_KEY "zpk_live_…"`
3. **Restart the agent** so the new env var is inherited.

Credits charge the user's ZOOOP balance; tasks and uploads land under the
PAT's bound project.

## Two paths: raw model vs AI tool

**Default to raw models.** AI tools are a deliberately narrow surface for
specialized capabilities that raw text-to-image / text-to-video models
CAN'T replicate — chiefly precise background removal and image / video
upscaling. For everything else (style transfer, edits, age changes,
character animations, etc.) prefer a raw model: GPT Image 2 / Nanobanana
handle most prompt-driven edits more flexibly AND cheaper.

| Path | When | How |
| --- | --- | --- |
| **Raw model** (`interfaceId` + `versionId`) | Default. Text-driven generation, prompt-driven edits, anything where you'd write a prompt | `GET /v1/models?type=…&subtype=…` → submit with `interfaceId` + `versionId` + `params` |
| **AI tool** (`aiTool` slug) | Specialized non-prompt-driven capabilities only — currently background removal + image/video upscale. Browse `GET /v1/ai-tools` to see what's actually exposed | `GET /v1/ai-tools` → submit with `aiTool: <slug>` + the tool's `params[]` |

AI tools are admin-curated and admin-gated — only a small allowlist appears
in `/v1/ai-tools`. If your task isn't on that list, don't try to force it
through; use a raw model with a tailored prompt.

```bash
# Browse the (small) curated catalog
bash scripts/ai-tools.sh                 # all
bash scripts/ai-tools.sh image           # only image
bash scripts/ai-tools.sh video           # only video
bash scripts/ai-tools.sh -s <slug>       # one tool's full param schema
```

Submit / quote via the same scripts using `--ai-tool`:

```bash
bash scripts/submit.sh --ai-tool background-removal '{"image_url":"https://storage.zooop.ai/…"}'
bash scripts/quote.sh  --ai-tool background-removal '{"image_url":"https://storage.zooop.ai/…"}'
```

## How model selection works (raw path)

Pick a (type, subType) pair by **what the user wants to do**, not by what
inputs they happen to provide. The same image + prompt combination can
legitimately land in three different subTypes depending on intent — read
the table carefully, names like `motion-control` and `text-ref` are NOT
self-explanatory.

| type   | subType          | What it's for                                                                                  |
| ------ | ---------------- | ---------------------------------------------------------------------------------------------- |
| image  | default          | Generate a new image, **or edit an existing one from a plain text description** (text-to-image, img-to-img, style transfer, prompt-driven edits — GPT Image 2 / Nanobanana handle "把背景换成…" / "去掉左边的人" without any mask) |
| image  | edit-image       | Targeted region edit driven by a **black-and-white mask or hand-drawn annotation** the user supplies. Only pick this when the user actually provides (or asks to draw) a mask/region — never for plain text-described edits |
| video  | text-ref         | Generate a video from a prompt. Some models also accept reference images **for style** (referenced as `@Image1` / `@Image2` in the prompt) — these guide look, NOT motion |
| video  | first-last-frame | **Animate a still image** — provide one image as the start frame and the model generates motion outward. Optional end frame interpolates between two keyframes |
| video  | motion-control   | Make an image move using motion **copied from a reference video** (e.g. the character in the image performs the action / dance in the reference clip) |
| video  | audio-lipsync    | Make a character image lip-sync to a given audio track                                          |
| video  | extend-video     | Continue an existing video — append more frames after its last one                              |
| video  | video-edit       | Restyle or re-edit an existing video clip                                                       |
| audio  | text-to-speech   | TTS in a named voice                                                                            |
| audio  | voice-clone      | Speak text using a voice cloned from a reference audio sample                                   |
| audio  | sound-effect     | One-shot sound effect from a text description                                                   |
| audio  | music            | Music track from a text description                                                             |

For the per-model required fields (which image / video / audio params, and
which are optional), read `params[].required` on the model returned by
`/v1/models`. Don't infer from the subType — different models in the same
subType can have different param requirements.

### Disambiguation — pick subType by intent

The hard cases are video subTypes (and image edits), where the user's
**goal** decides, not which media they happen to hand you:

| User says… | Pick | Why |
| --- | --- | --- |
| "把这张图的背景换成海边" / "remove the person on the left" / "edit this photo to…" (image + text only, no mask) | **image/default** | Plain-text edits go through `default` with GPT Image 2 or Nanobanana — they take a reference image + edit prompt natively. `edit-image` is the wrong pick because it requires a mask the user didn't provide. |
| "我画了个 mask / 涂了一块区域，只改这里" | **image/edit-image** | The user actually has a mask or hand-drawn region. That's the only time `edit-image` is right. |
| "让这张图动起来" / "animate this poster" | **video/first-last-frame** | Goal: bring a still image to life. The image is a *start frame*. |
| "用这张图当风格参考生成视频" / "use this image as a style reference" | **video/text-ref** | Goal: generate a new scene; image only shapes look. Reference image goes into the model's `image_urls` / `reference_image_urls` param and is cited as `@Image1` in the prompt. |
| "让这个角色跳这段舞" / "make this character do this dance" | **video/motion-control** | Goal: transplant motion from a reference video onto an image. |
| "让这个人对口型说这段话" / "lip-sync this audio to my photo" | **video/audio-lipsync** | Goal: drive an image's mouth from audio. |
| "续写这段视频" / "extend this clip" | **video/extend-video** | Goal: more frames after the last one. |
| "把这段视频换风格" / "restyle this video" | **video/video-edit** | Goal: change look/feel of existing video. |
| Pure prompt → video, no input image | **video/text-ref** | Goal: generate from text alone. |

Each model has one or more `versions` (e.g. `standard` / `pro` / `fast`)
with a coarse `typicalPrice` summary like
`{ typicalCredits: 8, unit: "second", note: "~40 credits for 5s @ 720p" }`.
That's enough to explain ballpark cost to the user. For an **exact** quote,
call `POST /v1/quote` (see "Quote before submit"). Final cost is enforced
server-side at submit time and echoed in `creditsCharged`.

## Standard workflow

1. **(Optional, first call only)** `GET /v1/me` — remaining daily budget,
   account balance, bound project name, current rate-limit numbers.

2. **Discover models** for the matching subtype:
   ```bash
   curl -fsS "$ZOOOP_API_HOST/v1/models?type=video&subtype=motion-control" \
        -H "Authorization: Bearer $ZOOOP_API_KEY"
   ```
   Match the user's hint (e.g. "用 seedance2") against `name` / `brand.name`.
   No hint → follow "Default model selection" below.

3. **(Optional) Upload local files.** If the user gave a path on disk:
   ```bash
   bash scripts/upload.sh /path/to/file.png
   # → prints the storage URL to feed into params.
   ```
   Wraps `POST /v1/uploads`. Image / audio return sync; video polls Aliyun
   moderation until terminal (5–30s typical). Block → exits non-zero.

4. **Quote the task** — exact credits + ETA, no side effects:
   ```bash
   bash scripts/quote.sh <interfaceId> <versionId> '<params-json>'
   # → { "credits": 8, "estimatedSeconds": 18, "breakdown": {...} }
   ```
   Safe to repeat. See "Quote before submit" for the confirmation policy.

5. **Submit the task**:
   ```bash
   bash scripts/submit.sh <interfaceId> <versionId> '<params-json>'
   # → { "taskId": "...", "status": "queued", "modelId": "...", "versionId": "..." }
   ```

6. **Poll until terminal** (`succeeded` / `failed` / `cancelled`):
   ```bash
   bash scripts/poll.sh <taskId>
   # → { "status": "succeeded", "outputs": [{"url": "..."}], "creditsCharged": 4 }
   ```

7. **Show the URL, then offer download.** Proactively ask *"Want me to
   download it to a local file?"* — on yes:

   ```bash
   bash scripts/download.sh <taskId>   # → saves to ~/Desktop, ext picked from content-type
   ```

   Skip the prompt only if the user already said "just show the URL".

## Quote before submit

Before every `POST /v1/tasks`, call `POST /v1/quote` with the **same body**
to get exact credits + P50 ETA. No charge, no DB row, no capacity hold —
safe to call as often as you like.

```bash
curl -fsS -X POST "$ZOOOP_API_HOST/v1/quote" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"interfaceId":"...","versionId":"...","params":{...}}'
# → { "credits": 8, "estimatedSeconds": 18, "modelName": "Kling V3",
#     "breakdown": { "pricingKey": "720p", "base": 8, "multiplier": 1, ... } }
```

After the quote, print **one compact summary line** before submitting —
just the agent's choice + cost, so the user can sanity-check it. Don't
echo the prompt back; they just typed it and re-reading it is noise.

```
→ Kling V3 · 720p · 8 credits · ~18s
```

**Confirmation policy** (don't confirm on every task — annoying):

| Situation | Behaviour |
| --- | --- |
| Default — single task, no opt-in/out | Print summary line, submit. No "should I continue?". |
| User said "不用问我" / "just go" / "make N variants" | Submit silently, no extra confirmation. |
| User said "ask me before spending" / "贵的让我确认" | Confirm before submitting. |
| Batch (≥ 3 tasks OR total ≥ 100 credits) | Confirm once for the whole batch unless already opted out. |
| `estimatedSeconds == null` | Say "ETA unknown" — don't invent a number. |

If the quote returns 400 / 404, fix the payload and re-quote — never submit
a request that just failed to quote.

## Default model selection

When the user's request is vague and does NOT name a model / brand / quality
tier, pick the curated defaults below.

### Images (`type=image, subtype=default`)

This subType covers BOTH text-to-image generation AND prompt-driven edits
of an existing image (e.g. "把背景换成海边", "去掉左边的人", "改成赛博朋克
风格"). Pass the user's source image as the model's reference-image param
— no mask required. Only fall back to `subtype=edit-image` if the user
actually hands over a mask or hand-drawn region.

- Default model: **GPT Image 2.0** with `quality: "low"`, `resolution: "2k"`,
  `aspect_ratio: "1:1"`. ~80% of cases are fine at `low`; `medium` handles
  ~95% of needs. Also strong for prompt-driven edits.
- For edits where the user wants tight identity / layout preservation
  (face stays the same, only one element changes), **Nanobanana** is the
  better pick — match `name` substring `nanobanana` against `/v1/models`.
- **Quality-sounding words inside the user's prompt are prompt-words, not
  param hints.** Phrases like "highest quality", "最高质量", "4k",
  "ultra-realistic", "cinematic", "电影级" appear as decorative descriptors
  in almost every prompt — they do NOT mean the user is asking you to bump
  the `quality` param. Keep `quality: "low"`.
- Bump to `quality: "medium"` when the request is non-trivial (detailed
  composition, important visual fidelity) or when a `low` result didn't
  satisfy.
- `quality: "high"` only for genuinely complex requests (intricate detail,
  fine typography, multi-subject composition) OR when the user explicitly
  passes `params.quality: "high"`.
- Switch to a different image model only when the user explicitly asks
  (e.g. "use Flux" / "用 Seedream"). Don't switch on a quality complaint.

### Videos (`type=video, subtype=text-ref`)

| User signal | Pick |
| --- | --- |
| "highest quality" / "best" / "电影级" | **Seedance 2** |
| Balanced (default — no explicit signal) | **Kling O3** → fallback to **Kling V3** → **Happy Horse** → **Grok Imagine** (pick first one available) |
| "cheap" / "fastest" / "性价比" / "便宜" | **Grok Imagine** |

Match by `name` (case-insensitive substring) or `brand.name` against `/v1/models`.

### Other categories

For `audio/*`, `image/edit-image` (mask-based only — see disambiguation
above), and all other video subtypes (`motion-control`, `first-last-frame`,
`audio-lipsync`, `extend-video`, `video-edit`), use **`models[0]`** from
`/v1/models` — pre-sorted, first row is the recommended default.

## Reference image → prompt (`POST /v1/describe-image`)

Turn a user-supplied reference image into a ready-to-feed prompt. Useful
when the user pastes "make something like THIS" — get a structured prompt
back, then plug it into a video / image submit.

```bash
bash scripts/describe.sh <https://storage.zooop.ai/…>
# → { "credits": 1, "overallDescription": "A vibrant ...", "subject": "...",
#     "composition": "...", "style": "...", "lighting": "...", "palette": "...",
#     "mood": "...", "camera": "..." }
```

- Input MUST be a ZOOOP CDN URL (returned by `/v1/uploads`). Foreign URLs are
  rejected — pipe local files through `upload.sh` first.
- Costs 1 credit per call. Upstream / parse failures auto-refund.
- `overallDescription` is the canonical one-paragraph prompt; other fields
  are best-effort and may be empty when the model can't tell.
- Per-PAT rate-limited to 10 / min (vision LLM is expensive).

## Endpoints

| Method | Path                       | What                                       |
| ------ | -------------------------- | ------------------------------------------ |
| GET    | `/v1/me`                   | Self-introspection                         |
| GET    | `/v1/models`               | List public models by `type` × `subtype`   |
| GET    | `/v1/ai-tools`             | List curated AI tools (optional `?type=image\|video`) |
| GET    | `/v1/ai-tools/{slug}`      | Full param schema for one tool             |
| POST   | `/v1/quote`                | Price a task (accepts `interfaceId` OR `aiTool`) |
| POST   | `/v1/tasks`                | Submit a generation (accepts `interfaceId` OR `aiTool`) |
| GET    | `/v1/tasks/{id}`           | Poll status / outputs                      |
| POST   | `/v1/uploads`              | Upload a file (raw body + `Content-Type`)  |
| GET    | `/v1/uploads/{uploadId}`   | Poll async (video) upload moderation       |
| POST   | `/v1/describe-image`       | Reference image → structured prompt (1 credit) |

Full request / response shapes live in `references/api-docs.md`.

## Reading a model's params schema

`/models` returns `params: InterfaceParam[]` per model. Each entry carries
`id` (the key to set in `params`), `type`, `required`, `options`,
`constraints`, `default`. Media-URL types (`image_url`, `video_url`,
`audio_url`, `first_frame`, `last_frame`, `mask_url`, `voice`, …) accept
only ZOOOP-hosted URLs — pipe foreign URLs / local paths through
`upload.sh` first. Full type list and behaviour: `references/api-docs.md`.

## Uploads — single-step raw-body

```bash
curl -X POST "$ZOOOP_API_HOST/v1/uploads" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: image/png" \
  --data-binary "@$HOME/Desktop/cat.png"
```

`Content-Type` drives moderation path AND the resulting file extension —
pass the file's REAL mime, not a guess. Image / audio return sync
(`{ "status": "ready", "url": ..., "size": ..., "contentType": ... }`).
Video returns `{ "status": "processing", "uploadId": ..., "pollUrl": ... }`
— then poll `GET /v1/uploads/{uploadId}` until `ready` / `blocked` / `errored`.

Allowed mimes, size cap (100 MB), and full poll-status shapes: see
`references/api-docs.md` → `POST /v1/uploads`.

## Error response shape

OpenAI-style envelope:

```json
{ "error": { "message": "...", "type": "invalid_request_error",
             "code": "missing_required_params", "params": [...] } }
```

- `type` — broad family: `invalid_request_error` / `authentication_error` /
  `permission_error` / `rate_limit_error` / `api_error`. Branch on `code`.
- `param` — set when one field is at fault.
- `missing_required_params` carries a structured `params` array with `id`,
  `type`, `default`, `options`, `constraints` — self-correct in one
  round-trip without re-fetching the model.

Most common codes (full table in `references/api-docs.md`):

| HTTP | code                       | Meaning                                          |
| ---- | -------------------------- | ------------------------------------------------ |
| 400  | `missing_required_params`  | Required model params absent — see `params` hint |
| 400  | `invalid_payload`          | Bad body shape                                   |
| 401  | `invalid_token`            | Token missing / revoked / expired                |
| 402  | `token_daily_cap_exceeded` | This task's cost would breach the daily cap      |
| 404  | `unknown_model`            | Bogus `interfaceId` or disabled model            |
| 422  | `moderation_blocked`       | Text or image violates content policy            |
| 422  | `token_project_unbound`    | Bound project deleted — revoke + recreate token  |
| 429  | `rate_limited`             | Honor `Retry-After`                              |
| 503  | various                    | No enabled provider — try another model          |

## Transient errors

Up to 3 attempts with exponential backoff (1s → 3s → 9s), honor
`Retry-After`. Retry only: connection errors with no HTTP status, `5xx`,
`429`. Don't retry other `4xx`, `451 moderation_blocked`, or
`422 token_project_unbound`. Full retry table + outage-diagnostic curls:
`references/api-docs.md` → "Transient errors".

## Idempotency (optional)

Pass `Idempotency-Key: <opaque string ≤ 256 chars>` on `POST /v1/tasks`.
Server caches the key for 24h; repeat submits with the same `(token, key)`
return the original `taskId` plus `"idempotent": true`. Stripe semantics.

## Self-introspection (`GET /v1/me`)

Returns `{ key, project, user, limits }` — bound project, daily budget
(`creditsRemainingToday` when `dailyCreditCap` is set), account
`creditBalance`, current per-PAT rate-limit numbers. Use it for "do I have
headroom for this batch?" planning. If `project.bound == false` the bound
project was deleted — submits will fail with `token_project_unbound`. Full
schema: `references/api-docs.md` → `GET /v1/me`.

## Rate limits

Per-PAT, 60s sliding window. Headline: `tasks 60/min`, `quote 120/min`,
`uploads 30/min`, `me / upload-poll / ai-tools 120/min`, `describe-image
10/min`. `/models` and `/tasks/{id}` are unbounded. `429` carries
`Retry-After`. Full table: `references/api-docs.md` → "Limits".

## What this skill does NOT do

- It does **not** manage projects, canvases, or organizations — single-shot
  generation only. PAT's bound project is fixed at creation time.
- It does **not** stream progress — poll instead.
- It does **not** auto-download outputs; always **ask** first (step 7)
  and pick the save extension from response `content-type`.
- It does **not** allow uploads > 100 MB via the API — direct the user to
  the Web UI for those.
