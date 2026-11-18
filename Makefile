.PHONY: help validate lint secrets check health

help:  ## Show targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

validate:  ## docker compose config for every stack
	@for f in $$(find stacks -name compose.yaml | sort); do \
	  d=$$(dirname $$f); printf '%-40s' $$d; \
	  docker compose -f $$f --env-file $$d/.env.example config --quiet && echo OK || exit 1; \
	done

lint:  ## yamllint + shellcheck
	yamllint --strict .
	shellcheck scripts/*.sh

secrets:  ## gitleaks scan of the working tree + history
	gitleaks detect --source . --verbose

check: validate lint secrets  ## Everything CI runs

health:  ## Live health report of the homelab
	./scripts/healthcheck.sh
