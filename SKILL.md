---
name: zooop
description: |
  Generate images, videos, and audio through the ZOOOP AI platform.
  Use when the user asks to "generate / create / make" an image, video, or
  voice clip, or wants to edit / upscale / remove background / lipsync /
  text-to-speech / clone-voice / generate music or sound effects.
---

# ZOOOP AI generation

Public REST API host: `https://api.zooop.ai` (override via `$ZOOOP_API_HOST`
in scripts; all `curl` examples below assume this default).
Auth: `Authorization: Bearer $ZOOOP_API_KEY` on every request.

If `scripts/*.sh` aren't present locally (e.g. this SKILL.md was read
standalone without cloning the bundle), the inline `curl` recipes in
each section work the same way. Or `git clone https://github.com/zooopai/skill-zooop`
to get the full bundle.

## One-time setup (first run only)

If `ZOOOP_API_KEY` is unset, instruct the user:

1. Visit https://zooop.ai/user#apiKeys → click **Create token**.
2. Pick a **project** the token will be bound to (required — the token
   cannot be re-bound later; create a new token for a different project).
3. Optionally set a **daily credit cap** (recommended for safety).
4. Copy the token (shown ONCE — they cannot recover it later).
5. Run: `export ZOOOP_API_KEY=zpk_live_...`

Credits are charged against the user's existing ZOOOP balance. Every task
the agent submits, and every file it uploads, lands under the PAT's bound
project — so the user sees them in that project's history page and storage
breakdown.

## How model selection works

The user usually hints which kind of task they want, optionally a specific
model. Match it to one (type, subType) pair from the table below, list the
matching models, then pick.

| type   | subType            | What it does                                 |
| ------ | ------------------ | -------------------------------------------- |
| image  | default            | Text-to-image / image-to-image generation    |
| image  | edit-image         | Targeted image edit with mask                |
| video  | text-ref           | Text-to-video                                |
| video  | motion-control     | Image-to-video with motion direction         |
| video  | first-last-frame   | Generate video between two keyframes         |
| video  | audio-lipsync      | Sync a video to an audio track               |
| video  | extend-video       | Extend an existing video                     |
| video  | video-edit         | Edit / restyle an existing video             |
| audio  | text-to-speech     | TTS in a named voice                         |
| audio  | voice-clone        | Clone a voice from a reference sample        |
| audio  | sound-effect       | Generate one-shot sound effect from text     |
| audio  | music              | Generate a music track from text             |

A model can have multiple versions ("standard" / "pro" / "fast") at
different price tiers — `versions` in the model row lists each version's
`id` and `name`. Pricing is enforced server-side at submit time and
reflected in the task's `creditsCharged` field after completion; agents
don't see per-call price ahead of time. Use `GET /v1/me` for budget
planning (`creditsRemainingToday`, `user.creditBalance`).

## Standard workflow

1. **(Optional, first call only) Self-check.** `GET /v1/me` tells the
   agent its remaining daily budget, account balance, bound project name,
   and current rate limits — useful for "do I have headroom for this
   batch?" planning. Skip if cost is uncertain; the submit itself enforces
   limits authoritatively.

2. **Discover models** for the matching subtype:
   ```bash
   curl -fsS "$ZOOOP_API_HOST/v1/models?type=video&subtype=motion-control" \
        -H "Authorization: Bearer $ZOOOP_API_KEY"
   ```
   Match the user's hint (e.g. "用 seedance2") against `name` / `brand.name` /
   `brand.id`. If the user gave **no hint**, follow the default model rules
   below — these are admin-curated and reflect ZOOOP's recommended picks
   for each category.

3. **(Optional) Upload local files.** If the user gave a path on disk:
   ```bash
   bash scripts/upload.sh /path/to/file.png
   # → prints the final URL to use in params (image_url / video_url / audio_url).
   ```
   The script wraps `POST /v1/uploads`. For images and audio it returns
   immediately (sync, Aliyun image moderation runs inline). For video it
   polls the moderation workflow until terminal (typical 5-30s, up to
   30 min). On block, it exits non-zero — the user's content was rejected.

4. **Submit the task** — pick a model `id`, one of its `versions[].id`, and
   fill `params` per the model's `params` schema:
   ```bash
   bash scripts/submit.sh <interfaceId> <versionId> '<params-json>'
   # → { "taskId": "...", "status": "queued", "modelId": "...", "versionId": "..." }
   ```

