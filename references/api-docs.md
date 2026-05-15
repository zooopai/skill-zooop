# ZOOOP Public REST API (v1)

## Quick start

```bash
# 1. Create a Personal Access Token at https://zooop.ai/user#apiKeys
export ZOOOP_API_KEY=zpk_live_...

# (Quote every URL: zsh treats `?` as a glob and `&` as a job separator.)

# 2. Discover models for the kind of task you want
curl -fsS -H "Authorization: Bearer $ZOOOP_API_KEY" \
  "https://api.zooop.ai/v1/models?type=image&subtype=default"

# 3. Submit a task with one of the model ids + a version id
curl -fsS -X POST -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"interfaceId":"<uuid>","versionId":"standard","params":{"prompt":"a red panda"}}' \
  "https://api.zooop.ai/v1/tasks"

# 4. Poll for the result
curl -fsS -H "Authorization: Bearer $ZOOOP_API_KEY" \
  "https://api.zooop.ai/v1/tasks/<taskId>"
```

## Authentication

All endpoints require `Authorization: Bearer <PAT>`. Tokens look like
`zpk_live_<32 chars>` and are created at <https://zooop.ai/user#apiKeys>. The
plaintext is shown ONCE at creation; afterwards only the leading prefix is
visible in the settings UI. To rotate, create a new token and revoke the old
one (revocation is immediate).

The token's user owns every task it submits and every file it uploads.
Credits are debited from that user's personal balance.

**Project binding**: every PAT is bound to one project at creation time and
cannot be re-bound. Tasks submitted via the PAT land under that project;
uploaded files do too. If the bound project is later deleted, all submits
return 422 `token_project_unbound` — the user must revoke + recreate. See
`GET /v1/me` for the bound project info.

## Error envelope

All errors follow an OpenAI-style envelope so SDKs that parse that shape work
out of the box:

```json
{
  "error": {
    "message": "Missing required parameters: aspect_ratio, resolution",
    "type": "invalid_request_error",
    "code": "missing_required_params",
    "params": [
      {
        "id": "aspect_ratio", "type": "aspect_ratio", "required": true,
        "default": "1:1",
        "options": [{"value": "1:1", "label": "1:1"}, {"value": "16:9", "label": "16:9"}]
      },
      {
        "id": "resolution", "type": "resolution", "required": true,
        "default": "1024",
        "options": [{"value": "1024", "label": "1024 × 1024"}, ...]
      }
    ]
  }
}
```

- `type` — broad family: `invalid_request_error`, `authentication_error`,
  `permission_error`, `rate_limit_error`, `api_error`.
- `code` — stable machine-readable reason. Branch on this in client code.
- `param` — set when the failure points at a single body / query field.
- Free-form extras (`validCategories`, `spent`, `cap`, `params`, `labels`, …)
  live under `error` too and are stable for any documented `code`.
- For `missing_required_params`, the `params` array carries structured hints
  per missing field (`id` / `type` / `required` / `default` / `options` /
  `constraints`) — agents can self-correct in one round-trip without
  re-fetching the model.

Per-endpoint error tables below.

## Endpoints

### `GET /v1/me`

PAT self-introspection. Returns everything the calling agent needs to plan
its requests without trial-and-error 429s / 402s — bound project, daily
credit headroom, account balance, current rate-limit numbers.

```bash
curl -fsS -H "Authorization: Bearer $ZOOOP_API_KEY" \
  "https://api.zooop.ai/v1/me"
```

Response:

```json
{
  "key": {
    "id": "uuid",
    "prefix": "zpk_live_aBcD…",
    "label": "claude-code-mac",
    "createdAt": "2026-05-15T10:00:00.000Z",
    "expiresAt": null,
    "dailyCreditCap": 1000,
    "creditsSpentToday": 42,
    "creditsRemainingToday": 958
  },
  "project": { "id": "uuid", "name": "My Project" },
  "user":    { "creditBalance": 84495 },
  "limits":  {
    "tasksPerMin": 60,
    "uploadsPerMin": 30,
    "uploadPollPerMin": 120
  }
}
```

Field notes:
- `key.dailyCreditCap` is `null` when no cap is set; `creditsRemainingToday`
  is also `null` in that case.
- `key.expiresAt` is `null` when the token never expires. Warn the user to
  renew before this date.
- `project.id` / `project.name` are both `null` (with `project.bound: false`)
  when the bound project was deleted — submits will fail with
  `token_project_unbound` until the token is rotated.
- `user.creditBalance` is the account-level wallet that funds tasks. Even
  with `creditsRemainingToday > 0`, an empty wallet still blocks expensive
  submits.
- `limits.*` reflect the current per-PAT rate-limit numbers. Honor them.

