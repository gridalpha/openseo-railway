#!/bin/sh
# Container entrypoint for OpenSEO on Railway. It follows upstream's
# docker-entrypoint.sh step for step; every difference below is Railway's.
set -e

: "${PORT:=3001}"

# Vite's preview server refuses a request whose Host is not in preview.allowedHosts
# (built from ALLOWED_HOST in vite.config.ts). A leading dot allows a domain and
# every subdomain of it, so this default covers any generated Railway domain
# without a ${{gateway.RAILWAY_PUBLIC_DOMAIN}} reference — which would render
# empty on a first-ever template deploy and 403 every request. Override it with
# your own hostname when you attach a custom domain.
: "${ALLOWED_HOST:=.up.railway.app}"

# Exposes the Railway variables to the cloudflare:workers bindings the app reads
# its config through; wrangler is non-interactive here and phones home otherwise.
CLOUDFLARE_INCLUDE_PROCESS_ENV=true
CI=true
WRANGLER_SEND_METRICS=false
export PORT ALLOWED_HOST CLOUDFLARE_INCLUDE_PROCESS_ENV CI WRANGLER_SEND_METRICS

# The volume is mounted here. miniflare keeps D1, KV, R2, the Durable Objects
# behind the chat agents and Workflow state under it, and creates the tree
# itself — Railway's own lost+found beside it is never enumerated.
mkdir -p /app/.wrangler

echo "[railway] OpenSEO: AUTH_MODE=${AUTH_MODE:-unset} PORT=$PORT ALLOWED_HOST=$ALLOWED_HOST"

# Validates the environment before the slow steps, and exits non-zero on a hard
# failure (an unknown AUTH_MODE, or auth config missing for the selected mode).
# A missing DATAFORSEO_API_KEY is a warning, not a failure: the app boots and
# says so on /api/health.
pnpm exec tsx scripts/selfhost-preflight.ts

pnpm run db:migrate:local

# Upstream's build-reuse fingerprint. The Dockerfile already wrote it, so a
# normal boot prints "reusing" and serves in seconds; a deployer who sets one of
# these variables gets the rebuild that correctness then requires.
FP_FILE=dist/.openseo-build-env
FINGERPRINT="$(env | grep -E '^(VITE_|AUTH_MODE|BYPASS_EMAIL_VERIFICATION|POSTHOG_PUBLIC_KEY|POSTHOG_HOST|TURNSTILE_SITE_KEY|POSTHOG_SOURCEMAPS)' | sort | sha256sum | cut -d' ' -f1)"
test -n "$FINGERPRINT"

if [ -f "$FP_FILE" ] && [ "$(cat "$FP_FILE")" = "$FINGERPRINT" ]; then
  echo "[railway] reusing the bundle baked into the image."
else
  echo "[railway] build-relevant environment differs from the image — rebuilding, this takes several minutes."
  rm -f "$FP_FILE"
  pnpm exec vite build
  printf '%s' "$FINGERPRINT" > "$FP_FILE"
fi

# Bind [::] rather than upstream's 0.0.0.0: Railway routes IPv6 between
# services, and the gateway reaches this one over the private network. Node
# leaves IPV6_V6ONLY unset, so the same socket still answers the IPv4 prober.
exec pnpm exec vite preview --host :: --port "$PORT"
