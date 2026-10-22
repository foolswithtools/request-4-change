# request-4-change

request-4-change is a standalone companion app that gives any web application in-app bug reporting and feature requests. It enriches and decomposes each request, files it in the team's system of record and, after approval, dispatches headless Claude Code workers that open pull requests for the work. It never merges and never deploys: a person merges every pull request.

This repository is the public face of the product. It holds **documentation and deploy examples only**. The source code lives in a private repository and is not published here.

## What is here

- [`docs/`](docs/README.md): how to deploy, configure and operate request-4-change, and the widget contract a host app builds against.
- [`deploy/`](deploy/README.md): example files that run the published images: Amazon ECS task definitions, a Docker Compose file for a local trial, and an example that extends the worker image.

## Images

request-4-change runs as two container images, published on GitHub Container Registry:

- `ghcr.io/foolswithtools/request-4-change-server@sha256:56e4d4327bb32003571d70cce66bdf89c5f35e2a0259da26776aee00f61a3cb4`, run as the `edge` role (a sidecar in the host app's task) and as the `control` role (one service per installation);
- `ghcr.io/foolswithtools/request-4-change-worker@sha256:e7603b4a3ccb907b16f9d835483428120d24e7d46b24dc6273cca616d78e6903`, run as one short-lived task per unit of work.

Every image reference in this repository is pinned by digest (`image@sha256:...`), never by a mutable tag. The images carry a bundled build, and their contents can be inspected; the security model does not depend on the code being secret.

## How content arrives

Nothing is committed to this repository directly. Docs and deploy examples arrive only as snapshot pull requests from the private repository: a tagged, allowlisted copy of the published paths, checked for secrets and private names, which a maintainer reviews and merges. `main` is protected; a reviewed pull request is the only way in.

Examples use `example.com` and placeholder values in angle brackets, such as `<account-id>`. Replace them with your own.

## Licence

MIT, see [`LICENSE`](LICENSE). The licence covers the docs, the deploy examples and the published `request-4-change-server` and `request-4-change-worker` images.
