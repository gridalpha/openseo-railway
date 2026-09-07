# HTTP basic-auth gateway in front of OpenSEO.
#
# OpenSEO's Docker self-host mode runs with AUTH_MODE=local_noauth — no auth
# checks and a single injected admin user — and upstream's own docs say to put
# it behind an auth-protected reverse proxy. This is that proxy. It owns the
# only public domain in the project; OpenSEO itself stays on the private network.
#
# Built from the same repository as the app: the service sets
# RAILWAY_DOCKERFILE_PATH=gateway/Dockerfile, and the build context stays the
# repo root, so the COPY paths below are repo-relative.
FROM caddy:2-alpine

COPY gateway/Caddyfile /etc/caddy/Caddyfile
COPY gateway/entrypoint.sh /usr/local/bin/gateway-entrypoint.sh

# Adapting the config provisions basic_auth, which parses the hash — so the
# check needs a real throwaway one rather than a placeholder it would reject.
# This also asserts that the caddy binary the entrypoint shells out to exists.
RUN sh -n /usr/local/bin/gateway-entrypoint.sh \
 && GATEWAY_PASSWORD_HASH="$(caddy hash-password --plaintext throwaway)" \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

CMD ["sh", "/usr/local/bin/gateway-entrypoint.sh"]