All PATs grant full access to every `/v1/*` endpoint.

Privacy: deliberately omits `user.id / email / name` (PAT bearer doesn't
need user identity — the token itself is the identity) and never enumerates
other PATs of the same user.

### `GET /v1/models?type=<type>&subtype=<subType>`

Lists the enabled model interfaces that match one `(type, subType)` pair.
Both query params are **required** — calling without them returns 400 plus
the full set of valid `(type, subType)` pairs so the caller can self-correct.

Exposure rule: a `(type, subType)` pair is exposed via the public API iff
the corresponding generator tool is currently in the homepage sidebar. The
single source of truth is `src/lib/seo/tool-pages-seo.ts` (`inSidebar: true`).

Response shape:

```json
{
  "models": [
    {
      "id": "uuid",
      "name": "Flux Pro",
      "type": "image",
      "subType": "default",
      "description": "Photorealistic text-to-image model …",
      "brand": { "id": "flux", "name": "Black Forest Labs", "logo": "https://..." },
      "promptRequired": true,
      "promptMaxLength": 2000,
      "params": [
        { "id": "prompt", "type": "long_text", "required": true, "maxLength": 2000 },
        { "id": "aspect_ratio", "type": "aspect_ratio", "required": false, "enumValues": ["1:1","16:9","9:16"] }
      ],
      "versions": [
        { "id": "standard", "name": "Standard" },
        { "id": "pro",      "name": "Pro" }
      ],
      "tags": ["HOT"]
    }
  ]
}
```

### Public categories

| type   | subType            | Tool                            |
| ------ | ------------------ | ------------------------------- |
| image  | default            | Image generator                 |
| image  | edit-image         | Image editor                    |
| video  | text-ref           | Video generator                 |
| video  | motion-control     | Motion control (image-to-video) |
| video  | first-last-frame   | First / last frame video        |
| video  | audio-lipsync      | Lip sync                        |
| video  | extend-video       | Extend video                    |
| video  | video-edit         | Video editor                    |
| audio  | text-to-speech     | Text-to-speech                  |
| audio  | voice-clone        | Voice clone                     |
| audio  | sound-effect       | Sound effect                    |
| audio  | music              | Music generation                |

### `POST /v1/tasks`

Submit one generation task by model id.

Body:

```json
{
  "interfaceId": "<uuid from /models>",
  "versionId": "standard",
  "params": { "prompt": "…", "image_url": "…", "duration": 5 }
}
```

The keys allowed in `params` come from the model's `params[]` spec returned
by `/models`. Param values are validated server-side via the same path the
web `/api/ai/execute` route uses.

**Optional header** `Idempotency-Key: <≤256 chars>` — repeat submissions
with the same `(token, key)` within 24 hours return the original `taskId`
plus `"idempotent": true` instead of creating a duplicate. Stripe semantics.

Response:

```json
{ "taskId": "uuid", "status": "queued", "modelId": "...", "versionId": "..." }
```

Errors:

| HTTP | code                       | Cause                                       |
| ---- | -------------------------- | ------------------------------------------- |
| 400  | `invalid_payload`          | Missing required input or bad shape         |
| 400  | `missing_required_params`  | Model `required: true` params absent; `error.params` lists each with type / options / default |
| 400  | `invalid_idempotency_key`  | `Idempotency-Key` header missing or > 256 chars |
| 401  | `missing_token` / `invalid_token` | Missing or revoked / expired PAT     |
| 402  | `arrears`                  | Account in arrears                          |
| 402  | `token_daily_cap_exceeded` | This task's cost would breach the token's daily cap (post-pricing precise check) |
| 403  | `model_not_public`         | Model exists but isn't on the public API surface |
| 403  | `account_banned`           | Token's owner is banned                     |
| 404  | `unknown_model`            | Bogus `interfaceId` or disabled model       |
| 422  | `moderation_blocked`       | Text prompt failed content moderation       |
| 422  | `token_project_unbound`    | PAT's bound project was deleted — revoke + recreate |
| 429  | `rate_limited`             | Per-token rate-limit ceiling (default 60 req/min) |
| 429  | `token_daily_cap_reached`  | Token's `dailyCreditCap` already met before this call (coarse pre-check) |
| 503  | various                    | No enabled provider — pick a different model |

### `GET /v1/tasks/{id}`

Returns the current state of a task. Path-id is the `taskId` from submit.

```json
{
  "taskId": "uuid",
  "status": "succeeded",
  "outputs": [{ "url": "https://...", "thumbnailUrl": "https://..." }],
  "error": null,
  "creditsCharged": 4,
  "createdAt": "2026-05-14T01:23:45.000Z",
  "completedAt": "2026-05-14T01:24:12.000Z"
}
```

