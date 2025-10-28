# Makefile for Hug SCM
# A humane, intuitive interface for Git and other version control systems

.PHONY: help
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

##@ General

help: ## Display this help message
	@echo "$(BLUE)Hug SCM - Makefile Help$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Testing

test: ## Run all tests using BATS
	@echo "$(BLUE)Running all tests...$(NC)"
	./tests/run-tests.sh

test-unit: ## Run only unit tests
	@echo "$(BLUE)Running unit tests...$(NC)"
	./tests/run-tests.sh --unit

test-integration: ## Run only integration tests
	@echo "$(BLUE)Running integration tests...$(NC)"
	./tests/run-tests.sh --integration

test-check: ## Check test prerequisites without running tests
	@echo "$(BLUE)Checking test prerequisites...$(NC)"
	./tests/run-tests.sh --check

test-deps-install: ## Install or update local BATS dependencies
	@echo "$(BLUE)Installing test dependencies...$(NC)"
	./tests/run-tests.sh --install-deps

##@ VHS Screencasts

vhs-check: ## Check if VHS is installed
	@echo "$(BLUE)Checking VHS installation...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --check

vhs: demo-repo vhs-check ## Build all GIF/PNG images from VHS tape files
	@echo "$(BLUE)Building all VHS screencasts...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --all

vhs-build: vhs ## Alias for vhs target

vhs-build-one: demo-repo vhs-check ## Build a specific VHS tape file (usage: make vhs-build-one TAPE=filename.tape)
	@echo "$(BLUE)Building VHS screencast: $(TAPE)$(NC)"
	@if [ -z "$(TAPE)" ]; then \
		echo "$(YELLOW)Usage: make vhs-build-one TAPE=filename.tape$(NC)"; \
		exit 1; \
	fi
	@bash docs/screencasts/bin/vhs-build.sh "$(TAPE)"

vhs-dry-run: ## Show what would be built without building
	@echo "$(BLUE)Dry run - showing what would be built...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --dry-run --all

vhs-clean: ## Remove generated GIF/PNG files from VHS
	@echo "$(BLUE)Cleaning VHS generated images...$(NC)"
	@rm -f docs/commands/img/hug-*.gif docs/commands/img/hug-*.png
	@echo "$(GREEN)VHS images cleaned$(NC)"

##@ Documentation

docs-dev: vhs ## Start documentation development server
	@echo "$(BLUE)Starting documentation server...$(NC)"
	npm run docs:dev

docs-build: vhs ## Build documentation for production
	@echo "$(BLUE)Building documentation...$(NC)"
	npm run docs:build

docs-preview: vhs ## Preview built documentation
	@echo "$(BLUE)Previewing documentation...$(NC)"
	npm run docs:preview

##@ Installation

install: ## Install Hug SCM
	@echo "$(BLUE)Installing Hug SCM...$(NC)"
	./install.sh
	@echo "$(GREEN)Installation complete!$(NC)"
	@echo "Run 'source bin/activate' to activate Hug"

deps-docs: ## Install documentation dependencies
	@echo "$(BLUE)Installing documentation dependencies...$(NC)"
	npm ci

##@ Development

check: test-check ## Alias for test-check (check prerequisites)

clean: ## Clean build artifacts and temporary files
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	rm -rf docs/.vitepress/dist
	rm -rf docs/.vitepress/cache
	rm -rf node_modules/.vite
	@echo "$(GREEN)Clean complete!$(NC)"

clean-all: clean demo-clean ## Clean everything including node_modules
	@echo "$(BLUE)Cleaning everything...$(NC)"
	rm -rf node_modules
	@echo "$(GREEN)Deep clean complete!$(NC)"

##@ Demo Repository

demo-repo: ## Create demo repository for tutorials and screencasts
	@echo "$(BLUE)Creating demo repository...$(NC)"
	@bash docs/screencasts/bin/repo-setup.sh
	@echo "$(GREEN)Demo repository created at /tmp/demo-repo$(NC)"

demo-clean: ## Clean demo repository and remote
	@echo "$(BLUE)Cleaning demo repository...$(NC)"
	@rm -rf /tmp/demo-repo /tmp/demo-repo.git
	@echo "$(GREEN)Demo repository cleaned$(NC)"

demo-repo-rebuild: demo-clean demo-repo ## Rebuild demo repository from scratch

demo-repo-status: ## Show status of demo repository
	@echo "$(BLUE)Demo repository status:$(NC)"
	@if [ -d /tmp/demo-repo ]; then \
		cd /tmp/demo-repo && \
		echo "$(GREEN)Repository exists$(NC)" && \
		echo "" && \
		echo "Commits: $$(git rev-list --all --count 2>/dev/null || echo 'N/A')" && \
		echo "Branches: $$(git branch -a 2>/dev/null | wc -l || echo 'N/A')" && \
		echo "Tags: $$(git tag 2>/dev/null | wc -l || echo 'N/A')" && \
		echo "Remote: $$(git remote -v 2>/dev/null | head -1 || echo 'N/A')"; \
	else \
		echo "$(YELLOW)Demo repository does not exist$(NC)"; \
		echo "Run 'make demo-repo' to create it"; \
	fi

.PHONY: test test-unit test-integration test-check test-deps-install
.PHONY: vhs vhs-build vhs-build-one vhs-dry-run vhs-clean vhs-check
.PHONY: docs-dev docs-build docs-preview deps-docs
.PHONY: install check clean clean-all
.PHONY: demo-repo demo-clean demo-repo-rebuild demo-repo-status
