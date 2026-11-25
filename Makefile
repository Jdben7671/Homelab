.PHONY: help validate k8s lint secrets check health

help:  ## Show targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

validate:  ## docker compose config for every legacy stack
	@for f in $$(find legacy/casaos-stacks -name compose.yaml | sort); do \
	  d=$$(dirname $$f); printf '%-40s' $$d; \
	  docker compose -f $$f --env-file $$d/.env.example config --quiet && echo OK || exit 1; \
	done

k8s:  ## kubeconform for every manifest in k8s/
	docker run --rm -v "$$PWD:/repo" -w /repo ghcr.io/yannh/kubeconform:v0.7.0 -strict -summary k8s/

lint:  ## yamllint + shellcheck
	yamllint --strict .
	shellcheck scripts/*.sh

secrets:  ## gitleaks scan of the working tree + history
	gitleaks detect --source . --verbose

check: validate k8s lint secrets  ## Everything CI runs

health:  ## Live health report of the homelab
	./scripts/healthcheck.sh
