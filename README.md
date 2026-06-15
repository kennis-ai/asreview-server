# asreview-server

Public, reproducible build of [ASReview LAB](https://github.com/asreview/asreview)
packaged as a container image for the **kennis-pve** Kubernetes cluster.

Published as `ghcr.io/kennis-ai/asreview-lab:<version>`.

## Why this repo exists

node01's original `asreview-server:latest` was a local Docker Swarm build that
was never backed up — only the compose survived. That compose proved the image
was **stock upstream ASReview LAB v2** (entrypoint `asreview.webapp.app:create_app()`
plus the `auth-tool` and `task-manager` subcommands), with no proprietary code.
This repo rebuilds it faithfully from `pip install asreview==<version>`.

It lives in its own **public** repo so the GHCR package can be public: the
kennis-pve cluster pulls every workload from public registries with no
`imagePullSecret`. The Kubernetes manifests that consume this image (Deployment,
Service, PVC, Secrets, ingress) live in the **private** `kennis-ai/infrastructure`
repo, because they reference cluster-internal databases and secrets. Nothing
sensitive lives here — it's a thin packaging of an open-source tool.

## Version pinning

The tag tracks the ASReview version. `2.1.1` is the version that wrote the
restored production database (5 users, 1 project); pinning to it avoids an
incompatible schema migration against the restored tables. Bump deliberately.

## Build

CI (`.github/workflows/build.yml`) builds natively on GitHub's amd64 runner —
the same architecture as the cluster — sanity-checks the artifact, then pushes:

- confirms `asreview auth-tool`, `asreview task-manager`, and
  `asreview.webapp.app:create_app` resolve,
- asserts the installed version equals the tag,
- asserts the runtime uid is 1000 (the cluster runs it under PSA `restricted`).

```bash
# Manual build of a specific version:
gh workflow run build.yml -f version=2.1.1
gh run watch

# Local (amd64; emulated + slow on Apple Silicon):
docker build -t ghcr.io/kennis-ai/asreview-lab:2.1.1 .
```

## Runtime

The image runs, as uid 1000:

```
asreview auth-tool create-db \
  && (asreview task-manager &) \
  && exec gunicorn -w 4 -b 0.0.0.0:5000 'asreview.webapp.app:create_app()'
```

It expects a Postgres connection and config via the standard ASReview env /
`asreview_config.toml` (`ASREVIEW_LAB_CONFIG_PATH`), and a writable
`/project_folder` (`ASREVIEW_PATH`). See the deployment manifests in
`kennis-ai/infrastructure` under
`clusters/kennis-pve/apps/kennis-production/asreview/`.

## License

The Dockerfile and CI in this repo are MIT. The packaged software, ASReview, is
Apache-2.0 — see the [upstream project](https://github.com/asreview/asreview).
