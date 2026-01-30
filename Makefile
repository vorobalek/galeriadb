# Galeriadb: build, lint, test. Run from repo root.
# Dependencies: docker, docker compose, hadolint, shellcheck, shfmt (for lint),
#   container-structure-test, trivy, dockle (for security/cst).
# Optional: use 'make ci-docker' (full CI in container) or 'make lint-docker' (lint only, same dev image).

SHELL := /bin/bash
# Use :local for tests so we never accidentally use a pulled image when running via make
IMAGE ?= galeriadb/11.8:local
DEV_IMAGE ?= galeriadb/dev:local
DOCKERFILE ?= docker/Dockerfile
DOCKERFILE_DEV ?= docker/Dockerfile.dev
CONTEXT ?= docker/
CST_CONFIG ?= tests/04.cst/config/cst.yaml
ARTIFACTS_DIR ?= ./artifacts

# Shell scripts to lint (docker/ and tests/)
SH_FILES := $(shell find docker tests -name '*.sh' 2>/dev/null || true)
DOCKERFILES := $(shell find . -name 'Dockerfile' -not -path './.git/*' 2>/dev/null || true)

.PHONY: help lint lint-docker build build-dev ci ci-docker swarm cst security test-smoke test-deploy test-backup-s3 test clean

help:
	@echo "Targets: lint, lint-docker, build, build-dev, ci, ci-docker, swarm, cst, security, test-smoke, test-deploy, test-backup-s3, test"

lint: lint-dockerfile lint-shell lint-shfmt

lint-dockerfile:
	@echo "--- hadolint ---"
	@command -v hadolint >/dev/null 2>&1 || (echo "hadolint not found; install from https://github.com/hadolint/hadolint" && exit 1)
	@for f in $(DOCKERFILES); do echo "Linting $$f"; hadolint "$$f" || exit 1; done

lint-shell:
	@echo "--- shellcheck ---"
	@command -v shellcheck >/dev/null 2>&1 || (echo "shellcheck not found; install from https://www.shellcheck.net/" && exit 1)
	@for f in $(SH_FILES); do echo "Linting $$f"; shellcheck "$$f" || exit 1; done

lint-shfmt:
	@echo "--- shfmt check ---"
	@command -v shfmt >/dev/null 2>&1 || (echo "shfmt not found; install with: go install mvdan.cc/sh/v3/cmd/shfmt@latest" && exit 1)
	@for f in $(SH_FILES); do shfmt -d -i 2 -ci "$$f" || exit 1; done

# Run lint inside dev container (same image as ci-docker; no Docker socket needed).
lint-docker: build-dev
	@echo "--- lint (in container) ---"
	docker run --rm -v "$(CURDIR):/workspace" -w /workspace "$(DEV_IMAGE)" make lint

# Dev image: hadolint, shellcheck, shfmt, CST, Trivy, Dockle, Docker CLI + Compose. Used by ci-docker and lint-docker.
build-dev:
	@echo "--- build dev image $(DEV_IMAGE) ---"
	docker build -t "$(DEV_IMAGE)" -f "$(DOCKERFILE_DEV)" .

# Single entry point for all tests. Used by CI and locally (make ci or make ci-docker).
ci: lint build cst security test-smoke test-deploy test-backup-s3
	@echo "--- CI passed ---"

# Swarm sanity (main/schedule only in CI). Uses IMAGE; run after make ci.
swarm: build
	@echo "--- swarm sanity ---"
	bash ./tests/05.swarm/entrypoint.sh

# Run full CI inside dev container; uses host Docker via socket (no Docker-in-Docker).
# Trivy cache is mounted so the vuln DB is downloaded once and reused (no ~800 MiB each run).
ci-docker: build-dev
	@echo "--- CI (in container, host Docker socket) ---"
	docker run --rm \
		-v "$(CURDIR):/workspace" \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v trivy-cache:/root/.cache/trivy \
		-w /workspace \
		-e IMAGE="$(IMAGE)" \
		-e ARTIFACTS_DIR="$(ARTIFACTS_DIR)" \
		-e HOST_WORKSPACE="$(CURDIR)" \
		"$(DEV_IMAGE)" make ci

# Alias for ci-docker.
test-docker: ci-docker

build:
	@echo "--- build image $(IMAGE) ---"
	docker build -t "$(IMAGE)" -f "$(DOCKERFILE)" "$(CONTEXT)"

cst: build
	@echo "--- container structure test ---"
	./tests/04.cst/entrypoint.sh "$(IMAGE)"

security: build
	@echo "--- trivy ---"
	@command -v trivy >/dev/null 2>&1 || (echo "trivy not found" && exit 1)
	trivy image --exit-code 1 --severity CRITICAL $(IMAGE)
	@echo "--- dockle ---"
	@command -v dockle >/dev/null 2>&1 || (echo "dockle not found" && exit 1)
	@dockle --exit-code 1 -i CIS-DI-0001 $(IMAGE)

test-smoke: build
	@echo "--- smoke test ---"
	./tests/01.smoke/entrypoint.sh "$(IMAGE)"

# Runs all deploy cases in order: 01.all, 02.mixed, 03.restart, 04.full-restart (one compose config).
test-deploy: build
	@echo "--- deploy test ---"
	COMPOSE_IMAGE="$(IMAGE)" ./tests/02.deploy/entrypoint.sh "$(IMAGE)"

test-backup-s3: build
	@echo "--- S3 backup test (MinIO) ---"
	./tests/03.backup-s3/entrypoint.sh "$(IMAGE)"

# Alias for ci (single entry point for full check).
test: ci

clean:
	@docker compose -f tests/02.deploy/compose/compose.test.yml -p galeriadb-test down -v --remove-orphans 2>/dev/null || true
	@rm -rf "$(ARTIFACTS_DIR)"
