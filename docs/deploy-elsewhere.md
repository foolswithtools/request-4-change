# Deploy elsewhere

The images are plain OCI images and run on any container platform. This page covers the local trial with [`deploy/compose.yaml`](../deploy/compose.yaml), what any other platform must provide, and extending the images.

## Local trial with Docker Compose

`deploy/compose.yaml` runs Postgres 16, a one-off `migrate` container, `control` and `edge` on one machine. It runs no worker, so nothing is dispatched: the images refuse the local task runner in production mode, and worker tasks are meant for ECS. It is for trying the admin page, intake and enrichment, not for production.

```sh
cd deploy
head -c 32 /dev/urandom > kek
docker compose up
```

- `kek` is `control`'s key-encryption key (`R4C_KEK=file:/run/secrets/kek`), exactly 32 random bytes. It must be readable by uid 1000, the image's `node` user; on Linux, `chown 1000 kek && chmod 600 kek`, or `chmod 644 kek` on a host no one else uses. Keep it out of version control. Losing it makes every `local` value unreadable.
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

[`deploy/extend/Dockerfile`](../deploy/extend/Dockerfile) builds `FROM` the published worker image by digest and adds your CA certificates and Claude Code skills for worker sessions. CA certificates are for example for a TLS-inspecting proxy, a model endpoint behind a private CA, or a GitHub Enterprise Server with a private CA (which also needs the worker's two GitHub URL variables, [deploy/README.md](../deploy/README.md#the-worker-task-definition)). Put each PEM certificate in `deploy/extend/certs/` as a file ending in `.crt`, put your skills in `deploy/extend/plugins/` (below), build, push to your own registry, and point the worker task definition's `image` at the result.

Keep the worker starting as root: add no `USER` line to a derived worker image, and leave the container's `user` unset in its task definition. Running the worker as root is what lets it start the model step and the checks as a user of their own. A worker started as an ordinary user, which can look like hardening, runs every child as that user and loses the separation described in the [security model](security-model.md#the-model-step).

Inside the worker, the added certificates reach:

- **git** (the clone and the push), which reads the system certificate store that `update-ca-certificates` rebuilds;
- **the worker's own requests** to `control` and the GitHub API, through `NODE_EXTRA_CA_CERTS`;
- **the model step** (Claude Code, and so its calls to the model provider), through `NODE_EXTRA_CA_CERTS`;
- **check commands** that read the system store, such as git or curl.

The worker passes `NODE_EXTRA_CA_CERTS` to the model step only when it names a file that root owns and no one else can write, as `/etc/ssl/certs/ca-certificates.crt` in the example is; otherwise the model step runs without it. The certificates do **not** reach check commands that run on Node: the checks run with a fixed allowlist of environment variables that excludes `NODE_EXTRA_CA_CERTS`, and Node does not read the system store by default.

The same pattern works for the server image (`FROM` `ghcr.io/foolswithtools/request-4-change-server@sha256:7c07f83fd9e32ec13a4b5b02301230bd922da517a8d6a1a1bced5dc38633f50d`), for example to give `control` your database's CA. The server image runs as the non-root `node` user, so switch to `USER root` for the install and back to `USER node` after it.

### Skills for worker sessions

The worker loads each Claude Code plugin in `/opt/r4c/plugins`, when the image has it, and gives the model step the `Skill` tool, so the model can use the skills they carry. The example Dockerfile copies `deploy/extend/plugins/` there; `plugins/example` holds one example skill to replace with your own. Each directory in `plugins/` is one plugin:

```
plugins/<plugin>/.claude-plugin/plugin.json      {"name": "<plugin>", "version": "...", "description": "..."}
plugins/<plugin>/skills/<skill>/SKILL.md         frontmatter with name and description, then the instructions
```

The model sees a skill as `<plugin>:<skill>`. A plugin may carry **skills only**, because anything else a plugin can carry would run with the model step's access to the model provider:

- every entry in `plugins/` is a directory with its `.claude-plugin/plugin.json`, named with lower-case letters, digits, `-` and `_` only, and not named like a part of a plugin (`skills`, `commands`, `agents`, `hooks`, `workflows` and the like);
- `plugin.json` may hold only `$schema`, `name`, `version`, `description`, `author`, `homepage`, `repository`, `license` and `keywords`;
- next to it, only `skills/` and documentation files such as `README.md`, `LICENSE` or `NOTICE.txt`: no hooks, MCP or LSP servers, agents, commands, settings or `bin/`;
- a skill's frontmatter must be YAML whose top-level keys are only `name`, `description`, `license` and `metadata` (so no `hooks`, `mcpServers`, `allowed-tools`, `context` or `model`), with no YAML tags, anchors or aliases; what the values say is up to you, Markdown and the word "hooks" included. Save a skill with LF or CRLF line ends, not CR alone. A skill may not use `` !`command` `` (or a ```` ```! ```` block) to run a shell command when it loads;
- no symlinks, and nothing the worker's `agent` user could write: keep the example's `COPY` without `--chown`, and its `chmod`.

If `/opt/r4c/plugins` breaks any of these rules, every unit fails with `The plugin directory /opt/r4c/plugins is refused:` and the reason, before the worker clones anything. The worker never loads part of the directory.

The model step's file tools stay confined to the repository being changed, so the model cannot open a skill's other files: put everything a skill needs in its `SKILL.md`. Every unit gets every skill in the image; choosing skills per installation on the admin page is not available yet.

Always rebuild on a new published digest when you upgrade.