Public `status` values: `queued | running | succeeded | failed | cancelled`.
Internal granular states (`pending`, `processing`, `uploading`, `moderating`)
are collapsed into `running` since they're not actionable for agents.

### `POST /v1/uploads`

Upload a local file in a single request. The file content is the raw HTTP
body (NOT multipart). `Content-Type` selects the media type. Returns a
public URL ready to feed into a subsequent `/tasks` submission.

```bash
curl -X POST \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: image/png" \
  --data-binary @cat.png \
  https://api.zooop.ai/v1/uploads
```

The upload lands under the PAT's bound project (same path as Web UI uploads),
so it shows up in the "Uploads" tab of the in-app history picker and counts
toward your storage quota.

**Image / audio — synchronous response** (typically < 1s):

```json
{
  "status": "ready",
  "url": "https://storage.zooop.ai/<userId>/<projectId>/<uuid>.png",
  "size": 123456,
  "contentType": "image/png"
}
```

**Video — asynchronous via Aliyun video moderation**. Returns `202` with an
upload id:

```json
{
  "status": "processing",
  "uploadId": "<uuid>",
  "pollUrl": "/v1/uploads/<uuid>"
}
```

Poll `GET /v1/uploads/{uploadId}` until you get a terminal status.
Recommended cadence: 5s first poll, then 10–20s. Most clips resolve in
under a minute; the workflow has a 30-minute deadline.

**Image moderation block** (image content violates the policy):

```json
{
  "error": {
    "message": "Uploaded content violates content policy",
    "type": "invalid_request_error",
    "code": "moderation_blocked",
    "labels": "porn"
  }
}
```
HTTP 451.

**Allowed Content-Type values**: `image/png`, `image/jpeg`, `image/webp`,
`image/gif`, `audio/mpeg`, `audio/wav`, `audio/webm`, `audio/ogg`,
`video/mp4`, `video/webm`, `video/quicktime`. Off-list values return 400
with the allowlist in the response.

**Size cap**: 100 MB (Cloudflare request-body limit). If you need to upload
something larger, use the Web UI then pass that URL to `/tasks`.

### `GET /v1/uploads/{uploadId}`

Poll the status of an async (video) upload returned by `POST /v1/uploads`.

```bash
curl -H "Authorization: Bearer $ZOOOP_API_KEY" \
  https://api.zooop.ai/v1/uploads/<uuid>
```

Response shapes:

```json
{ "status": "processing" }                                    # 202, still moderating
{ "status": "ready",   "url": "...", "contentType": "..." }   # 200, ready to use
{ "status": "blocked", "labels": "porn", "error": "..." }     # 200, rejected
{ "status": "errored", "reason": "..." }                       # 200, workflow gave up
```

Ownership: the upload id can only be polled by the PAT that created it.
Other tokens (even from the same user account) get 404 `unknown_upload`.

## Limits

- **Rate limit** (per PAT, 60-second sliding window):
  - `POST /v1/tasks` — 60 req/min
  - `POST /v1/uploads` — 30 req/min
  - `GET /v1/uploads/{id}` — 120 req/min
  - `GET /v1/me` — 120 req/min
  - `GET /v1/models`, `GET /v1/tasks/{id}` — unbounded
  - 429 responses carry `Retry-After` (seconds).
- **Tokens per user**: max 10 active. Revoke an old one to create a new one.
- **Daily credit cap (optional)**: per token; UTC-midnight rollover. Two
  enforcement points — coarse pre-check (`token_daily_cap_reached`, 429)
  and precise post-pricing check (`token_daily_cap_exceeded`, 402,
  prevents over-cap submission even when current spend < cap).
- **Concurrency**: per-user `maxConcurrency` (default 3) caps how many
  PAT-submitted tasks run in parallel — excess queues in FIFO order and
  drains as earlier tasks complete. Rate-limit and concurrency are
  orthogonal: you can submit 60/min but only 3 will execute at once.
- **Content moderation**: identical to web — Aliyun text moderation runs
  before credit deduction; AIGC image outputs are moderated post-generation;
  uploaded images are moderated synchronously on `POST /v1/uploads`;
  uploaded videos are moderated asynchronously via the poll route.
- **Upload size**: 100 MB hard ceiling per file (Cloudflare request-body
  limit). Larger files: use the Web UI and pass the URL.

## Out of scope

- **Team / organization workspaces**: PATs are personal-only.
- **Project management**: PATs are bound to one project at creation. To
  switch projects, revoke and create a new token.
- **Canvases / story timeline**: the API exposes single-shot generation only.
- **Streaming progress**: poll instead.
- **Listing tasks / uploads**: no `/tasks?since=` or `/uploads?since=`
  endpoints — track task IDs client-side.
