# Contributing to galeriadb

Thanks for your interest in improving galeriadb! This guide covers how to
propose changes and run the project locally.

## Before You Start

- Read and follow the Code of Conduct: `CODE_OF_CONDUCT.md`.
- For security issues, please follow `SECURITY.md` and do not open a public
  issue.
- Search existing issues and pull requests to avoid duplicates.

## Development Setup

The project builds a Docker image and includes a dev/CI container so you do not
need a local toolchain beyond Docker and Make.

### Build the Image

```bash
docker build -t galeriadb/12.1:local -f docker/Dockerfile docker/
```

### Run the Test Suite

```bash
make ci
```

Run the same suite inside the dev container:

```bash
make ci-docker
```

Common targets:

- `make lint` (hadolint, shellcheck, shfmt)
- `make build` (builds `galeriadb/12.1:local`)
- `make cst` (Container Structure Tests)
- `make security` (Trivy + Dockle)
- `make smoke` (single-node startup)

## Making Changes

- Create a feature branch from the default branch (the latest MariaDB version).
- Keep changes focused and update docs/tests when behavior changes.
- Prefer small, well-described commits.
- Use `make lint` and `make ci` (or `make ci-docker`) before opening a PR.

## Submitting a Pull Request

Please include:

- A clear summary of the change.
- Links to related issues (if any).
- The tests you ran and their results.

## Versioned Branches

The default branch tracks the latest MariaDB version for this repo. Older
versions are maintained in versioned branches when needed.
