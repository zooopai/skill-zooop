#!/usr/bin/env bash
# Submit one Zooop AI task. Prints the JSON response from POST /v1/tasks.
#
# Two modes:
#   submit.sh <interfaceId> <versionId> '<params-json>'
#   submit.sh --ai-tool <slug>          '<params-json>'
#
# Examples:
#   submit.sh d2c0... pro '{"prompt":"a red panda eating noodles","aspect_ratio":"1:1"}'
#   submit.sh --ai-tool background-removal '{"image_url":"https://storage.zooop.ai/…"}'
#
# Discover identifiers via:
#   GET /v1/models?type=<type>&subtype=<subType>     (raw path)
#   GET /v1/ai-tools[?type=image|video]              (curated tools)
set -euo pipefail

: "${ZOOOP_API_KEY:?ZOOOP_API_KEY must be set — visit https://zooop.ai/user#apiKeys to create one}"
HOST="${ZOOOP_API_HOST:-https://api.zooop.ai}"

if [[ ${1:-} == "--ai-tool" ]]; then
  if [[ $# -lt 3 ]]; then
    echo "usage: $0 --ai-tool <slug> <params-json>" >&2
    exit 64
  fi
  SLUG="$2"
  PARAMS="$3"
  BODY=$(printf '{"aiTool":"%s","params":%s}' "$SLUG" "$PARAMS")
else
  if [[ $# -lt 3 ]]; then
    echo "usage: $0 <interfaceId> <versionId> <params-json>" >&2
    echo "       $0 --ai-tool <slug> <params-json>" >&2
    exit 64
  fi
  INTERFACE_ID="$1"
  VERSION_ID="$2"
  PARAMS="$3"
  # interfaceId / versionId are caller-supplied identifiers; we wrap them in
  # JSON quotes via printf %s, so embedded quotes in the caller's input would
  # break the JSON — that's a caller mistake, not a security issue (the auth
  # header already gates request submission).
  BODY=$(printf '{"interfaceId":"%s","versionId":"%s","params":%s}' "$INTERFACE_ID" "$VERSION_ID" "$PARAMS")
fi

curl -fsS -X POST "$HOST/v1/tasks" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY"
