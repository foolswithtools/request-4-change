# syntax=docker/dockerfile:1
# Extends the published worker image with your own CA certificates, for example for a TLS-inspecting
# proxy or a GitHub Enterprise Server with a private CA. Put your PEM certificates, one per file
# ending in .crt, in ./certs beside this file, then:
#   docker build -t <your-registry>/request-4-change-worker:<your-tag> .
# and point the worker task definition's image at the result. Which processes in the worker trust the
# added certificates is in docs/deploy-elsewhere.md, "Extending the images". Loading Claude Code
# plugins and skills into worker sessions is not supported yet.

FROM ghcr.io/foolswithtools/request-4-change-worker@sha256:e7603b4a3ccb907b16f9d835483428120d24e7d46b24dc6273cca616d78e6903
COPY certs/ /usr/local/share/ca-certificates/
RUN apk add --no-cache ca-certificates && update-ca-certificates
# Node's own requests (the worker's calls to control and GitHub) read this; git reads the system store.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
