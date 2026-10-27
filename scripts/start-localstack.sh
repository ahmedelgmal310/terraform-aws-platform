#!/usr/bin/env bash
# Starts LocalStack Community and waits until the services the tests use are
# ready. The image is passed in pinned by digest (LOCALSTACK_IMAGE).
set -euo pipefail

: "${LOCALSTACK_IMAGE:?set LOCALSTACK_IMAGE}"
SERVICES="${LOCALSTACK_SERVICES:-s3,sts,iam,kms,ec2,logs,dynamodb}"

docker run -d --name localstack \
  -p 127.0.0.1:4566:4566 \
  -e SERVICES="$SERVICES" \
  -e EAGER_SERVICE_LOADING=1 \
  "$LOCALSTACK_IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if health="$(curl -fsS http://localhost:4566/_localstack/health 2>/dev/null)"; then
    pending="$(echo "$health" | jq -r --arg s "$SERVICES" '
      ($s | split(",")) as $want
      | [.services | to_entries[] | select(.key as $k | $want | index($k)) | select(.value != "running" and .value != "available")]
      | length')"
    if [ "$pending" = "0" ]; then
      echo "LocalStack ready: $(echo "$health" | jq -c '{version, services: (.services | with_entries(select(.value == "running" or .value == "available")) | keys)}')"
      exit 0
    fi
  fi
  sleep 2
done

echo "LocalStack did not become ready" >&2
docker logs localstack >&2 || true
exit 1
