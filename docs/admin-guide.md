# Admin guide

`control` serves an admin page under `/admin` for configuring an installation: where each setting and secret lives, and the audit log. `edge` answers 404 to every `/admin` path. The page is HTML rendered on the server, with one script and no client framework.

## Enabling it

`control` serves the admin page when `R4C_ADMIN_OIDC_ISSUER` is set; without it, `/admin` answers 404. Once the issuer is set, the other required variables must be present too, or `control` exits with status 2 and names the missing variable.

| Variable | Required | Meaning |
|---|---|---|
| `R4C_ADMIN_OIDC_ISSUER` | yes | OIDC issuer URL; discovery reads `<issuer>/.well-known/openid-configuration`. Must be `https`. |
| `R4C_ADMIN_OIDC_CLIENT_ID` | yes | The app client's id at the IdP. |
| `R4C_ADMIN_OIDC_CLIENT_SECRET_LOCATOR` | no | Where the client secret lives: `ssm:<name>` or `secretsmanager:<arn>`, never the secret itself. Leave it unset for a public client (PKCE only). |
| `R4C_ADMIN_ROLE_CLAIM` | no | The ID token claim that lists the user's groups. Default `groups`. |
| `R4C_ADMIN_ROLE` | yes | The group a user must hold to use the page. |
| `R4C_ADMIN_BASE_URL` | yes | The page's origin as browsers see it, for example `https://r4c.example.com`, with no path. The redirect URI is `<base>/admin/callback`, and every `PUT` and `POST` must carry this exact `Origin`. |
| `DATABASE_URL` | yes | Sessions, sign-ins in flight and the audit log live in Postgres. |
| `R4C_DATABASE_CREDENTIALS` | no | JSON `{"username": "...", "password": "..."}`, such as an RDS managed master secret injected whole. `control` puts them, URL-encoded, into `DATABASE_URL`, which must then carry no user or password. |
| `R4C_KEK` | yes | The key-encryption key for `local` values ([below](#settings-and-secrets)). |

Register `<R4C_ADMIN_BASE_URL>/admin/callback` as the client's callback URL, with the authorization code grant and the `openid` and `email` scopes. With **Amazon Cognito**, the issuer is `https://cognito-idp.<region>.amazonaws.com/<user-pool-id>` with no trailing slash, and groups are in the claim `cognito:groups`, so set `R4C_ADMIN_ROLE_CLAIM=cognito:groups`. A client with a secret sends it with HTTP Basic authentication at the token endpoint.

## Signing in

`GET /admin` without a session goes to the IdP with a fresh state, nonce and PKCE challenge, bound to the browser by a short-lived cookie. The callback checks all three, then creates a session: cookie `r4c_admin` (`HttpOnly; Secure; SameSite=Strict`), valid 8 hours from sign-in and never extended. The database stores only a hash of the cookie. The user's groups are checked against `R4C_ADMIN_ROLE` on every request, so a user without the role gets a session that every page refuses with 403. "Sign out" deletes the session.

When the IdP is on another site, the browser withholds the `SameSite=Strict` cookie on the redirect back, so `/admin` answers that one request with a page that reloads itself from its own site. Browsers that do not send `Sec-Fetch-Site` (Safari before 16.4) may loop at sign-in in that setup.

## What the page shows

**Configuration.** Every key the running version defines, grouped by prefix (`connector`, `dispatch`, `llm`, ...). Each row shows the value (`********` for a secret whatever its length; `(unavailable)` when its store cannot be read), its source (`local`, `ssm:<name>` or `secretsmanager:<arn>`), and when and by whom it last changed. A secret's input is a password field that is never pre-filled: the page can replace a secret, never show it. A reference records where the value lives and writes nothing to Secrets Manager or SSM.

**Audit log.** Events filtered by entity and id, 200 per page, in commit order. Sign-ins, sign-outs, refused requests and configuration changes are all recorded, never with a value.

## Settings

Keys set on this page apply at once in the `control` process that serves it, and in other `control` replicas within the cache TTL (`R4C_CONFIG_CACHE_TTL_SECONDS`, 300 s by default).

### Model

| Key | Meaning |
|---|---|
| `llm.provider` | `bedrock` |
| `llm.model` | The model id. On Bedrock, use the inference profile id, for example `us.anthropic.<model>`. |
| `llm.region` | AWS region of the Bedrock endpoint |
| `llm.unit_token_cap` | Token cap for one unit's worker session |

Until all four and `R4C_KEK` are set, `control` logs `LLM steps skipped` once and claims nothing, so queued requests wait. A daily token budget (200,000 by default) and a kill switch are kept in Postgres and read before every model call; while the switch is on or the budget is spent, the steps pause and nothing fails. Set the worker task definition's `ANTHROPIC_MODEL` to the same inference profile id.

### GitHub

request-4-change uses one GitHub App, which `control` alone holds the key of.

| Key | Kind | Meaning |
|---|---|---|
| `github.app_id` | config | The App's numeric id |
| `github.app_private_key` | secret | The App's PEM private key |
| `github.webhook_secret` | secret | The App's webhook secret |
| `connector.github.repo` | config | The system-of-record repository, `owner/name`, where request and unit issues are filed |
| `connector.github.approver_team` | config | The product-owner team, `org/team-slug`. Only its members' `r4c:approved` and `r4c:declined` labels count. |
| `connector.github.api_url` | config | Optional, for GitHub Enterprise Server; `https://api.github.com` unless set. Workers do not read it: on GitHub Enterprise Server, also set the worker task definition's `R4C_GITHUB_API_URL` and `R4C_GIT_BASE_URL` ([deploy/README.md](../deploy/README.md#the-worker-task-definition)). |

The App needs `issues: write` on the system-of-record repository and `members: read` on the organization. On each target repository it needs `contents: write`, `pull_requests: write`, `checks: read`, `actions: read` and `administration: read` (to check branch protection before dispatch). Subscribe it to the `issues`, `issue_comment`, `pull_request`, `pull_request_review`, `check_suite` and `workflow_run` events, delivered to `https://<control hostname>/webhooks/github` with the webhook secret above.

### Dispatch

| Setting | Where | Meaning |
|---|---|---|
| `dispatch.targets` | key | JSON keyed by `owner/repo`, for example `{"acme/app": {"defaultBranch": "main", "checkCommands": ["pnpm test:unit"]}}`. A repository that isn't listed gets no token. |
| `dispatch.repo` | key | The installation's target repository, `owner/repo`, with an entry in `dispatch.targets` |
| `dispatch.stuck_after_minutes` | key | How long a unit may stay dispatched with no report and no PR before it counts as stuck, 15 to 10080. Default 60. Keep it above the worker's longest run on your target: a worker allows up to 20 minutes for the model step and 15 for each check command, plus clone and push. |
| `dispatch.stuck_retries` | key | Fresh attempts for a stuck unit before it is escalated, 0 to 10. Default 3. |
| `R4C_ECS_CLUSTER_ARN`, `R4C_WORKER_SUBNET_IDS`, `R4C_WORKER_SECURITY_GROUP_ID`, `R4C_CONTROL_INTERNAL_URL` | environment | What `RunTask` uses. Until all four are set, `control` logs `dispatch skipped` once and starts no task. |
| `R4C_DISPATCH_CONCURRENCY` | environment | Units being dispatched at once, 1 to 100. Default 2. |

Before each unit, `control` checks that the target is configured, that its default branch requires status checks, and that the request is below its token ceiling. A unit that fails a check stays approved, gets one comment on its issue naming the reason, and is checked again after 15 minutes. When GitHub cannot be reached for the branch-protection check, the unit is checked again after 15 minutes without a comment, and the audit log records the reason `unavailable`.

### Feedback and escalation

| Key | Meaning |
|---|---|
| `feedback.escalation_team` | The team escalation comments mention, `org/team-slug`. Unset: no one is mentioned. A person is never mentioned. |
| `feedback.answers_timeout_hours` | How long a unit waits for an `r4c-answers:` reply to its questions before it is escalated, 1 to 8760. Default 72. |
| `runner.idle_interval_ms` | How long a queue step waits after finding nothing to do, 10 to 3600000. Default 5000. |

A failed CI run on a worker's PR starts a new round with the redacted failure log, at most three rounds. After the last, `control` asks the model once to rescope the unit into at most two smaller ones; a unit that can't be rescoped, or whose PR is closed without a merge, is escalated: labelled `r4c:needs-human`, left open, with one comment. `R4C_RUNNER=off` starts no queue steps (a `control` that only serves the API).

## Settings and secrets

Each key's value has one locator:

| Locator | Value lives in | Read with `control`'s task role |
|---|---|---|
| `secretsmanager:<arn>` | AWS Secrets Manager | `GetSecretValue` (`SecretString` only) |
| `ssm:<name>` | SSM Parameter Store | `GetParameter` with decryption |
| `local` | Postgres, envelope-encrypted under the KEK | — |

A rotated value in Secrets Manager or SSM takes effect within one cache TTL, without a redeploy. A store read that fails is retried after 30 s.

`R4C_KEK` picks the key-encryption key: `kms:<key-id-or-arn>`, or `file:<path>` to a mounted file of exactly 32 random bytes (`head -c 32 /dev/urandom > kek && chmod 600 kek`, mounted from a secret store, never the image). Each `local` value gets its own data key, wrapped by the KEK, and both layers bind the key name, so a sealed value copied onto another key does not open.

Keep `R4C_KEK` spelled exactly as when values were sealed: its key id is a hash of the configured string, so switching between a key id, its ARN or an alias strands existing values. For KMS, turn on automatic key rotation; nothing else changes. To rotate a `file:` key, or move from `file:` to `kms:`:

1. Mount the new key beside the old one, and restart `control` with `R4C_KEK=<new>` and `R4C_KEK_PREVIOUS=file:<old>`.
2. Run `--role=control config rewrap` once (needs `DATABASE_URL`, `R4C_KEK` and `R4C_KEK_PREVIOUS`). It re-seals every `local` value under the current KEK in one transaction and prints `{"rewrapped":n,"unchanged":m}`. Running it again is a no-op.
3. Remove `R4C_KEK_PREVIOUS` and the old key.

Moving from one KMS key to another, or from `kms:` back to `file:`, is not supported yet.

## Limits

Anyone who can reach `/admin` can make it write to the database without signing in, so `control` bounds that itself:

- **Per client** (an IPv4 address, or an IPv6 /64): 120 requests a minute across `/admin`, and 10 a minute to the sign-in route. Beyond that, 429 with `Retry-After`, and nothing is written. Counts are per `control` process.
- **Repeated refusals** that need no session are audited once per client, reason and subject every 10 minutes, then as one collapsed count.
- **Sign-ins in flight** are capped at 1,000 across all clients; past that, sign-in answers 429 until some expire (10 minutes). A WAF rule on the load balancer is the defense against many clients at once.

### Behind a load balancer

The limits key on the TCP peer by default, and `X-Forwarded-For` is ignored, so a caller cannot choose the address it is counted under. Behind a load balancer every request comes from the balancer, so set `R4C_TRUSTED_PROXIES`: comma-separated addresses, CIDRs (`10.0.0.0/24`, `fd00::/8`), or `loopback`, `linklocal` or `uniquelocal`. For an ALB, list the CIDRs of the subnets it is attached to. A bad entry stops `control` at start with status 2.

## Page security

Every `/admin` response carries `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and a `Content-Security-Policy` with `default-src 'self'` and `frame-ancestors 'none'`. There is no inline script or style. Error replies never repeat the request body.
