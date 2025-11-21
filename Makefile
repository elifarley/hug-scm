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

test: test-bash test-lib-py ## Run all tests (BATS + pytest)
	@echo "$(GREEN)All tests completed!$(NC)"

test-bash: ## Run all BATS-based tests (or specific: TEST_FILE=... TEST_FILTER=... SHOW_FAILING=1)
	@echo "$(BLUE)Running BATS tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh tests/ $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-unit: ## Run only unit tests (or specific: TEST_FILE=... TEST_FILTER=... SHOW_FAILING=1)
	@echo "$(BLUE)Running unit tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/unit/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --unit $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-integration: ## Run only integration tests (or specific: TEST_FILE=... TEST_FILTER=... SHOW_FAILING=1)
	@echo "$(BLUE)Running integration tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/integration/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --integration $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-lib: ## Run only library tests (or specific: TEST_FILE=... TEST_FILTER=... SHOW_FAILING=1)
	@echo "$(BLUE)Running library tests...$(NC)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/lib/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --lib $(if $(SHOW_FAILING),-F) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-check: ## Check test prerequisites without running tests
	@echo "$(BLUE)Checking test prerequisites...$(NC)"
	@echo "$(BLUE)Checking BATS prerequisites...$(NC)"
	./tests/run-tests.sh --check
	@echo "$(BLUE)Checking Python test prerequisites...$(NC)"
	@if cd git-config/lib/python && python3 -m pytest --version >/dev/null 2>&1; then \
		echo "$(GREEN)✓ pytest is available$(NC)"; \
	else \
		echo "$(YELLOW)⚠ pytest not found - install with 'make test-deps-install' or 'make test-deps-py-install'$(NC)"; \
	fi

test-lib-py: ## Run Python library tests using pytest
	@echo "$(BLUE)Running Python library tests...$(NC)"
	@cd git-config/lib/python && \
	if ! python3 -m pytest --version >/dev/null 2>&1; then \
		echo "$(YELLOW)pytest not installed. Installing pytest and dev dependencies...$(NC)"; \
		python3 -m pip install -q -e ".[dev]" || \
		(echo "$(YELLOW)Warning: Could not install dev dependencies. Tests will be skipped.$(NC)" && exit 0); \
	fi; \
	python3 -m pytest tests/ -v --color=yes --tb=short $(if $(TEST_FILTER),-k "$(TEST_FILTER)")

test-lib-py-coverage: ## Run Python library tests with coverage report
	@echo "$(BLUE)Running Python library tests with coverage...$(NC)"
	@cd git-config/lib/python && \
	python3 -m pip install -q -e ".[dev]" 2>/dev/null || true; \
	python3 -m pytest tests/ -v --cov=. --cov-report=term-missing --cov-report=html

test-deps-install: ## Install all test dependencies (BATS + Python)
	@echo "$(BLUE)Installing test dependencies...$(NC)"
	@echo "$(BLUE)Installing BATS dependencies...$(NC)"
	./tests/run-tests.sh --install-deps
	@echo "$(BLUE)Installing Python test dependencies...$(NC)"
	@cd git-config/lib/python && python3 -m pip install -q -e ".[dev]" || \
	(echo "$(YELLOW)Warning: Could not install Python dev dependencies. Python tests may not work.$(NC)")
	@echo "$(GREEN)All test dependencies installed$(NC)"

test-deps-py-install: ## Install Python test dependencies (pytest, coverage, etc.)
	@echo "$(BLUE)Installing Python test dependencies...$(NC)"
	@cd git-config/lib/python && python3 -m pip install -e ".[dev]"
	@echo "$(GREEN)Python test dependencies installed$(NC)"

optional-deps-install: ## Install optional dependencies (gum, etc.)
	@echo "$(BLUE)Installing optional dependencies...$(NC)"
	@bash bin/optional-deps-install.sh

optional-deps-check: ## Check if optional dependencies are installed
	@echo "$(BLUE)Checking optional dependencies...$(NC)"
	@bash bin/optional-deps-install.sh --check

##@ Mock Data Management