5. **Poll until terminal.** Blocks until `succeeded` / `failed` / `cancelled`:
   ```bash
   bash scripts/poll.sh <taskId>
   # → { "status": "succeeded", "outputs": [{"url": "..."}], "creditsCharged": 4 }
   ```

6. **Show the user the result URL.** Don't auto-download large videos.

## Default model selection

When the user's request is vague ("generate me an image of X", "make a
video of Y") and does NOT name a specific model, brand, or quality tier,
pick the defaults below. These are ZOOOP's curated picks; do not deviate
unless the user explicitly asks for something else.

### Images (`type=image, subtype=default`)

- Default model: **GPT Image 2.0**.
- Default params: `quality: "low"`, `resolution: "2k"`, `aspect_ratio: "1:1"`.
- **If the user says the result quality is not good enough**, re-submit
  with `quality: "medium"` on the same model. Do NOT switch model on a
  quality complaint — GPT Image 2's tiered quality is the right knob.
- Only switch model if the user explicitly asks (e.g. "use Flux" /
  "用 Seedream").

### Videos (`type=video, subtype=text-ref`)

Pick from the table below based on the user's quality / cost signal.
For ambiguous requests, default to the **"Balanced"** row.

| User signal | Pick |
| --- | --- |
| "highest quality" / "best" / "电影级" | **Seedance 2** |
| Balanced (default — no explicit signal) | **Kling O3** → fallback to **Kling V3** → **Happy Horse** → **Grok Imagine** (in this order; pick the first one available in `/v1/models`) |
| "cheap" / "fastest" / "性价比" / "便宜" | **Grok Imagine** |

Match by `name` (case-insensitive substring) or `brand.name` against the
`/v1/models` response.

### Other categories

For `audio/*`, `image/edit-image`, and all other video subtypes
(`motion-control`, `first-last-frame`, `audio-lipsync`, `extend-video`,
`video-edit`), use **`models[0]`** from `/v1/models` — the response is
pre-sorted, so the first row is the recommended default.

### How to find a named model by `name`

The model `id` is a UUID and varies per deployment, so never hard-code it.
Instead:

```bash
MODELS=$(curl -fsS "$ZOOOP_API_HOST/v1/models?type=image&subtype=default" \
              -H "Authorization: Bearer $ZOOOP_API_KEY")
IID=$(echo "$MODELS" | jq -r '.models[] | select(.name | ascii_downcase | contains("gpt image 2")) | .id' | head -1)
VID=$(echo "$MODELS" | jq -r '.models[] | select(.id=="'"$IID"'") | .versions[0].id')
```

## Endpoints (reference)

| Method | Path                          | What                                              |
| ------ | ----------------------------- | ------------------------------------------------- |
| GET    | `/v1/me`                      | Self-introspection: key info, project, balance, limits |
| GET    | `/v1/models`                  | List public models by `type` × `subtype`          |
| POST   | `/v1/tasks`                   | Submit a generation; returns `taskId`             |
| GET    | `/v1/tasks/{id}`              | Poll task status / outputs                        |
| POST   | `/v1/uploads`                 | Upload a file (raw body + `Content-Type`)         |
| GET    | `/v1/uploads/{uploadId}`      | Poll async (video) upload moderation status       |

For the full request / response shapes, query params, error codes, and
rate-limit numbers, see [`references/api-docs.md`](./references/api-docs.md).
That file is the canonical REST API reference — read it when this guide
doesn't cover a specific field.

## Reading a model's params schema

Each model in `GET /models` has a `params: InterfaceParam[]` array. Each entry has:

- `id` — the key to set in `params` at submit time
- `type` — one of `image_url`, `image_urls`, `video_url`, `audio_url`, `voice`,
  `aspect_ratio`, `resolution`, `duration`, `boolean`, `enum`, `text`,
  `long_text`, `float`, `first_frame`, `last_frame`, `mask_url`, ...
- `required` — whether the user must supply it
- `options` — allowed values for `enum` / `aspect_ratio` / `resolution`
- `constraints` — `min` / `max` / `maxLength` etc.
- `default` — fallback when the user omits it

Some params have media-URL types (`image_url`, `video_url`, etc.). For those
the value MUST be a ZOOOP-hosted URL — pass the file through `upload.sh` first
if the user gave a local path or a foreign URL.

## Uploads — single-step raw-body

```bash
curl -X POST "$ZOOOP_API_HOST/v1/uploads" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: image/png" \
  --data-binary "@$HOME/Desktop/cat.png"
```

