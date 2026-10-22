# Deploy on ECS

This page runs request-4-change on Amazon ECS on Fargate, in the shape request-4-change is built for: one load balancer, `control` as one service per installation, `edge` as a sidecar inside each host app's own task, and one worker task per unit of work. The example files are in [`deploy/ecs/`](../deploy/ecs/).

## The shape

| Piece | Runs as | Reached by |
|---|---|---|
| `control` | One ECS service of `deploy/ecs/control-service.json`, behind the load balancer at its own hostname, for example `r4c.example.com` | Browsers (the admin page), `edge`, GitHub webhooks on port 8080; workers on its internal port 8081, inside the VPC only |
| `edge` | A sidecar container inside the host app's task, from `deploy/ecs/edge-sidecar.json` | The load balancer, for `/__r4c/*` on the host app's hostname |
| worker | One task of `deploy/ecs/worker-task.json` per unit, started by `control` with `RunTask` | Nobody: it has no inbound rules and only connects out |
| Postgres 16 | For example Amazon RDS, in private subnets | `control` only |

`edge` runs **inside the host app's task**, not in front of it. The host app keeps its own target group and listener rule; a second target group for the sidecar's port and a listener rule that matches the host app's hostname **and** the path `/__r4c/*`, at a higher priority than the host-only rule, send the widget's traffic to `edge`. The host app must not serve anything under that prefix. Its health check is `/__r4c/healthz`, since `edge` answers 404 at `/healthz`.

## 1. Network

- **Load balancer.** An internet-facing ALB with HTTPS listeners for the host app's hostname and `control`'s.
- **control's security group.** Ingress on 8080 from the load balancer, and on 8081 from the workers' security group only. Give `control` a private DNS name the workers can resolve, for example with an ECS Service Connect or Cloud Map namespace, and use it in `R4C_CONTROL_INTERNAL_URL` (`http://control.internal.example.com:8081` in the example).
- **The workers' security group.** No ingress rules. Egress on TCP 443 (through a NAT gateway, to GitHub and Bedrock) and on TCP 8081 to `control`'s security group. Nothing else. Rule 443 does not restrict destinations by domain; see [Security model](security-model.md#worker-egress).
- **Private subnets** for `control`, the workers and the database. `R4C_WORKER_SUBNET_IDS` lists the workers' subnets.

## 2. Database and key

- Postgres 16 that `control` can reach on 5432. Put the host and database name in `DATABASE_URL` without credentials, and inject RDS's managed master secret whole as `R4C_DATABASE_CREDENTIALS`: `control` merges its username and password into the URL. Node does not trust RDS's certificate authority by default, so either use `sslmode=no-verify` (encrypted, server not verified) as the example does, or add the RDS CA bundle to the image (see [Deploy elsewhere](deploy-elsewhere.md#extending-the-images)) and verify.
- A KMS key for `control`'s key-encryption key, `R4C_KEK=kms:<key-arn>`. Keep the value spelled exactly the same for the life of the installation; see the [admin guide](admin-guide.md#settings-and-secrets).

## 3. IAM roles

Four roles, each trusted by `ecs-tasks.amazonaws.com` only. The published images are public on GHCR, so pulling them needs no registry credentials.

| Role | Allows |
|---|---|
| control task role | `kms:Decrypt` and `kms:GenerateDataKey` on the KEK; `secretsmanager:GetSecretValue` and `ssm:GetParameter` on the secrets and parameters its settings point at; `bedrock:InvokeModel` on the configured inference profile and its models; `ecs:RunTask` of `task-definition/r4c-worker:*` with the condition `ecs:cluster` equal to your cluster; `ecs:TagResource` on tasks with `ecs:CreateAction` = `RunTask`; `iam:PassRole` of the two worker roles, with `iam:PassedToService` = `ecs-tasks.amazonaws.com` |
| control execution role | Log writes, and `secretsmanager:GetSecretValue` on the database credentials secret it injects |
| worker task role | `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on the configured inference profile and its models, and nothing else. Claude Code streams each turn, so the streaming action is required. |
| worker execution role | Log writes only, plus pulls from your registry if you run an [extended image](deploy-elsewhere.md#extending-the-images) there. A worker task gets no injected secrets. |

## 4. Register the task definitions

Replace every `<placeholder>` and `example.com` value, then:

```sh
aws ecs register-task-definition --cli-input-json file://deploy/ecs/control-service.json
aws ecs register-task-definition --cli-input-json file://deploy/ecs/worker-task.json
```

Add the container in `deploy/ecs/edge-sidecar.json` to the `containerDefinitions` of your host app's task definition, and register that. The sidecar listens on 8090 because host app containers often use 8080; tasks share one network namespace, so the ports must differ.

Keep the worker's family `r4c-worker` and its container name `worker`: `control` starts that family and overrides that container. Leave `R4C_UNIT_ID`, `R4C_NONCE`, `R4C_CONTROL_INTERNAL_URL` and `TRACEPARENT` out of it; `control` sets them at `RunTask` ([deploy/README.md](../deploy/README.md#the-worker-task-definition)).

## 5. Migrate, then start control

Before the first start and before each upgrade, run a one-off task of `control`'s task definition with the command overridden to `["--role=control", "db", "migrate"]`. It applies the image's migrations and exits 0. Then create or update the `control` service (target group on 8080, health check `/healthz`).

## 6. Register the host app

`control` accepts requester assertions only from registered host apps. Run a one-off task of `control`'s task definition with the command:

```sh
--role=control host-app add --app-id example-app --jwks-url https://app.example.com/.well-known/jwks.json
```

The app id must equal the sidecar's `R4C_APP_ID` and the `app_id` claim the host app signs. Give each host app its own signing keys.

## 7. Configure on the admin page

Sign in at `https://r4c.example.com/admin` and set the model, the GitHub App and the target repositories. The [admin guide](admin-guide.md) lists every key. Dispatch stays idle until they are set.

## Upgrading

Change the image digest in all three task definitions together: `edge` and `control` come from the same server image and speak the same contract. Run the migrations first, then update the `control` service, then the host apps.