mocks-check: ## Check status of recorded mock data
	@echo "$(BLUE)Checking mock data status...$(NC)"
	@cd git-config/lib/python/tests/fixtures && \
	if [ ! -d mocks/git/log ]; then \
		echo "$(YELLOW)⚠ No mock data found$(NC)"; \
		echo "Run 'make mocks-generate' to create mock data"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓ Mock data exists$(NC)"; \
	echo ""; \
	echo "TOML files:"; \
	find mocks -name "*.toml" -type f | sed 's/^/  - /'; \
	echo ""; \
	echo "Output files:"; \
	find mocks -name "*.txt" -type f | wc -l | xargs printf "  %s output files\n"

mocks-generate: ## Regenerate all mock data from real commands
	@echo "$(BLUE)Regenerating all mock data...$(NC)"
	@cd git-config/lib/python/tests/fixtures && python3 generate_mocks.py
	@echo "$(GREEN)✓ All mock data regenerated successfully$(NC)"

mocks-generate-git: ## Regenerate Git command mocks only
	@echo "$(BLUE)Regenerating Git command mocks...$(NC)"
	@cd git-config/lib/python/tests/fixtures && python3 generate_mocks.py
	@echo "$(GREEN)✓ Git mocks regenerated$(NC)"

mocks-regenerate: mocks-generate ## Alias for mocks-generate

mocks-clean: ## Remove all generated mock data
	@echo "$(BLUE)Cleaning mock data...$(NC)"
	@cd git-config/lib/python/tests/fixtures/mocks && \
	find . -name "*.toml" -type f -delete && \
	find . -name "*.txt" -type f -delete
	@echo "$(GREEN)✓ Mock data cleaned$(NC)"
	@echo "$(YELLOW)Run 'make mocks-generate' to recreate$(NC)"

mocks-clean-git: ## Remove Git command mocks only
	@echo "$(BLUE)Cleaning Git command mocks...$(NC)"
	@rm -rf git-config/lib/python/tests/fixtures/mocks/git/log/*.toml
	@rm -rf git-config/lib/python/tests/fixtures/mocks/git/log/outputs/*.txt
	@echo "$(GREEN)✓ Git mocks cleaned$(NC)"

mocks-test-with-regenerate: ## Run Python tests and regenerate mocks on failure
	@echo "$(BLUE)Running Python tests with mock regeneration...$(NC)"
	@cd git-config/lib/python && \
	if ! python3 -m pytest tests/ -v --color=yes --tb=short; then \
		echo "$(YELLOW)Tests failed - regenerating mocks...$(NC)"; \
		cd tests/fixtures && python3 generate_mocks.py; \
		echo "$(BLUE)Retrying tests with fresh mocks...$(NC)"; \
		cd ../.. && python3 -m pytest tests/ -v --color=yes --tb=short; \
	fi
	@echo "$(GREEN)✓ Python tests passed$(NC)"

mocks-validate: ## Validate mock data integrity (TOML + output files match)
	@echo "$(BLUE)Validating mock data integrity...$(NC)"
	@cd git-config/lib/python/tests/fixtures && \
	python3 -c "import tomllib; from pathlib import Path; errors = []; \
[toml_file for toml_file in Path('mocks').rglob('*.toml') if (lambda f: ([errors.append(f'Missing: {f.parent / scenario.get(\"output_file\", \"\")}') for scenario in tomllib.load(open(f, 'rb')).get('scenario', []) if not (f.parent / scenario.get('output_file', '')).exists()], None)[1])(toml_file)]; \
exit(1) if errors and print('\n'.join(errors)) else print('$(GREEN)✓ All mock data is valid$(NC)')"

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

.PHONY: test test-bash test-unit test-integration test-lib test-check test-lib-py test-lib-py-coverage test-deps-install test-deps-py-install optional-deps-install optional-deps-check
.PHONY: mocks-check mocks-generate mocks-generate-git mocks-regenerate mocks-clean mocks-clean-git mocks-test-with-regenerate mocks-validate
.PHONY: vhs-deps-install
.PHONY: vhs vhs-build vhs-build-one vhs-dry-run vhs-clean vhs-check vhs-regenerate vhs-commit-push
.PHONY: docs-dev docs-build docs-preview deps-docs
.PHONY: install check clean clean-all
.PHONY: demo-repo demo-repo-simple demo-repo-workflows demo-repo-beginner demo-repo-all demo-clean demo-clean-all demo-repo-rebuild demo-repo-rebuild-all demo-repo-status
