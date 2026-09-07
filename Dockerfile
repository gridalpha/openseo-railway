# OpenSEO on Railway.
#
# Upstream's published self-host image (Dockerfile.selfhost) carries the source
# and node_modules but no build output: docker-entrypoint.sh runs `vite build`
# at container start, because vite inlines the envPrefix'd variables into the
# client bundle. On Railway that build would sit inside the health-check window
# of every single deployment, so it is done once here instead — the two
# variables it bakes in are fixed for this deployment shape.
FROM ghcr.io/every-app/open-seo:latest

# local_noauth is the only self-host auth mode that needs no external identity
# provider: cloudflare_access (the app's own default) wants a Cloudflare Access
# team domain and audience tag, and hosted wants a Google OAuth client — the
# preflight fails the boot without them. It leaves the app with no auth of its
# own, which is why the Caddy gateway in gateway/ owns the public domain.
ENV AUTH_MODE=local_noauth \
    VITE_SHOW_DEVTOOLS=false \
    CLOUDFLARE_INCLUDE_PROCESS_ENV=true \
    CI=true \
    WRANGLER_SEND_METRICS=false \
    NODE_OPTIONS=--max-old-space-size=4096

WORKDIR /app

# `pnpm run build` is `vite build && tsc --noEmit`. The type check is a
# contributor gate; running it here would let an upstream type error break every
# deploy of this image for no runtime benefit.
#
# The fingerprint file is upstream's: docker-entrypoint.sh reuses an existing
# build when the build-relevant environment still hashes to what produced it, so
# writing it here is what lets railway-entrypoint.sh skip straight to serving.
RUN pnpm exec vite build \
 && FP="$(env | grep -E '^(VITE_|AUTH_MODE|BYPASS_EMAIL_VERIFICATION|POSTHOG_PUBLIC_KEY|POSTHOG_HOST|TURNSTILE_SITE_KEY|POSTHOG_SOURCEMAPS)' | sort | sha256sum | cut -d' ' -f1)" \
 && printf '%s' "$FP" > dist/.openseo-build-env \
 && test -s dist/.openseo-build-env

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN sh -n /usr/local/bin/railway-entrypoint.sh

CMD ["sh", "/usr/local/bin/railway-entrypoint.sh"]