The `Content-Type` header drives the moderation path AND the resulting file
extension — pass the file's REAL mime, not a guess.

**Image / audio** (sync, < 1s typical):
```json
{ "status": "ready", "url": "https://storage.zooop.ai/.../<uuid>.png",
  "size": 12345, "contentType": "image/png" }
```

**Video** (async, returns immediately — `uploadId` is a plain UUID):
```json
{ "status": "processing",
  "uploadId": "<uuid>", "pollUrl": "/v1/uploads/<uuid>" }
```

Then poll:
```bash
curl -fsS "$ZOOOP_API_HOST/v1/uploads/$UPLOAD_ID" \
  -H "Authorization: Bearer $ZOOOP_API_KEY"
```
Returns `{ "status": "processing" }` (202), `{ "status": "ready", "url": ... }` (200),
`{ "status": "blocked", "labels": "...", "error": "..." }`, or `{ "status": "errored" }`.

Allowed Content-Type values:
- `image/png`, `image/jpeg`, `image/webp`, `image/gif`
- `audio/mpeg`, `audio/wav`, `audio/webm`, `audio/ogg`
- `video/mp4`, `video/webm`, `video/quicktime`

Size cap 100 MB. For larger files, instruct the user to upload via the Web UI
and copy the resulting URL.

## Error response shape

Errors follow the OpenAI-style envelope:

```json
{
  "error": {
    "message": "Missing required parameters: aspect_ratio, resolution",
    "type": "invalid_request_error",
    "code": "missing_required_params",
    "params": [
      { "id": "aspect_ratio", "type": "aspect_ratio", "required": true,
        "options": [{"value": "1:1", "label": "1:1"}, ...], "default": "1:1" },
      { "id": "resolution", "type": "resolution", "required": true,
        "options": [...], "default": "1024" }
    ]
  }
}
```

- `error.type` — broad family: `invalid_request_error` / `authentication_error` /
  `permission_error` / `rate_limit_error` / `api_error`. Branch on `code` for
  fine-grained handling.
- `error.param` is set when the failure points at a single body / query field.
- For `missing_required_params`, `error.params` is an array of structured
  hints — each entry tells the agent what to send (type / valid options /
  default / numeric bounds), so self-correction works in one round-trip
  without re-fetching the model.

| HTTP | code                       | Meaning                                    |
| ---- | -------------------------- | ------------------------------------------ |
| 400  | `invalid_payload`          | Missing required input or bad shape        |
| 400  | `missing_required_params`  | Required model params absent — see `params` array for valid options |
| 400  | `missing_category`         | `/v1/models` called without `type` / `subtype` |
| 400  | `unknown_category`         | `(type, subtype)` not exposed              |
| 400  | `invalid_idempotency_key`  | `Idempotency-Key` header malformed         |
| 401  | `missing_token`            | No `Authorization` header                  |
| 401  | `invalid_token`            | Token wrong, revoked, or expired           |
| 402  | `arrears`                  | Account balance went negative — top up     |
| 402  | `token_daily_cap_exceeded` | This task's cost would breach token's daily cap |
| 403  | `model_not_public`         | Model exists but not in public API surface |
| 403  | `account_banned`           | The token's user is banned                 |
| 404  | `unknown_model`            | Bogus `interfaceId` or disabled model      |
| 404  | `unknown_task`             | `/tasks/{id}` for a task this token can't see |
| 404  | `unknown_upload`           | `/uploads/{id}` for an upload this token doesn't own |
| 413  | `file_too_large`           | Upload body > 100 MB                       |
| 422  | `moderation_blocked`       | Text prompt or input violates content policy (text mod) |
| 422  | `token_project_unbound`    | PAT's bound project was deleted — revoke + recreate |
| 429  | `rate_limited`             | Backoff per `Retry-After`                  |
| 429  | `token_daily_cap_reached`  | Token's daily credit ceiling was hit (pre-check, before pricing) |
| 451  | `moderation_blocked`       | Uploaded image was blocked by content moderation |
| 502  | `storage_upload_failed`    | R2 PUT failed during upload — retry        |
| 503  | `moderation_unavailable`   | Moderation worker unreachable — retry briefly |
| 503  | various                    | No enabled provider — try another model     |

For any 5xx other than 503, retry once with a short delay; otherwise surface
the error to the user.

## Transient errors — don't give up on the first failure

