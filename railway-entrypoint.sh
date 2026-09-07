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
# a leading-dot form of your own hostname when you attach a custom domain.
: "${ALLOWED_HOST:=.railway.app}"

# vite.config.ts adds a *second* allowed host: the hostname of BETTER_AUTH_URL.
# Railway's health prober is anonymous and sends "Host: healthcheck.railway.app",
# which no deployer-chosen ALLOWED_HOST would cover — the probe is then answered
# 403 and the deployment sits in HEALTHCHECK for its whole window while the app
# serves normally. Claiming that slot keeps the probe working whatever
# ALLOWED_HOST is set to. The value is inert otherwise: auth.ts reads
# BETTER_AUTH_URL only in hosted mode, and hardcodes a placeholder base URL here.
: "${BETTER_AUTH_URL:=https://healthcheck.railway.app}"
export BETTER_AUTH_URL

# Exposes the Railway variables to the cloudflare:workers bindings the app reads
# its config through; wrangler is non-interactive here and phones home otherwise.
CLOUDFLARE_INCLUDE_PROCESS_ENV=true
CI=true
WRANGLER_SEND_METRICS=false
export PORT ALLOWED_HOST CLOUDFLARE_INCLUDE_PROCESS_ENV CI WRANGLER_SEND_METRICS

# The volume is mounted at /data, NOT at /app/.wrangler. `vite build` writes
# .wrangler/deploy/config.json, which the Cloudflare vite plugin reads when the
# preview server starts, and a volume mounted over that directory hides it —
# the container then crash-loops on "ENOENT: /app/.wrangler/deploy/config.json"
# behind a SUCCESS deployment. Only the state tree is mutable, so link that one
# directory across and leave the rest of .wrangler in the image layer.
#
# miniflare keeps D1, both KV namespaces, R2, the Durable Objects behind the
# chat agents, and Workflow state under it, and creates the tree itself.
STATE_ROOT="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"
mkdir -p "$STATE_ROOT/state" /app/.wrangler
[ -L /app/.wrangler/state ] || rm -rf /app/.wrangler/state
ln -sfn "$STATE_ROOT/state" /app/.wrangler/state
echo "[railway] miniflare state -> $(readlink /app/.wrangler/state)"

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
