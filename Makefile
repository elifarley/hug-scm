# Makefile for Hug SCM
# A humane, intuitive interface for Git and other version control systems

.PHONY: help
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Test customization variables (optional)
TEST_FILE ?=
TEST_FILTER ?=

DEMO_REPO_BASE := /tmp/demo-repo

# Setup PATH for demo repository creation (includes hug commands)
HUG_BIN_PATH := $(shell pwd)/git-config/bin
DEMO_REPO_ENV := export PATH="$$PATH:$(HUG_BIN_PATH)" &&

##@ General

help: ## Display this help message
	@echo "$(BLUE)Hug SCM - Makefile Help$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Testing

test: ## Run all tests using BATS (or specific: TEST_FILE=... TEST_FILTER=...)
	@echo "$(BLUE)Running all tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh tests/ $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-unit: ## Run only unit tests (or specific: TEST_FILE=... TEST_FILTER=...)
	@echo "$(BLUE)Running unit tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/unit/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --unit $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-integration: ## Run only integration tests (or specific: TEST_FILE=... TEST_FILTER=...)
	@echo "$(BLUE)Running integration tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/integration/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --integration $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-lib: ## Run only library tests (or specific: TEST_FILE=... TEST_FILTER=...)
	@echo "$(BLUE)Running library tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/lib/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --lib $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-check: ## Check test prerequisites without running tests
	@echo "$(BLUE)Checking test prerequisites...$(NC)"
	./tests/run-tests.sh --check

test-deps-install: ## Install or update local BATS dependencies
	@echo "$(BLUE)Installing test dependencies...$(NC)"
	./tests/run-tests.sh --install-deps

optional-deps-install: ## Install optional dependencies (gum, etc.)
	@echo "$(BLUE)Installing optional dependencies...$(NC)"
	@bash bin/optional-deps-install.sh

optional-deps-check: ## Check if optional dependencies are installed
	@echo "$(BLUE)Checking optional dependencies...$(NC)"
	@bash bin/optional-deps-install.sh --check

##@ VHS Screencasts

vhs-deps-install: ## Install VHS tool if not present
	@echo "$(BLUE)Installing VHS dependencies...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --install-deps

vhs-check: vhs-deps-install ## Check if VHS is installed
	@echo "$(BLUE)Checking VHS installation...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --check

vhs: demo-repo-rebuild-all vhs-deps-install ## Build all GIF/PNG images from VHS tape files
	@echo "$(BLUE)Building all VHS screencasts...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --all
	@$(MAKE) vhs-strip-metadata

vhs-build: vhs ## Alias for vhs target

vhs-build-one: vhs-check ## Build a specific VHS tape file (usage: make vhs-build-one TAPE=filename.tape)
	@echo "$(BLUE)Building VHS screencast: $(TAPE)$(NC)"
	@if [ -z "$(TAPE)" ]; then \
		echo "$(YELLOW)Usage: make vhs-build-one TAPE=filename.tape$(NC)"; \
		exit 1; \
	fi
	@bash docs/screencasts/bin/vhs-build.sh "$(TAPE)"
	@$(MAKE) vhs-strip-metadata

vhs-dry-run: ## Show what would be built without building
	@echo "$(BLUE)Dry run - showing what would be built...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --dry-run --all

vhs-strip-metadata: ## Strip metadata from all PNG/GIF images to make them deterministic
	@echo "$(BLUE)Stripping metadata from images...$(NC)"
	@bash docs/screencasts/bin/vhs-strip-metadata.sh && echo "$(GREEN)Metadata stripped successfully$(NC)"

vhs-clean: ## Remove generated GIF/PNG files from VHS
	@bash docs/screencasts/bin/vhs-clean.sh

vhs-regenerate: demo-repo vhs-deps-install ## Regenerate VHS images for CI (demo + essential tapes)
	@echo "$(BLUE)Regenerating VHS images...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh hug-l.tape hug-lo.tape hug-lol.tape hug-sl-states.tape
	@echo "$(BLUE)Cleaning up frame directories...$(NC)"
	@bash docs/screencasts/bin/vhs-cleanup-frames.sh
	@echo "$(BLUE)Verifying cleanup...$(NC)"
	@bash docs/screencasts/bin/vhs-cleanup-frames.sh --verify-strict
	@$(MAKE) vhs-strip-metadata
	@echo "$(GREEN)VHS images regenerated successfully$(NC)"

