#!/usr/bin/env bash
# Quote a Zooop AI task without submitting. Prints the JSON response from
# POST /v1/quote — returns exact credits + ETA seconds with no side effects.
#
# Usage:  quote.sh <interfaceId> <versionId> '<params-json>'
# Example:
#   quote.sh d2c0... pro '{"prompt":"a red panda eating noodles","aspect_ratio":"1:1"}'
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

# Same body shape as submit.sh; the API enforces identical schema.
BODY=$(printf '{"interfaceId":"%s","versionId":"%s","params":%s}' "$INTERFACE_ID" "$VERSION_ID" "$PARAMS")

curl -fsS -X POST "$HOST/v1/quote" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY"
