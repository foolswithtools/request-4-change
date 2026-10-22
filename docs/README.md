# request-4-change docs

| Page | What it covers |
|---|---|
| [Deploy on ECS](deploy-ecs.md) | Running the images on Amazon ECS: control as a service, edge as a sidecar inside the host app's task, workers as one task per unit |
| [Deploy elsewhere](deploy-elsewhere.md) | The local trial with `deploy/compose.yaml`, other container platforms, and extending the images |
| [Widget contract v1](widget-contract/v1.md) | How a host app embeds the request widget and what it sends |
| [Admin guide](admin-guide.md) | The admin page, every setting control reads, and what each one does |
| [Security model](security-model.md) | Trust boundaries, credentials, and what each image can reach, including the worker's egress limits |
| [Observability](observability.md) | Traces, metrics and logs: the telemetry settings and service names |

## How it fits together

1. A person files a bug or a feature request from the widget in a host app. The widget posts to `/__r4c/api/requests` on the host app's own domain; the load balancer sends that path to the `edge` sidecar.
2. `edge` checks the host-signed requester assertion and forwards the request to `control`.
3. `control` classifies and enriches the request with the configured model, decomposes it into units sized for one worker session each, and files a parent issue and one child issue per unit in the system of record (GitHub Issues).
4. A product owner approves the request in the system of record.
5. `control` starts one `worker` task per approved unit. The worker clones the target repository, runs Claude Code with a restricted tool list, runs the unit's checks, pushes a branch and opens a pull request.
6. CI results on that pull request feed back to `control`: a failure starts a new round (at most three), after which the unit is rescoped or escalated to a person.
7. A person reviews and merges the pull request. request-4-change never merges and never deploys.
