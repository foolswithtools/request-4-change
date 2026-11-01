# Extends the published worker image with your own CA certificates and with Claude Code skills for
# worker sessions.
# - CA certificates, for example for a TLS-inspecting proxy, a GitHub Enterprise Server or a model
#   endpoint with a private CA: put your PEM certificates, one per file ending in .crt, in ./certs.
# - Skills: each directory in ./plugins is a Claude Code plugin that carries only skills
#   (.claude-plugin/plugin.json and skills/<name>/SKILL.md). Replace plugins/example with your own.
#   A plugin with hooks, MCP or LSP servers, agents, commands or anything else, or a skill that
#   declares hooks or runs a shell command when it loads, makes every unit fail.
# Then:
#   docker build -t <your-registry>/request-4-change-worker:<your-tag> .
# and point the worker task definition's image at the result. docs/deploy-elsewhere.md, "Extending the
# images", says which processes trust the added certificates and how the skills are loaded.
# Add no USER line: the worker must start as root to run the model step and the checks as a user of
# their own (docs/security-model.md, "The model step").

FROM ghcr.io/foolswithtools/request-4-change-worker@sha256:dd9c2aa3dd4f91371ba2c164f0757029825534d1a792a2fb0a6b9e635be70d67
COPY certs/ /usr/local/share/ca-certificates/
RUN apk add --no-cache ca-certificates && update-ca-certificates
# Node's own requests (the worker's calls to control and GitHub, and the model step) read this; git
# reads the system store.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
# The worker loads /opt/r4c/plugins only while root owns it and the agent user can write none of it:
# keep COPY without --chown, and the chmod.
COPY plugins/ /opt/r4c/plugins/
RUN chmod -R u=rwX,go=rX /opt/r4c/plugins
