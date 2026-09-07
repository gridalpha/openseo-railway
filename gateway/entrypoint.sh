#!/bin/sh
# The Caddyfile reads every {$VAR} from this process's environment when the
# config is adapted, so nothing here renders a file. This script exists for the
# one value a Railway variable cannot express: bcrypt has no template function,
# so the hash is derived at boot from the plaintext password the deployer set.
set -eu

: "${PORT:=8080}"
: "${GATEWAY_USERNAME:=openseo}"

# A ${{open-seo.RAILWAY_PRIVATE_DOMAIN}} reference renders as an empty string
# until that service owns a deployment, which is exactly the state a template's
# first deploy is in — so the variable arrives set, and set to a bare ":3001"
# that Caddy would bake as its upstream. Repair it on the value's shape rather
# than only on the variable being unset.
case "${OPENSEO_UPSTREAM:-}" in
  "" | ":"*) OPENSEO_UPSTREAM=open-seo.railway.internal:3001 ;;
esac

if [ -z "${GATEWAY_PASSWORD_HASH:-}" ]; then
  if [ -z "${GATEWAY_PASSWORD:-}" ]; then
    echo "[gateway] GATEWAY_PASSWORD is not set, and no pre-computed" >&2
    echo "[gateway] GATEWAY_PASSWORD_HASH was supplied. Refusing to start:" >&2
    echo "[gateway] this gateway is the only thing authenticating OpenSEO." >&2
    exit 1
  fi
  # --plaintext is the only scriptable form: reading the password from stdin
  # works from a terminal only, and returns an empty hash otherwise.
  GATEWAY_PASSWORD_HASH="$(caddy hash-password --plaintext "$GATEWAY_PASSWORD")"
fi

unset GATEWAY_PASSWORD
export PORT GATEWAY_USERNAME GATEWAY_PASSWORD_HASH OPENSEO_UPSTREAM

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
echo "[gateway] :$PORT -> $OPENSEO_UPSTREAM, basic auth as '$GATEWAY_USERNAME'"
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
