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

`scripts/{upload,quote,submit,poll}.sh` ship with this skill. Inline `curl`
recipes below work the same way if the bundle isn't cloned. Full request /
response / error reference: [`references/api-docs.md`](./references/api-docs.md)
— read it whenever this guide doesn't cover a field.

## API key — setup, rotation, removal

**The token must NEVER appear in the agent conversation.** This skill runs
across multiple agent runtimes (Claude Code, Codex, Cursor, …) with
different retention / training / log policies. A token pasted into chat
can land in training corpora, telemetry, or shared transcripts — and
once leaked, it can spend the user's credits until they revoke it.
Always have the **user** set the env var themselves, in their own
terminal.

Agent: check whether the key is already set (e.g. `echo $ZOOOP_API_KEY`
or the OS-equivalent). If empty, give the user these instructions
**verbatim** — do not ask them to paste the token back to you:

1. Visit https://zooop.ai/user#apiKeys → **Create token**.
2. Pick the project to bind it to (immutable). **Set a daily credit cap**
   — caps the blast radius if the token ever leaks.
3. Copy the token (shown ONCE).
4. In their **own terminal** (NOT this chat) run the line matching their OS:
   - macOS / Linux / WSL / Git Bash —
     `echo 'export ZOOOP_API_KEY=zpk_live_…' >> ~/.zshrc && source ~/.zshrc`
     (use `~/.bashrc` if their shell is bash, not zsh)
   - Windows PowerShell —
     `[Environment]::SetEnvironmentVariable('ZOOOP_API_KEY','zpk_live_…','User')`
   - Windows cmd — `setx ZOOOP_API_KEY "zpk_live_…"`
5. **Restart the agent** so the new env var is inherited.

**Rotation**: revoke the old token at /user#apiKeys → create a new one →
user re-runs step 4 with the new value → restart agent.
**Removal**: revoke at /user#apiKeys → user deletes the same env-var
setting from the same place.

Credits are charged against the user's existing ZOOOP balance. Every task
and every upload lands under the PAT's bound project — visible in that
project's history page and storage breakdown.

## How model selection works

Match the user's intent to one (type, subType) pair, list the matching
models, then pick.

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
   download it to a local file?"* — on yes, save to Desktop with the
   extension picked from the response `content-type`:

   ```bash
   URL=$(echo "$RESULT_JSON" | jq -r '.outputs[0].url')
   CT=$(curl -sI "$URL" | awk 'tolower($1)=="content-type:" {print $2}' | tr -d '\r')
   EXT=$(case "$CT" in image/png) echo png;; image/jpeg) echo jpg;;
                       image/*) echo "${CT#image/}";; video/mp4) echo mp4;;
                       audio/*) echo "${CT#audio/}";; *) echo bin;; esac)
   curl -fL -o "$HOME/Desktop/zooop-$(date +%Y%m%d-%H%M%S).$EXT" "$URL"
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

- Default model: **GPT Image 2.0** with `quality: "low"`, `resolution: "2k"`,
  `aspect_ratio: "1:1"`. ~80% of cases are fine at `low`; `medium` handles
  ~95% of needs.
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

For `audio/*`, `image/edit-image`, and all other video subtypes
(`motion-control`, `first-last-frame`, `audio-lipsync`, `extend-video`,
`video-edit`), use **`models[0]`** from `/v1/models` — pre-sorted, first row
is the recommended default.

## Endpoints

| Method | Path                       | What                                       |
| ------ | -------------------------- | ------------------------------------------ |
| GET    | `/v1/me`                   | Self-introspection                         |
| GET    | `/v1/models`               | List public models by `type` × `subtype`   |
| POST   | `/v1/quote`                | Price a task (no side effects)             |
| POST   | `/v1/tasks`                | Submit a generation                        |
| GET    | `/v1/tasks/{id}`           | Poll status / outputs                      |
| POST   | `/v1/uploads`              | Upload a file (raw body + `Content-Type`)  |
| GET    | `/v1/uploads/{uploadId}`   | Poll async (video) upload moderation       |

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

## Transient errors — don't give up on the first failure

A single request can fail for reasons that have nothing to do with the API.
Retry before declaring an outage.

**Retry (transient, usually self-heals):** TCP / TLS errors with no HTTP
status (`ECONNRESET`, `EAI_AGAIN`, curl exit codes 6 / 7 / 35 / 52 / 56);
HTTP `502` / `503` / `504`; HTTP `429` (honor `Retry-After`); Cloudflare
`520`–`526`.

**Do NOT retry:** other `4xx` (auth / validation — retry won't help);
`451 moderation_blocked` (same bytes get rejected again);
`422 token_project_unbound` (rotate the token).

**Pattern:** up to 3 attempts, exponential backoff (1s → 3s → 9s), honor
`Retry-After`. If all 3 fail, surface the error.

**Diagnostic before declaring outage:**

```bash
curl -fsS -o /dev/null -w "%{http_code}\n" https://zooop.ai
curl -fsS -o /dev/null -w "%{http_code}\n" https://api.zooop.ai/llms.txt
```

If `zooop.ai` is up but `api.zooop.ai` keeps failing, only THEN report;
otherwise it's almost always local network or transient.

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
`uploads 30/min`, `me / upload-poll 120/min`. `/models` and `/tasks/{id}`
are unbounded. `429` carries `Retry-After`. Full table:
`references/api-docs.md` → "Limits".

## What this skill does NOT do

- It does **not** manage projects, canvases, or organizations — single-shot
  generation only. PAT's bound project is fixed at creation time.
- It does **not** stream progress — poll instead.
- It does **not** auto-download outputs; always **ask** first (step 7)
  and pick the save extension from response `content-type`.
- It does **not** allow uploads > 100 MB via the API — direct the user to
  the Web UI for those.
