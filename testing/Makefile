DC := docker compose

.PHONY: help build clean

.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Testing container tooling (local build/test)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

build: ## Build the resume-testing Docker image
	docker build -t resume-testing .

clean: ## Remove the resume-testing Docker image
	docker rmi resume-testing 2>/dev/null || true
