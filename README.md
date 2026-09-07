# openseo-railway

Deployment files for running [OpenSEO](https://github.com/every-app/open-seo) —
the open-source alternative to Semrush and Ahrefs — on [Railway](https://railway.com).

Two services are built from this one repository:

| Service | Dockerfile | Public | What it is |
|---|---|---|---|
| `open-seo` | `Dockerfile` | no | Upstream's published self-host image with the client + worker bundle pre-built |
| `gateway` | `gateway/Dockerfile` | yes | Caddy, HTTP basic auth, the only route into the app |

The second service selects its Dockerfile with the `RAILWAY_DOCKERFILE_PATH`
environment variable, so both builds keep the repository root as their context.

## Why a gateway

OpenSEO's Docker self-host mode runs `AUTH_MODE=local_noauth`: no auth checks,
one injected admin user (`admin@localhost`). Upstream's own documentation says
to run it "behind your own auth-protected reverse proxy, tunnel, or private
network". The other two auth modes need an external identity provider —
`cloudflare_access` wants a Cloudflare Access team domain and audience tag,
`hosted` wants a Google OAuth client — and the app's startup preflight refuses
to boot without them, so neither is a default a template can ship.

The gateway is that reverse proxy. It holds the deployment's only credential,
derives the bcrypt hash from `GATEWAY_PASSWORD` at boot (Railway variables
cannot compute one), and serves an anonymous `/healthz` so Railway's prober
does not have to be let past the credential.

## Why the build is baked into the image

Upstream's `docker-entrypoint.sh` runs `vite build` at *container start*,
because vite inlines the `envPrefix`'d variables into the client bundle. That is
right for `docker compose`, where a container is created once, and wrong on
Railway, where every deployment creates a new one and the build would run inside
the health-check window. `Dockerfile` runs the build once, at image build time,
and writes the fingerprint file upstream's entrypoint checks — so a normal boot
skips straight to serving, while a deployer who changes one of the
build-relevant variables still gets the rebuild correctness requires.

## Variables

| Variable | Service | Default | Notes |
|---|---|---|---|
| `GATEWAY_PASSWORD` | gateway | none — required | The password you log in with |
| `GATEWAY_USERNAME` | gateway | `openseo` | |
| `GATEWAY_PASSWORD_HASH` | gateway | derived | Set a pre-computed bcrypt hash to keep the plaintext out of the environment |
| `OPENSEO_UPSTREAM` | gateway | `open-seo.railway.internal:3001` | |
| `PORT` | both | 8080 / 3001 | Railway sets this |
| `DATAFORSEO_API_KEY` | open-seo | unset | base64 of your DataForSEO `login:password`. Every SEO data feature is unavailable until it is set; the app boots and reports it on `/api/health` |
| `ALLOWED_HOST` | open-seo | `.up.railway.app` | Vite's preview server host allow-list. Set your own hostname when you attach a custom domain |
| `OPENROUTER_API_KEY` | open-seo | unset | Enables SAM, the in-app agent |
| `OPENROUTER_MODEL` | open-seo | unset | |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `BETTER_AUTH_SECRET` | open-seo | unset | All three together enable Google Search Console |
| `OPENSEO_TELEMETRY_DISABLED` | open-seo | unset | Set to `1` to turn off upstream's anonymous usage heartbeat |

`AUTH_MODE`, `VITE_SHOW_DEVTOOLS`, `CLOUDFLARE_INCLUDE_PROCESS_ENV`,
`NODE_OPTIONS`, `CI` and `WRANGLER_SEND_METRICS` are baked into the image;
changing `AUTH_MODE` or `VITE_SHOW_DEVTOOLS` triggers a rebuild at boot.

## State

The `open-seo` service needs a volume mounted at `/app/.wrangler`. Everything the
app owns lives there: the D1 (SQLite) database, both KV namespaces, the R2
bucket, the Durable Objects behind the chat agents, and Workflow state. Upstream
offers Postgres as a scale-out backend, but the app reaches it only through a
Cloudflare Hyperdrive binding and the other four stores stay on disk regardless,
so it would add a service without removing the volume.

## Licence

The deployment files here are MIT, matching upstream. OpenSEO itself is
copyright its authors — see [every-app/open-seo](https://github.com/every-app/open-seo).