The Internet is messy: even when the API is healthy, a single request can
fail for reasons that have nothing to do with the API. Before concluding
"the API is down" or "the user needs a VPN," **retry**.

**Retry these (transient, usually self-heals within seconds):**

- TCP / TLS / connection errors with no HTTP status (`SSL_ERROR_SYSCALL`,
  `Connection reset`, `ECONNRESET`, `EAI_AGAIN`, curl exit codes 6 / 7 / 35 /
  52 / 56)
- HTTP `502` / `503` / `504` (gateway / overload)
- HTTP `429` — wait for `Retry-After` seconds, then retry
- Cloudflare-specific `520` – `526` (edge couldn't reach origin)

**Do NOT retry these (permanent — fix or surface to user):**

- All other `4xx`: the request itself is wrong (auth, validation, missing
  resource). Retrying won't help.
- `451 moderation_blocked` on uploads: the content was rejected. Retrying
  the same bytes will be rejected again.
- `422 token_project_unbound`: the PAT's project is gone. Tell the user
  to revoke and recreate the token.

**Recommended retry pattern:** up to 3 attempts, exponential backoff
(1s → 3s → 9s), honoring `Retry-After` when present. If all 3 fail, then
surface the error.

**Diagnostic sanity check before declaring an outage:** if your retries
all fail with the same TCP/TLS error, verify the network path before
blaming the API:

```bash
curl -fsS -o /dev/null -w "%{http_code}\n" https://zooop.ai      # main site healthy?
curl -fsS -o /dev/null -w "%{http_code}\n" https://api.zooop.ai/llms.txt
```

If `zooop.ai` is up but `api.zooop.ai` keeps failing, only THEN report
to the user; otherwise it's almost always local network or transient.

## Idempotency (optional)

Pass an `Idempotency-Key: <opaque string ≤ 256 chars>` header on `POST /tasks`
to safely retry a submit without creating duplicate tasks. Server stores the
key for **24 hours**; repeat submits with the same `(token, key)` return the
original `taskId` plus `"idempotent": true`. Useful when network failures
might cause double-clicks. Stripe-style semantics.

```bash
curl -X POST "$ZOOOP_API_HOST/v1/tasks" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{"interfaceId":"...","versionId":"...","params":{...}}'
```

## Self-introspection (`GET /v1/me`)

```bash
curl -fsS "$ZOOOP_API_HOST/v1/me" \
  -H "Authorization: Bearer $ZOOOP_API_KEY"
```

Response:
```json
{
  "key": {
    "id": "...", "prefix": "zpk_live_...", "label": "claude-code-mac",
    "createdAt": "...", "expiresAt": null,
    "dailyCreditCap": 1000,
    "creditsSpentToday": 42,
    "creditsRemainingToday": 958
  },
  "project": { "id": "...", "name": "My Project" },
  "user":    { "creditBalance": 84495 },
  "limits":  { "tasksPerMin": 60, "uploadsPerMin": 30, "uploadPollPerMin": 120 }
}
```

Use cases:
- "Do I have headroom for this 100-task batch?" → check `creditsRemainingToday`
  (when `dailyCreditCap` is non-null) AND `user.creditBalance`
- "Where will my tasks show up?" → `project.name`
- "When does this token expire?" → `expiresAt`
- "What's the max submit rate?" → `limits.tasksPerMin`

If `project.bound` comes back as `false`, the bound project was deleted —
all task / upload submits will fail with `token_project_unbound` until the
user revokes this token and creates a new one.

## Rate limits

Per-PAT, 60-second sliding window:

| Endpoint                     | Default limit |
| ---------------------------- | ------------- |
| `POST /v1/tasks`             | 60 / min      |
| `POST /v1/uploads`           | 30 / min      |
| `GET /v1/uploads/{id}`       | 120 / min     |
| `GET /v1/me`                 | 120 / min     |
| `GET /v1/models`             | (unbounded)   |
| `GET /v1/tasks/{id}`         | (unbounded)   |

429 responses carry `Retry-After` in seconds — honor it before retrying.

## What this skill does NOT do

- It does **not** manage projects, canvases, or organizations — the public
  API exposes single-shot generation only. The PAT's bound project is
  chosen at creation time and is immutable.
- It does **not** stream progress — poll instead.
- It does **not** download outputs. Decide downstream whether to fetch URLs.
- It does **not** allow uploads > 100 MB via the API — direct the user to
  the Web UI for those.
