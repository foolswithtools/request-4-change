# Deploy examples

Example files for running the published request-4-change images. Every image reference in them is pinned by digest, never a tag. No Dockerfile that builds request-4-change from source is published here; `extend/` only layers on top of a published image.

| Path | What it is |
|---|---|
| [`ecs/control-service.json`](ecs/control-service.json) | ECS task definition for `control`: run it as one service per installation behind a load balancer |
| [`ecs/edge-sidecar.json`](ecs/edge-sidecar.json) | The `edge` container definition to add to your host app's own task definition, as a sidecar |
| [`ecs/worker-task.json`](ecs/worker-task.json) | ECS task definition for the worker: `control` starts one task of it per unit, with `RunTask`; it is never a service |
| [`ecs/egress-proxy-task.json`](ecs/egress-proxy-task.json) | ECS task definition for the egress proxy: the worker image with the entrypoint `node /app/egress-proxy.cjs`, run as one service with no load balancer, which worker tasks must go through to reach the internet |
| [`compose.yaml`](compose.yaml) | Docker Compose for a local trial: Postgres 16, the migrations, `control` and `edge` |
| [`extend/Dockerfile`](extend/Dockerfile) | Builds `FROM` the published worker image and adds your CA certificates and skills for worker sessions |

Values in angle brackets, such as `<account-id>` and `<region>`, and every `example.com` hostname are placeholders. [Deploy on ECS](../docs/deploy-ecs.md) walks through the ECS files and [Deploy elsewhere](../docs/deploy-elsewhere.md) through the rest.

## The worker task definition

`control` starts worker tasks of the family `r4c-worker` and overrides the container named `worker`, so keep both names. The container's command is `run`. At `RunTask`, `control` sets four variables in that override. They are set by `control`, never by you, so leave them out of the task definition:

| Variable | What it carries |
|---|---|
| `R4C_UNIT_ID` | The unit of work this task runs |
| `R4C_NONCE` | A single-use value, valid for 5 minutes, that the worker trades with `control` for its repository token and its unit. No token is ever put in the override. |
| `R4C_CONTROL_INTERNAL_URL` | `control`'s internal listener, as `control` itself is configured |
| `TRACEPARENT` | The W3C trace context of `control`'s dispatch span, so the worker's spans join the trace |

Set `R4C_EGRESS_PROXY_URL` in the task definition, never in an override, to the egress proxy's `http://<host>:<port>`. The worker then sends the model step, the checks and git through it, keeping loopback direct, and opens its pull request through it. Any other form makes the worker exit 2. Do not set `NODE_USE_ENV_PROXY`: the worker calls `control` and the task credential endpoint directly on purpose.

Leave the container's `user` unset, so the worker starts as root, the image's default. It needs root to start the model step and the checks as a user of their own; see the [security model](../docs/security-model.md#the-model-step).

Two worker variables are yours to set, and only for GitHub Enterprise Server. Workers do not read `control`'s `connector.github.api_url`, so they must match it:

| Variable | Default | Meaning |
|---|---|---|
| `R4C_GITHUB_API_URL` | `https://api.github.com` | Where the worker opens its pull request: the same API URL as `connector.github.api_url` |
| `R4C_GIT_BASE_URL` | `https://github.com/` | The prefix of the clone and push URL, `<base><owner>/<repo>.git`, ending in `/` |

## Telemetry in the examples

Each example sets `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SDK_DISABLED`, `R4C_DEPLOYMENT_ENVIRONMENT` and `R4C_INSTANCE`. With the endpoint unset or empty, nothing is exported. The worker's endpoint must be a collector inside the VPC that its security group allows: the OTLP exporter does not use the egress proxy, and the workers' group should reach nothing else on the internet. See [Observability](../docs/observability.md).
