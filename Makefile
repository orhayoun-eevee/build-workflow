.PHONY: help lint lint-tools-check

help:
	@echo "Targets:"
	@echo "  make lint              Run local workflow/script/Dockerfile lint checks"

lint-tools-check:
	@missing=0; \
	for tool in shellcheck shfmt actionlint hadolint; do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			echo "Missing required tool: $$tool"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "Install the missing tools, then run: make lint"; \
		exit 1; \
	fi

lint: lint-tools-check
	@mapfile -t script_files < <(find scripts -type f -name '*.sh'); \
	if [ "$${#script_files[@]}" -gt 0 ]; then \
		shellcheck "$${script_files[@]}"; \
	else \
		echo "No shell scripts found under scripts/"; \
	fi
	@shfmt -d scripts
	@actionlint
	@hadolint --failure-threshold error docker/Dockerfile
