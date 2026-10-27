SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

MODULES      := $(wildcard modules/*)
ENVS         := dev staging prod
INTEGRATION  := modules/vpc modules/s3-secure-bucket modules/iam-github-oidc bootstrap
export PATH  := $(CURDIR)/.bin:$(PATH)

.PHONY: help tools fmt validate lint docs test-unit test-policy test-integration plan checkov all

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

tools: ## Install pinned tflint, terraform-docs, opa and conftest into ./.bin
	scripts/install-tools.sh tflint terraform-docs opa conftest

fmt: ## Format Terraform and Rego
	terraform fmt -recursive
	opa fmt -w policies

validate: ## terraform validate every directory that contains .tf files
	find . -name '*.tf' -not -path '*/.terraform/*' -printf '%h\n' | sort -u | while read -r d; do \
	  terraform -chdir="$$d" init -backend=false >/dev/null && terraform -chdir="$$d" validate; done

lint: ## tflint with the AWS ruleset
	tflint --init && tflint --recursive

docs: ## Refresh module READMEs (terraform-docs)
	for m in $(MODULES); do terraform-docs -c .terraform-docs.yml $$m; done

test-unit: ## Mocked unit tests for every module
	for m in $(MODULES); do terraform -chdir=$$m init -backend=false >/dev/null && terraform -chdir=$$m test -test-directory=tests/unit; done

test-policy: ## OPA policy unit tests
	opa check --strict policies && opa test policies -v

test-integration: ## Apply/destroy tests against a LocalStack on localhost:4566
	export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 AWS_ENDPOINT_URL=http://localhost:4566; \
	for d in $(INTEGRATION); do terraform -chdir=$$d init -backend=false -test-directory=tests/integration >/dev/null && terraform -chdir=$$d test -test-directory=tests/integration; done

plan: ## Plan every environment against LocalStack and run Conftest on the result
	export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-1 AWS_ENDPOINT_URL=http://localhost:4566; \
	for e in $(ENVS); do scripts/localstack-override.sh live/$$e; \
	  terraform -chdir=live/$$e init >/dev/null; \
	  terraform -chdir=live/$$e plan -refresh=false -lock=false -out=tfplan; \
	  terraform -chdir=live/$$e show -json tfplan > live/$$e/plan.json; \
	  conftest test live/$$e/plan.json -p policies --all-namespaces; done

checkov: ## Checkov static scan (Docker)
	docker run --rm -v "$(CURDIR):/src" -w /src bridgecrew/checkov:3.3.30 -d . --config-file .checkov.yaml

all: fmt validate lint docs test-unit test-policy ## Everything that runs without Docker
