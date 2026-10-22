# Deploy elsewhere

The images are plain OCI images and run on any container platform. This page covers the local trial with [`deploy/compose.yaml`](../deploy/compose.yaml), what any other platform must provide, and extending the images.

## Local trial with Docker Compose

`deploy/compose.yaml` runs Postgres 16, a one-off `migrate` container, `control` and `edge` on one machine. It runs no worker, so nothing is dispatched: the images refuse the local task runner in production mode, and worker tasks are meant for ECS. It is for trying the admin page, intake and enrichment, not for production.

```sh
cd deploy
head -c 32 /dev/urandom > kek
docker compose up
```

- `kek` is `control`'s key-encryption key (`R4C_KEK=file:/run/secrets/kek`), exactly 32 random bytes. It must be readable by uid 1000, the image's `node` user; on Linux, `chmod 644 kek` or `chown 1000 kek`. Keep it out of version control. Losing it makes every `local` value unreadable.
- `control` answers on `http://127.0.0.1:8080` (`/healthz`). The admin page stays off (`/admin` answers 404) until the `R4C_ADMIN_*` variables are set; see the [admin guide](admin-guide.md#enabling-it).
- `edge` answers on `http://127.0.0.1:8090/__r4c/`. It needs a host app's JWKS over HTTPS: set `R4C_APP_ID` and `R4C_HOST_JWKS_URL` before `docker compose up`, and register the same app in `control`:

  ```sh
  docker compose run --rm control --role=control host-app add --app-id "$R4C_APP_ID" --jwks-url "$R4C_HOST_JWKS_URL"
  ```

- Telemetry is off unless `OTEL_EXPORTER_OTLP_ENDPOINT` is set in your shell.
- The database password in the file is a local placeholder. Do not reuse the file as a production configuration.

## Any other platform

What request-4-change needs, wherever it runs:

| Need | Why |
|---|---|
| Postgres 16, reachable from `control` only | Requests, units, the queue, sessions and the append-only audit log |
| `control`, one or more replicas, with ports 8080 (public) and 8081 (internal) | The API, the admin page, webhooks and the queue steps on 8080; the workers' exchange on 8081, which must be reachable from workers and nothing else |
| `edge` next to each host app, on the same hostname, with `/__r4c/*` routed to it | The widget is loaded from, and posts to, the host app's own origin |
| A way for `control` to start one worker container per unit | Today that is ECS `RunTask` only (`R4C_TASK_RUNNER=ecs`) |
| Outbound HTTPS from `control` and the workers | GitHub, the model provider and, for `control`, your IdP |
| A key-encryption key | `R4C_KEK`: `kms:<key-arn>` on AWS, or `file:<path>` with a mounted 32-byte key from your secret store, never baked into an image |

Run migrations with `--role=control db migrate` before each start of a new version. `control` reads its secrets either from AWS Secrets Manager or SSM Parameter Store with its own credentials, or as `local` values it encrypts under the KEK; see the [admin guide](admin-guide.md#settings-and-secrets).

## Extending the images

[`deploy/extend/Dockerfile`](../deploy/extend/Dockerfile) builds `FROM` the published worker image by digest and adds your CA certificates, for example for a TLS-inspecting proxy or a GitHub Enterprise Server with a private CA (which also needs the worker's two GitHub URL variables, [deploy/README.md](../deploy/README.md#the-worker-task-definition)). Put each PEM certificate in `deploy/extend/certs/` as a file ending in `.crt`, build, push to your own registry, and point the worker task definition's `image` at the result.

Inside the worker, the added certificates reach:

- **git** (the clone and the push), which reads the system certificate store that `update-ca-certificates` rebuilds;
- **the worker's own requests** to `control` and the GitHub API, through `NODE_EXTRA_CA_CERTS`;
- **check commands** that read the system store, such as git or curl.

They do **not** reach the model step, or check commands that run on Node: each runs with a fixed allowlist of environment variables that excludes `NODE_EXTRA_CA_CERTS`, and Node does not read the system store by default.

The same pattern works for the server image (`FROM` `ghcr.io/foolswithtools/request-4-change-server@sha256:56e4d4327bb32003571d70cce66bdf89c5f35e2a0259da26776aee00f61a3cb4`), for example to give `control` your database's CA. The server image runs as the non-root `node` user, so switch to `USER root` for the install and back to `USER node` after it.

Loading Claude Code plugins and skills into worker sessions is not supported yet: the worker runs Claude Code in restricted mode with a fresh home directory for each round, and passes it no plugin directory.

Always rebuild on a new published digest when you upgrade.
