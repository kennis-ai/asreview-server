# Dockerfile — ghcr.io/kennis-ai/asreview-server
#
# Public, reproducible rebuild of node01's lost `asreview-server:latest` local
# image. It exists in a PUBLIC repo of its own so the GHCR package can be public
# — the kennis-pve cluster pulls every workload from public registries with no
# imagePullSecrets. The k8s manifests that consume this image live in the private
# `kennis-ai/infrastructure` repo (they reference cluster DB/secrets); only the
# image build lives here.
#
# The original build context was never committed or backed up (Portainer stored
# only the compose). The node01 Swarm spec proved the image was stock upstream
# ASReview LAB v2 — entrypoint `asreview.webapp.app:create_app()` +
# `asreview auth-tool create-db` + `asreview task-manager`, no proprietary code.
# So this is a faithful, from-scratch rebuild — nothing sensitive ships here.
#
# Version pin: the restored project metadata recorded "version": "2.1.1", the
# ASReview version that wrote the production DB (5 users, 1 project). Pinning to
# it avoids an incompatible schema migration against the restored tables.
#
# Built + published by .github/workflows/build.yml (native amd64, sanity-checked).
FROM python:3.12-slim

# Links the GHCR package to this public repo (provenance + public visibility).
LABEL org.opencontainers.image.source="https://github.com/kennis-ai/asreview-server" \
      org.opencontainers.image.description="Upstream ASReview LAB, packaged for the kennis-pve cluster" \
      org.opencontainers.image.licenses="Apache-2.0"

ARG ASREVIEW_VERSION=2.1.1

# psycopg2-binary: ASReview talks to CNPG Postgres over SQLAlchemy
#   (postgresql+psycopg2://). gunicorn: WSGI server, 4 workers, matching node01.
RUN pip install --no-cache-dir \
        "asreview==${ASREVIEW_VERSION}" \
        "gunicorn>=21,<24" \
        "psycopg2-binary>=2.9,<3"

# Run as a non-root uid (1000) so the pod satisfies PSA `restricted`. The
# Deployment's fsGroup=1000 + init chown make the restored /project_folder PVC
# writable by this uid. HOME must be writable (ASReview/Flask scratch files).
RUN useradd --uid 1000 --create-home --shell /bin/bash asreview \
 && mkdir -p /project_folder /app/config \
 && chown -R 1000:1000 /project_folder /app /home/asreview

ENV ASREVIEW_PATH=/project_folder \
    ASREVIEW_LAB_HOST=0.0.0.0 \
    HOME=/home/asreview

USER 1000
WORKDIR /app
EXPOSE 5000

# Faithful replica of the node01 compose command:
#   1. auth-tool create-db   — idempotent; ensures the auth schema exists
#   2. task-manager &        — background simulation/queue runner
#   3. gunicorn (exec)       — foreground WSGI server; exec makes it PID-forwarded
#
# Shell-form CMD (no ENTRYPOINT) so `docker run IMG <other cmd>` overrides this
# cleanly. An `ENTRYPOINT ["bash","-c"]` would instead swallow any run args as
# positional params to bash — breaking introspection and the deployment's
# ability to ever override the command.
CMD ["bash", "-c", "asreview auth-tool create-db && (asreview task-manager &) && exec gunicorn -w 4 -b 0.0.0.0:5000 'asreview.webapp.app:create_app()'"]
