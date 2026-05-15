#!/usr/bin/env bash
# Submit one Zooop AI task. Prints the JSON response from POST /v1/tasks.
#
# Usage:  submit.sh <interfaceId> <versionId> '<params-json>'
# Example:
#   submit.sh d2c0... pro '{"prompt":"a red panda eating noodles","aspect_ratio":"1:1"}'
#
# Discover the interfaceId + versionId via:
#   GET /v1/models?type=<type>&subtype=<subType>
set -euo pipefail

: "${ZOOOP_API_KEY:?ZOOOP_API_KEY must be set — visit https://zooop.ai/user#apiKeys to create one}"
HOST="${ZOOOP_API_HOST:-https://api.zooop.ai}"

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <interfaceId> <versionId> <params-json>" >&2
  exit 64
fi

INTERFACE_ID="$1"
VERSION_ID="$2"
PARAMS="$3"

# Build the request body. interfaceId / versionId are caller-supplied
# identifiers; we wrap them in JSON quotes via printf %s, so embedded quotes
# in the caller's input would break the JSON — that's a caller mistake, not a
# security issue (the auth header already gates request submission).
BODY=$(printf '{"interfaceId":"%s","versionId":"%s","params":%s}' "$INTERFACE_ID" "$VERSION_ID" "$PARAMS")

curl -fsS -X POST "$HOST/v1/tasks" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY"
