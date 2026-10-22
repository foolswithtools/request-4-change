# Observability

Every role emits vendor-neutral OpenTelemetry over OTLP/HTTP to an endpoint you configure, and nothing leaves the process when none is set.

## Settings

These are not secrets; they go in the task definitions and in `compose.yaml` as plain environment variables.

| Variable | Purpose | When unset |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP base URL. Traces go to `<base>/v1/traces`, metrics to `<base>/v1/metrics`. | Nothing is exported. There is no localhost default. |
| `OTEL_SDK_DISABLED` | `true` turns export off even with the endpoint set | Export follows the endpoint |
| `R4C_DEPLOYMENT_ENVIRONMENT` | The resource attribute `deployment.environment` | `unknown` |
| `R4C_INSTANCE` | The resource attribute `r4c.instance`: which installation this is | The host name (on Fargate, a task-specific name) |

No other variable sets the endpoint; the per-signal variables, such as `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, are ignored. Telemetry never stops a role from starting.

**Worker endpoint.** Worker tasks may only connect out on TCP 443 (and to `control`). A worker's endpoint must therefore be HTTPS on port 443, or a collector it reaches inside the VPC, for example one running beside `control`. An `http://…:4318` collector outside the VPC will not receive worker telemetry.

## Service names

| Process | `service.name` |
|---|---|
| server image, `--role=edge` | `request-4-change-edge` |
| server image, `--role=control` | `request-4-change-control` |
| worker image | `request-4-change-worker` |

Every span and metric carries `service.name`, `service.version` (the image's release version, also in each role's `/healthz` answer), `deployment.environment` and `r4c.instance`. The server's one-shot commands (`db migrate`, `host-app`, `config`, `audit`, `llm`) emit nothing.

## Traces

Each server role starts a `SERVER` span per request, named `<METHOD> <route pattern>`, for example `POST /__r4c/api/requests`, as a child of the caller's W3C `traceparent` when there is one. Spans carry the route pattern, never the URL, and an error adds its name and code, never its message. The widget sends a fresh sampled `traceparent` with each submit, and `edge` passes its own span on to `control`, so a widget request is one trace: the widget, then `edge`, then `control`.

`control` starts each worker task inside a `dispatch.unit` span (`r4c.unit_id`, `r4c.attempt`) and hands its trace context to the task as `TRACEPARENT`. The worker runs the whole unit inside one `worker.run` span with `r4c.unit.status`.

## Metrics

Two instruments, labelled `route`, `method`, `status_code` and `status_class` (`2xx` to `5xx`):

- `http_server_request_duration_seconds`: histogram, unit `s`, boundaries `0.05, 0.1, 0.2, 0.4, 0.8, 1, 2, 5`;
- `http_server_requests_total`: counter.

They are exported every 15 seconds, cumulative. The server flushes on `SIGTERM` or `SIGINT`; the worker flushes when its run ends. An unreachable endpoint can delay exit by about 8 seconds.

## Logs

Each role writes JSON lines on stdout at level `info`, with a `service` field, and `trace_id` and `span_id` inside a span. There are no per-request lines, because a URL can carry a value. Before a line is written, values under keys such as `authorization`, `token`, `secret`, `password`, `cookie` and `email` are replaced with `[REDACTED]`, at any depth and in the message, as are `Bearer <value>`, JWTs and GitHub tokens. Errors are written with their type, message and stack, all scrubbed.
