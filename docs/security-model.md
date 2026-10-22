# Security model

What each part of request-4-change holds, whom it trusts and what it can reach. The images carry a bundled build whose contents anyone can inspect; nothing here depends on the code being secret.

## Roles and what they hold

| Part | Holds | Trusts |
|---|---|---|
| `edge` (sidecar in the host app's task) | No secret. Its settings are the host app's id, the URL of the host's public JWKS, and where `control` is. | Nothing: it checks every requester assertion itself |
| `control` (one service per installation) | Every secret: the GitHub App's private key and webhook secret, the admin IdP's client secret, the database credentials, and the KEK that seals `local` values | Requester assertions only after checking them again itself, whatever `edge` said |
| worker (one task per unit) | Nothing at start. It trades a single-use nonce for one short-lived token scoped to one repository | `control`'s internal listener |

## Requester identity

A host app signs a short-lived JWT for the signed-in user (`sub`, `email`, `roles`, `app_id`, and `exp` at most 5 minutes ahead), with RS256 or ES256 and a `kid` from the JWKS it publishes over HTTPS. The widget sends it as a bearer token and never in a URL. `edge` checks it before forwarding anything, and `control` checks it again from scratch against the registered host app's JWKS before it touches the database, so a call that skips `edge` faces the same checks. Identity comes only from the token: identity fields in a request body are dropped. Any failure answers 401 `invalid_assertion`; the reason goes to the role's log only.

Two registered host apps that share a JWKS accept each other's tokens, so give each one its own keys.

## The admin page

Only `control` serves `/admin`; `edge` answers 404. Sign-in is OIDC with PKCE against your IdP, and every page and API call checks the group named by `R4C_ADMIN_ROLE`. Sessions last 8 hours and are never extended. Every write must carry the exact `Origin` of `R4C_ADMIN_BASE_URL`. The page shows a secret only as `********` and can replace one, never show it. Sign-ins, refusals and every configuration change are written to the append-only audit log, never with a value. `control` rate-limits the admin routes per client itself; behind a load balancer, set `R4C_TRUSTED_PROXIES` so a client is counted under its own address ([admin guide](admin-guide.md#limits)).

## Repository credentials

- `control` holds the GitHub App key and mints installation tokens itself.
- A worker's token is scoped to **one repository** with exactly `contents: write`, `pull_requests: write` and `checks: read`, and expires within an hour. `control` refuses a token GitHub returns with any other repository, permission or a longer life, and every worker token is audited (`token.mint`).
- No token travels in the `RunTask` request, whose overrides anyone with `ecs:DescribeTasks` can read. The task gets a nonce instead: 32 random bytes, stored only as a hash, single-use, valid for 5 minutes, exchanged once over `control`'s internal listener for the token, the unit and a session key for the worker's report.
- `control` dispatches only to a repository whose default branch requires status checks.
- The worker never merges and never deploys. It pushes one branch without force and opens one pull request; a person merges it.

## The model step

The worker runs Claude Code with a restricted tool list (`Read`, `Edit`, `Write`, `Glob`, `Grep`), in restricted mode, which removes every tool that runs commands or fetches URLs and confines the file tools to the working tree. It never runs with permission checks skipped. Prompts mark the request text, answers, reviewer feedback and failure logs as untrusted data.

The model step and the unit's checks run as a separate user from the process that holds the repository token, so they cannot read its environment or memory. Their environments are built from short allowlists: no repository token, no GitHub variable, and for the checks no AWS variable at all. The model step reaches Bedrock with the worker task role only through a loopback credential relay that the worker opens for that step alone, with a fresh token, and closes before any check runs. Each round starts with a fresh home and temporary directory that the checks could not have written. A check that changes the edited tree fails the unit, so what is committed is exactly what was checked. Before commit, the diff is checked against the unit's allowed paths, and changes to manifests, lockfiles, `.github`, `.git` and `node_modules` are refused at any depth, as are symlinks and hardlinks. Logs and failure tails are redacted for GitHub, Anthropic and AWS key shapes before they leave the task. The separation between the model step, the checks and the process that holds the repository token, and the promise that each round's home and temporary directory are ones the checks could not have written, need the worker image's default of running the worker as root, which starts the model step and the checks as a user of their own; run any other way, for example as an ordinary user on a laptop, every child runs as the current user and they do not hold.

## Worker egress

Worker tasks run in private subnets with **no inbound rules**. Their security group allows outbound **TCP 443 only**, through NAT, plus TCP 8081 to `control`'s security group for the nonce exchange.

This limits ports, **not destinations**: a worker can reach any HTTPS host on the internet. What a compromised worker could leak is bounded by what it holds, which is one repository-scoped token for at most an hour and a model step with no credentials of its own, but the security group does not stop it sending that anywhere. Do not point an installation at repositories with sensitive code until outbound traffic is restricted by domain, for example with an egress proxy that allows only GitHub and your model endpoint.

Telemetry follows the same rule: a worker can only send to an OTLP endpoint on HTTPS port 443, or to a collector inside the VPC that its security group allows. An `http://…:4318` collector outside the VPC does not receive worker telemetry.

## Configuration and secrets

`control` resolves every setting through one interface, with three kinds of locator: `secretsmanager:<arn>`, `ssm:<name>` and `local` (envelope-encrypted in Postgres under the KEK, with a fresh data key per value and the key name bound into the encryption). The admin page records where a value lives; it never writes to Secrets Manager or SSM. `edge` and the worker cannot construct the configuration source at all. No value appears in a log line, a span, an audit row or an error message: the logger redacts sensitive keys, bearer values, JWTs and GitHub tokens.

## Spending limits

The model is called with a deadline, under a daily token budget and a kill switch that `control` reads before every call. While the switch is on or the budget is spent, queued work waits rather than fails. Each request's estimated tokens become its own spending ceiling.

## What is not covered

- Signed SBOMs and provenance attestations for the images are not published.
- The egress limits above restrict ports only, as described.
