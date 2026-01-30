# Galeriadb: build, lint, test. Run from repo root.
# Dependencies: docker, docker compose, hadolint, shellcheck, shfmt (for lint),
#   container-structure-test, trivy, dockle (for security/cst).

SHELL := /bin/bash
# Use :local for tests so we never accidentally use a pulled image when running via make
IMAGE ?= galeriadb/11.8:local
DOCKERFILE ?= docker/Dockerfile
CONTEXT ?= docker/
CST_CONFIG ?= tests/04.cst/config/cst.yaml
COMPOSE_TEST_FILE ?= tests/02.integration-compose/compose/compose.test.yml
ARTIFACTS_DIR ?= ./artifacts

# Shell scripts to lint (docker/ and tests/)
SH_FILES := $(shell find docker tests -name '*.sh' 2>/dev/null || true)
DOCKERFILES := $(shell find . -name 'Dockerfile' -not -path './.git/*' 2>/dev/null || true)

.PHONY: help lint lint-dockerfile lint-shell lint-shfmt build cst security smoke integration backup-s3 test clean

help:
	@echo "Targets: lint, lint-dockerfile, lint-shell, lint-shfmt, build, cst, security, smoke, integration, backup-s3, test"

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
	@if [ -f tests/00.config/dockle.yaml ]; then dockle --exit-code 1 --config tests/00.config/dockle.yaml $(IMAGE); else dockle --exit-code 1 $(IMAGE); fi

smoke: build
	@echo "--- smoke test ---"
	./tests/01.smoke/entrypoint.sh "$(IMAGE)"

integration: build
	@echo "--- integration test (all) ---"
	COMPOSE_IMAGE="$(IMAGE)" ./tests/02.integration-compose/entrypoint.sh "$(IMAGE)"

integration-mixed: build
	@echo "--- integration test (mixed order) ---"
	COMPOSE_IMAGE="$(IMAGE)" INTEGRATION_SCENARIO=mixed ./tests/02.integration-compose/entrypoint.sh "$(IMAGE)"

integration-restart: build
	@echo "--- integration test (restart node) ---"
	COMPOSE_IMAGE="$(IMAGE)" INTEGRATION_SCENARIO=restart ./tests/02.integration-compose/entrypoint.sh "$(IMAGE)"

backup-s3: build
	@echo "--- S3 backup test (MinIO) ---"
	./tests/03.backup-s3/entrypoint.sh "$(IMAGE)"

test: lint build cst security smoke integration
	@echo "--- all tests passed ---"

clean:
	@docker compose -f "$(COMPOSE_TEST_FILE)" -p galeriadb-test down -v --remove-orphans 2>/dev/null || true
	@rm -rf "$(ARTIFACTS_DIR)"