vhs-commit-push: ## Commit and push VHS image changes (for CI/automation)
	@bash docs/screencasts/bin/vhs-commit-push.sh

##@ Documentation

docs-dev: ## Start documentation development server
	@echo "$(BLUE)Starting documentation server...$(NC)"
	npm run docs:dev

docs-build: ## Build documentation for production
	@echo "$(BLUE)Building documentation...$(NC)"
	npm run docs:build

docs-preview: ## Preview built documentation
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
	@$(DEMO_REPO_ENV) bash docs/screencasts/bin/repo-setup.sh "$(DEMO_REPO_BASE)"
	@echo "$(GREEN)Demo repository created at $(DEMO_REPO_BASE)$(NC)"

demo-repo-simple: ## Create simple demo repository for CI and quick testing
	@echo "$(BLUE)Creating simple demo repository...$(NC)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/bin/repo-setup-simple.sh "$(DEMO_REPO_BASE)"

demo-repo-workflows: ## Create workflows demo repository for practical workflows screencasts
	@echo "$(BLUE)Creating workflows demo repository...$(NC)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/practical-workflows/bin/repo-setup.sh /tmp/workflows-repo
	@echo "$(GREEN)Workflows demo repository created at /tmp/workflows-repo$(NC)"

demo-repo-beginner: ## Create beginner demo repository for beginner tutorial screencasts
	@echo "$(BLUE)Creating beginner demo repository...$(NC)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/hug-for-beginners/bin/repo-setup.sh /tmp/beginner-repo
	@echo "$(GREEN)Beginner demo repository created at /tmp/beginner-repo$(NC)"

demo-repo-all: demo-repo demo-repo-workflows demo-repo-beginner ## Create all demo repositories

demo-clean: ## Clean demo repository and remote
	@echo "$(BLUE)Cleaning demo repository...$(NC)"
	@rm -rf $(DEMO_REPO_BASE) $(DEMO_REPO_BASE).git
	@echo "$(GREEN)Demo repository cleaned$(NC)"

demo-clean-all: ## Clean all demo repositories
	@echo "$(BLUE)Cleaning all demo repositories...$(NC)"
	@rm -rf $(DEMO_REPO_BASE) $(DEMO_REPO_BASE).git
	@rm -rf /tmp/workflows-repo /tmp/workflows-repo.git
	@rm -rf /tmp/beginner-repo /tmp/beginner-repo.git
	@echo "$(GREEN)All demo repositories cleaned$(NC)"

demo-repo-rebuild: demo-clean demo-repo ## Rebuild demo repository from scratch

demo-repo-rebuild-all: demo-clean-all demo-repo-all ## Rebuild all demo repositories from scratch

demo-repo-status: ## Show status of demo repository
	@echo "$(BLUE)Demo repository status:$(NC)"
	@if [ ! -d $(DEMO_REPO_BASE) ]; then \
		echo "$(YELLOW)Demo repository does not exist$(NC)"; \
		echo "Run 'make demo-repo' to create it"; \
		exit 1; \
	fi; \
	cd $(DEMO_REPO_BASE) && \
	echo "$(GREEN)Repository exists$(NC)" && \
	echo "" && \
	echo "Commits: $$(git rev-list --all --count 2>/dev/null || echo 'N/A')" && \
	echo "Branches: $$(git branch -a 2>/dev/null | wc -l || echo 'N/A')" && \
	echo "Tags: $$(git tag 2>/dev/null | wc -l || echo 'N/A')" && \
	echo "Remote: $$(git remote -v 2>/dev/null | head -1 || echo 'N/A')"; \
	exit 0

.PHONY: test test-unit test-integration test-lib test-check test-deps-install optional-deps-install optional-deps-check
.PHONY: vhs-deps-install
.PHONY: vhs vhs-build vhs-build-one vhs-dry-run vhs-clean vhs-check vhs-regenerate vhs-commit-push
.PHONY: docs-dev docs-build docs-preview deps-docs
.PHONY: install check clean clean-all
.PHONY: demo-repo demo-repo-simple demo-repo-workflows demo-repo-beginner demo-repo-all demo-clean demo-clean-all demo-repo-rebuild demo-repo-rebuild-all demo-repo-status
