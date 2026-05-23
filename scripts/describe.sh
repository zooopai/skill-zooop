#!/usr/bin/env bash
# Describe a reference image — returns a structured prompt (subject,
# composition, style, lighting, palette, mood, camera + flowing
# overallDescription paragraph). Costs 1 credit per call; upstream failures
# auto-refund.
#
# Usage:  describe.sh <zooop-cdn-image-url>
# Example:
#   describe.sh https://storage.zooop.ai/<userId>/<projectId>/<uuid>.png
#
# Input MUST be a ZOOOP CDN URL. Pipe local files through upload.sh first.
set -euo pipefail

: "${ZOOOP_API_KEY:?ZOOOP_API_KEY must be set — visit https://zooop.ai/user#apiKeys to create one}"
HOST="${ZOOOP_API_HOST:-https://api.zooop.ai}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <zooop-cdn-image-url>" >&2
  exit 64
fi

URL="$1"
BODY=$(printf '{"imageUrl":"%s"}' "$URL")

curl -fsS -X POST "$HOST/v1/describe-image" \
  -H "Authorization: Bearer $ZOOOP_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY"
