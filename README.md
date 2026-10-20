# request-4-change

request-4-change is a standalone companion app that gives any web application
in-app bug reporting and feature requests. It enriches and decomposes each
request, files it in the team's system of record and, after approval, dispatches
headless Claude Code workers to do the work.

This repository is the public face of the product. It holds **documentation and
deploy examples only**. The source code lives in a private repository and is not
published here.

## What is here

- [`docs/`](docs/README.md): how to deploy, configure and operate request-4-change.
- [`deploy/`](deploy/README.md): example deployment files that run the published
  images.

## Images

request-4-change runs as two container images, published on GitHub Container
Registry:

- `ghcr.io/foolswithtools/request-4-change-server`
- `ghcr.io/foolswithtools/request-4-change-worker`

Every image reference in this repository is pinned by digest
(`image@sha256:...`), never by a mutable tag. The images carry a bundled build,
and their contents can be inspected; the security model does not depend on the
code being secret.

## How content arrives

Nothing is committed to this repository directly. Docs and deploy examples
arrive only as snapshot pull requests from the private repository: a tagged,
allowlisted copy of the published paths, which a maintainer reviews and merges.
`main` is protected; a reviewed pull request is the only way in.

Examples use `example.com` and placeholder values. Replace them with your own.

## Licence

MIT, see [`LICENSE`](LICENSE). The licence covers the docs, the deploy examples
and the published `request-4-change-server` and `request-4-change-worker`
images.
