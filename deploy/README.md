# Deploy examples

This directory will hold example files for running the published
request-4-change images. Its planned layout:

| Item | What it holds |
|---|---|
| ECS task definitions | Amazon ECS task-definition examples for the edge sidecar, the control service and the worker task |
| `deploy/compose.yaml` | A Docker Compose file for a local trial, with Postgres |
| `deploy/extend/` | A `Dockerfile` that starts `FROM` a published image and shows how to add CA certificates, plugins and skills |

Every image reference in these files is a digest, for example
`ghcr.io/foolswithtools/request-4-change-server@sha256:<digest>`, never a tag.

No Dockerfile that builds request-4-change from source is published here. The
`deploy/extend/` example only layers on top of a published image.

The files arrive with the first snapshot from the private repository.
