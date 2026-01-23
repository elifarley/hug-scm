# Makefile for Hug SCM
# A humane, intuitive interface for Git and other version control systems

.PHONY: help
.DEFAULT_GOAL := help
SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-print-directory

# UV command - required for all Python operations
UV_CMD := uv

# Python commands - always use UV (required tool)
PYTHON_CMD := uv run python
PYTEST_CMD := uv run pytest
PIP_CMD := uv pip install

# Terminal color support detection (tput works in $(shell) context)
TERM_COLOR := $(shell tput colors 2>/dev/null)

# Python library directory (absolute path for CI reliability)
PYTHON_LIB_DIR := $(realpath git-config/lib/python)

# === Directory Variables ===
# Centralize demo repo paths (currently scattered)
DEMO_BASE_DIR := /tmp
DEMO_REPO_BASE := $(DEMO_BASE_DIR)/demo-repo
DEMO_WORKFLOWS_REPO := $(DEMO_BASE_DIR)/workflows-repo
DEMO_BEGINNER_REPO := $(DEMO_BASE_DIR)/beginner-repo

# === Shell Script Discovery ===
# Single source of truth for shellcheck targets (repeated 3x)
BASH_SOURCES := $$(find git-config/bin git-config/lib hg-config/bin hg-config/lib bin tests \
    -type f \( -name "*.bash" -o -name "hug-*" -o -name "activate" -o -name "*.bats" \) \
    -not -path "*/.venv/*" -not -name "*.md")

# === Path Validation ===
# Fail fast if Python library directory is missing
ifeq ($(PYTHON_LIB_DIR),)
    $(error Python library directory not found at git-config/lib/python)
endif

ifeq ($(TERM_COLOR),0)
    BOLD :=
    RESET :=
    GREEN :=
    YELLOW :=
    BLUE :=
    CYAN :=
    RED :=
else
    BOLD := \033[1m
    RESET := \033[0m
    GREEN := \033[32m
    YELLOW := \033[33m
    BLUE := \033[34m
    CYAN := \033[36m
    RED := \033[31m
endif

# Test customization variables (optional)
TEST_FILE ?=
TEST_FILTER ?=
TEST_SHOW_ALL_RESULTS ?=

# Setup PATH for demo repository creation (includes hug commands)
HUG_BIN_PATH := $(shell pwd)/git-config/bin
DEMO_REPO_ENV := export PATH="$$PATH:$(HUG_BIN_PATH)" &&

# === Reusable Macros ===

# Macro: run_bats_test
# Usage: $(call run_bats_test,<display-name>,<default-dir>,<flag>)
# Parameters:
#   $1 = Display name (e.g., "unit", "integration")
#   $2 = Default directory for TEST_FILE basename (e.g., "tests/unit/")
#   $3 = Flag to pass to run-tests.sh (e.g., "--unit", "--integration")
define run_bats_test
@printf "$(BLUE)Running $(1) tests...$(RESET)\n"
@if [ -n "$(TEST_FILE)" ]; then \
    case "$(TEST_FILE)" in \
    tests/*) \
        ./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
        ;; \
    *) \
        ADJUSTED_FILE="$(2)$$(basename "$(TEST_FILE)")"; \
        ./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
        ;; \
    esac; \
else \
    ./tests/run-tests.sh $(3) $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
fi
endef

# Macro: ensure_pytest
# Ensures pytest is available before running Python tests
define ensure_pytest
@cd git-config/lib/python && \
    if ! $(PYTEST_CMD) --version >/dev/null 2>&1; then \
        printf "$(YELLOW)pytest not installed. Installing pytest and dev dependencies...$(RESET)\n"; \
        $(PIP_CMD) -q -e ".[dev]" || \
        (printf "$(YELLOW)Warning: Could not install dev dependencies. Tests will be skipped.$(RESET)\n" && exit 0); \
    fi; \
    cd - > /dev/null
endef

# Macro: install_platform_pkg
# Usage: $(call install_platform_pkg,<package-name>,<url>)
define install_platform_pkg
@if command -v $(1) >/dev/null 2>&1; then \
    printf "$(GREEN)✓ $(1) already installed$(RESET)\n"; \
else \
    if [ "$$(uname)" = "Darwin" ]; then \
        brew install $(1) 2>/dev/null || printf "$(YELLOW)⚠ Install $(1) manually from $(2)$(RESET)\n"; \
    elif [ -f /etc/debian_version ]; then \
        sudo apt-get install -y $(1) 2>/dev/null || printf "$(YELLOW)⚠ Install $(1) manually from $(2)$(RESET)\n"; \
    else \
        printf "$(YELLOW)⚠ Install $(1) manually from $(2)$(RESET)\n"; \
    fi; \
fi
endef

# === Output Helper Macros ===
# Usage: $(call print_info,Your message here)
# These use printf to properly interpret ANSI escape sequences from Make variables
# (Unlike echo, printf correctly interprets escape sequences passed from Make)

define print_info
@printf "$(BLUE)$(1)$(RESET)\n"
endef

define print_success
@printf "$(GREEN)$(1)$(RESET)\n"
endef

define print_warning
@printf "$(YELLOW)$(1)$(RESET)\n"
endef

define print_error
@printf "$(RED)$(1)$(RESET)\n"
endef

##@ General

help: ## Show this help message
	@printf "$(BOLD)$(CYAN)Hug SCM - Makefile Commands$(RESET)\n"
	@printf "\n"
	@printf "$(BOLD)Environment:$(RESET)\n"
	@printf "  $(GREEN)make doctor$(RESET)         - Check environment and tool readiness\n"
	@printf "  $(GREEN)make dev-env-init$(RESET)   - Create virtual environment (one-time)\n"
	@printf "  $(GREEN)make dev-deps-sync$(RESET)  - Sync dependencies from lockfiles\n"
	@printf "\n"
	@printf "$(BOLD)Code Quality:$(RESET)\n"
	@printf "  $(GREEN)make format$(RESET)         - Format code (LLM-friendly)\n"
	@printf "  $(GREEN)make format-verbose$(RESET) - Format code (show changes)\n"
	@printf "  $(GREEN)make lint$(RESET)           - Run linting (LLM-friendly)\n"
	@printf "  $(GREEN)make lint-verbose$(RESET)   - Run linting (detailed)\n"
	@printf "  $(GREEN)make typecheck$(RESET)      - Type check Python (LLM-friendly)\n"
	@printf "  $(GREEN)make typecheck-verbose$(RESET) - Type check Python (detailed)\n"
	@printf "  $(GREEN)make sanitize-check$(RESET)  - Read-only static checks (lint + typecheck)\n"
	@printf "  $(GREEN)make sanitize-check-verbose$(RESET) - Read-only static checks (detailed)\n"
	@printf "  $(GREEN)make sanitize$(RESET)       - Run all static checks (format + lint + typecheck)\n"
	@printf "  $(GREEN)make sanitize-verbose$(RESET) - Run all static checks (detailed)\n"
	@printf "\n"
	@printf "$(BOLD)Testing:$(RESET)\n"
	@printf "  $(CYAN)make test-unit$(RESET)       - Run unit tests (LLM-friendly)\n"
	@printf "  $(CYAN)make test-unit-verbose$(RESET) - Run unit tests (detailed)\n"
	@printf "  $(CYAN)make test-integration$(RESET) - Run integration tests (LLM-friendly)\n"
	@printf "  $(CYAN)make test-integration-verbose$(RESET) - Run integration tests (detailed)\n"
	@printf "  $(CYAN)make test-lib-py$(RESET)     - Run Python library tests\n"
	@printf "  $(CYAN)make test$(RESET)            - Run all behavioral tests (unit + integration)\n"
	@printf "  $(CYAN)make test-verbose$(RESET)    - Run all behavioral tests (detailed)\n"
	@printf "  $(CYAN)make test-full$(RESET)       - Run all tests including prerequisites and library tests\n"
	@printf "  $(CYAN)make test-full-verbose$(RESET) - Run all tests with detailed output\n"
	@printf "\n"
	@printf "$(BOLD)Gates:$(RESET)\n"
	@printf "  $(GREEN)make check$(RESET)          - Fast merge gate (sanitize + unit tests)\n"
	@printf "  $(GREEN)make check-verbose$(RESET)  - Merge gate with detailed output\n"
	@printf "  $(GREEN)make check-full$(RESET)     - Enhanced merge gate (includes library tests)\n"
	@printf "  $(GREEN)make check-full-verbose$(RESET) - Enhanced merge gate with detailed output\n"
	@printf "  $(GREEN)make validate$(RESET)       - Full release validation (sanitize + test + coverage)\n"
	@printf "  $(GREEN)make validate-full$(RESET)  - Full release validation including library tests\n"
	@printf "  $(GREEN)make coverage$(RESET)       - Enforce test coverage thresholds\n"
	@printf "  $(GREEN)make pre-commit$(RESET)     - Pre-commit hook\n"
	@printf "\n"
	@printf "$(BOLD)Debugging:$(RESET)\n"
	@printf "  $(CYAN)make debug-vars$(RESET)      - Dump all Makefile variables\n"
	@printf "  $(CYAN)make debug-self-test$(RESET) - Verify Makefile syntax and variables\n"
	@printf "  $(CYAN)make debug-dry-run$(RESET)   - Show what would execute without running\n"
	@printf "  $(CYAN)make debug$(RESET)           - Run all debug checks\n"
	@printf "\n"
	@printf "$(BOLD)Documentation:$(RESET)\n"
	@grep -E '^(docs-.*):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "$(BOLD)Screencasts (VHS):$(RESET)\n"
	@grep -E '^vhs.*:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "$(BOLD)Installation & Setup:$(RESET)\n"
	@printf "  $(GREEN)make install$(RESET)        - Install Hug SCM\n"
	@grep -E '^(dev-.*):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "$(BOLD)Utilities:$(RESET)\n"
	@grep -E '^(clean|demo-|mocks-):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "For full test filtering options, see $(CYAN)TESTING.md$(RESET)\n"

##@ Testing

test-lump: test-lib-py test-bash  ## Run all tests (BATS + pytest)
	$(call print_success,All tests completed!)

test: ## Run all behavioral tests (PRD-compliant: unit + integration)
	@$(MAKE) test-unit
	@$(MAKE) test-integration
	$(call print_success,✅ All tests completed!)

test-full: ## Run all tests including prerequisites and library tests
	@$(MAKE) test-check
	@$(MAKE) test-lib-py
	@$(MAKE) test-lib
	@$(MAKE) test-unit
	@$(MAKE) test-integration
	$(call print_success,✅ All tests completed!)

test-bash: ## Run all BATS-based tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	$(call run_bats_test,BATS,tests/,tests/)

test-unit: ## Run only unit tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	$(call run_bats_test,unit,tests/unit/,--unit)

test-integration: ## Run only integration tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	$(call run_bats_test,integration,tests/integration/,--integration)

test-lib: ## Run only library tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	$(call run_bats_test,library,tests/lib/,--lib)

test-check: ## Check test prerequisites without actually running tests
	$(call print_info,Checking test prerequisites...)
	./tests/run-tests.sh --check
	$(call print_info,Checking Python test prerequisites...)
	@if cd git-config/lib/python && $(PYTEST_CMD) --version >/dev/null 2>&1; then \
		printf "$(GREEN)✓ pytest is available$(RESET)\n"; \
	else \
		printf "$(YELLOW)⚠ pytest not found - install with 'make test-deps-install' or 'make test-deps-py-install'$(RESET)\n"; \
	fi

test-lib-py: ## Run Python library tests (pytest, LLM-friendly)
	$(call print_info,Running Python library tests...)
	$(ensure_pytest)
	@cd git-config/lib/python && \
	$(PYTEST_CMD) tests/ -q --color=yes --tb=short $(if $(TEST_FILTER),-k "$(TEST_FILTER)")

test-lib-py-coverage: ## Run Python library tests with coverage report
	$(call print_info,Running Python library tests with coverage...)
	$(ensure_pytest)
	@cd git-config/lib/python && \
	$(PYTEST_CMD) tests/ -v --cov=. --cov-report=term-missing --cov-report=html

test-lib-py-verbose: ## Run Python library tests (detailed output)
	$(call print_info,Running Python library tests (verbose)...)
	$(ensure_pytest)
	@cd git-config/lib/python && \
	$(PYTEST_CMD) tests/ -v --color=yes --tb=short $(if $(TEST_FILTER),-k "$(TEST_FILTER)")

test-unit-verbose: ## Run unit tests (detailed output)
	$(call print_info,Running unit tests...)
	@$(MAKE) test-unit TEST_SHOW_ALL_RESULTS=1

test-integration-verbose: ## Run integration tests (detailed output)
	$(call print_info,Running integration tests...)
	@$(MAKE) test-integration TEST_SHOW_ALL_RESULTS=1

test-verbose: ## Run all behavioral tests (detailed output)
	@$(MAKE) test-unit-verbose
	@$(MAKE) test-integration-verbose
	$(call print_success,✅ All tests completed!)

test-full-verbose: ## Run all tests with detailed output
	@$(MAKE) test-check
	@$(MAKE) test-lib-py-verbose
	@$(MAKE) test-lib TEST_SHOW_ALL_RESULTS=1
	@$(MAKE) test-unit-verbose
	@$(MAKE) test-integration-verbose
	$(call print_success,✅ All tests completed!)

dev-test-deps-install: ## Install all test dependencies (BATS + Python)
	$(call print_info,Installing test dependencies...)
	$(call print_info,Installing BATS dependencies...)
	./tests/run-tests.sh --install-deps
	$(call print_info,Installing Python test dependencies...)
	@sh -c 'if command -v uv >/dev/null 2>&1; then printf "$(CYAN)Using UV for fast dependency installation...$(RESET)\n"; fi'
	@cd git-config/lib/python && $(PIP_CMD) -q -e ".[dev]" || \
	(printf "$(YELLOW)Warning: Could not install Python dev dependencies. Python tests may not work.$(RESET)\n")
	$(call print_success,All test dependencies installed)

test-deps-install: ## Install all test dependencies (DEPRECATED: use 'dev-test-deps-install')
	$(call print_warning,⚠ 'test-deps-install' is deprecated, use 'make dev-test-deps-install')
	@$(MAKE) dev-test-deps-install

test-deps-py-install: ## Install Python test dependencies (DEPRECATED: use 'dev-deps-sync')
	$(call print_warning,⚠ 'test-deps-py-install' is deprecated, use 'make dev-deps-sync')
	@$(MAKE) dev-deps-sync

dev-deps-sync: ## Sync dependencies from lockfiles
	$(call print_info,Syncing dependencies...)
	@test -d .venv || (printf "$(RED)❌ .venv not found$(RESET)\n" && printf "$(BLUE)ℹ️ Run: make dev-env-init$(RESET)\n" && exit 1)
	$(call print_info,Installing Python test dependencies...)
	@sh -c 'if command -v uv >/dev/null 2>&1; then printf "$(CYAN)Using UV for fast dependency installation...$(RESET)\n"; fi'
	@cd git-config/lib/python && $(PIP_CMD) -e ".[dev]"
	$(call print_success,Python test dependencies installed)

dev-optional-install: ## Install optional development dependencies (gum, shfmt, ShellCheck)
	$(call print_info,Installing optional dependencies...)
	@bash bin/optional-deps-install.sh
	$(call print_info,Installing shfmt...)
	$(call install_platform_pkg,shfmt,https://github.com/mvdan/sh)
	$(call print_info,Installing ShellCheck...)
	$(call install_platform_pkg,shellcheck,https://www.shellcheck.net/)

optional-deps-install: ## Install optional dependencies (DEPRECATED: use 'dev-optional-install')
	$(call print_warning,⚠ 'optional-deps-install' is deprecated, use 'make dev-optional-install')
	@$(MAKE) dev-optional-install

dev-optional-check: ## Check if optional development dependencies are installed
	$(call print_info,Checking optional dependencies...)
	@bash bin/optional-deps-install.sh --check

optional-deps-check: ## Check if optional dependencies are installed (DEPRECATED: use 'dev-optional-check')
	$(call print_warning,⚠ 'optional-deps-check' is deprecated, use 'make dev-optional-check')
	@$(MAKE) dev-optional-check

doctor: ## Check environment and tool readiness
	$(call print_info,Checking environment...)
	@echo ""
	@echo "Required tools:"
	@command -v git >/dev/null || (printf "$(RED)❌ git not found$(RESET)\n" && exit 1)
	@printf "$(GREEN)✅ git found$(RESET)\n"
	@command -v bash >/dev/null || (printf "$(RED)❌ bash not found$(RESET)\n" && exit 1)
	@printf "$(GREEN)✅ bash found$(RESET)\n"
	@command -v python3 >/dev/null || (printf "$(RED)❌ python3 not found$(RESET)\n" && exit 1)
	@printf "$(GREEN)✅ python3 found$(RESET)\n"
	@echo ""
	@echo "Optional tools (for static checks):"
	@command -v shfmt >/dev/null || printf "$(YELLOW)⚠ shfmt not found (run 'make dev-optional-install')$(RESET)\n"
	@command -v shellcheck >/dev/null || printf "$(YELLOW)⚠ ShellCheck not found (run 'make dev-optional-install')$(RESET)\n"
	@echo ""
	@echo "UV (required for Python operations):"
	@if command -v uv >/dev/null 2>&1; then \
		printf "$(GREEN)✅ UV available$(RESET)\n"; \
	else \
		printf "$(RED)❌ UV not found (required, run 'make python-install-uv')$(RESET)\n"; \
		exit 1; \
	fi
	@echo ""
	@echo "Virtual Environment:"
	@if [ -d .venv ]; then \
		printf "$(GREEN)✅ .venv/ exists$(RESET)\n"; \
	else \
		printf "$(YELLOW)⚠ .venv/ not found (run 'make dev-env-init')$(RESET)\n"; \
	fi
	@echo ""
	@echo "Test frameworks:"
	@./tests/run-tests.sh --check >/dev/null 2>&1 || (printf "$(RED)❌ BATS not ready$(RESET)\n" && exit 1)
	@printf "$(GREEN)✅ BATS ready$(RESET)\n"
	@if cd git-config/lib/python && $(PYTEST_CMD) --version >/dev/null 2>&1; then \
		cd - > /dev/null && printf "$(GREEN)✅ pytest ready$(RESET)\n"; \
	else \
		cd - > /dev/null && printf "$(YELLOW)⚠ pytest not found (run 'make test-deps-py-install')$(RESET)\n"; \
	fi
	@echo ""
	@printf "$(GREEN)✅ Environment check complete$(RESET)\n"

python-check: ## Check Python environment (DEPRECATED: use 'doctor')
	$(call print_warning,⚠ 'python-check' is deprecated, use 'make doctor')
	@$(MAKE) doctor

python-venv-create: ## Create virtual environment using UV (fast) (DEPRECATED: use 'dev-env-init')
	$(call print_warning,⚠ 'python-venv-create' is deprecated, use 'make dev-env-init')
	@$(MAKE) dev-env-init

dev-env-init: ## Create virtual environment (one-time setup)
	$(call print_info,Creating virtual environment...)
	@command -v uv >/dev/null 2>&1 || { \
		printf "$(RED)❌ UV is required$(RESET)\n"; \
		printf "$(CYAN)ℹ️  Install with: make python-install-uv$(RESET)\n"; \
		exit 1; \
	}
	@$(UV_CMD) venv .venv
	$(call print_success,✓ Virtual environment created with UV)
	@printf "$(CYAN)Run 'make test-deps-py-install' to install dependencies$(RESET)\n"

python-install-uv: ## Install UV package manager
	$(call print_info,Installing UV...)
	@curl -LsSf https://astral.sh/uv/install.sh | sh
	$(call print_success,UV installed successfully)
	@printf "$(CYAN)Run 'source ~/.bashrc' or restart your shell to use UV$(RESET)\n"

##@ Mock Data Management

mocks-check: ## Check status of recorded mock data
	$(call print_info,Checking mock data status...)
	@cd git-config/lib/python/tests/fixtures && \
	if [ ! -d mocks/git/log ]; then \
		printf "$(YELLOW)⚠ No mock data found$(RESET)\n"; \
		echo "Run 'make mocks-generate' to create mock data"; \
		exit 1; \
	fi; \
	printf "$(GREEN)✓ Mock data exists$(RESET)\n"; \
	echo ""; \
	echo "TOML files:"; \
	find mocks -name "*.toml" -type f | sed 's/^/  - /'; \
	echo ""; \
	echo "Output files:"; \
	find mocks -name "*.txt" -type f | wc -l | xargs printf "  %s output files\n"

mocks-generate: ## Regenerate all mock data from real commands
	$(call print_info,Regenerating all mock data...)
	@cd git-config/lib/python/tests/fixtures && $(PYTHON_CMD) generate_mocks.py
	$(call print_success,✓ All mock data regenerated successfully)

mocks-generate-git: ## Regenerate Git command mocks only
	$(call print_info,Regenerating Git command mocks...)
	@cd git-config/lib/python/tests/fixtures && $(PYTHON_CMD) generate_mocks.py
	$(call print_success,✓ Git mocks regenerated)

mocks-regenerate: mocks-generate ## Alias for mocks-generate

mocks-clean: ## Remove all generated mock data
	$(call print_info,Cleaning mock data...)
	@cd git-config/lib/python/tests/fixtures/mocks && \
	find . -name "*.toml" -type f -delete && \
	find . -name "*.txt" -type f -delete
	$(call print_success,✓ Mock data cleaned)
	$(call print_warning,Run 'make mocks-generate' to recreate)

mocks-clean-git: ## Remove Git command mocks only
	$(call print_info,Cleaning Git command mocks...)
	@rm -rf git-config/lib/python/tests/fixtures/mocks/git/log/*.toml
	@rm -rf git-config/lib/python/tests/fixtures/mocks/git/log/outputs/*.txt
	$(call print_success,✓ Git mocks cleaned)

mocks-test-with-regenerate: ## Run Python tests and regenerate mocks on failure
	$(call print_info,Running Python tests with mock regeneration...)
	@cd git-config/lib/python && \
	if ! $(PYTEST_CMD) tests/ -v --color=yes --tb=short; then \
		printf "$(YELLOW)Tests failed - regenerating mocks...$(RESET)\n"; \
		cd tests/fixtures && $(PYTHON_CMD) generate_mocks.py; \
		printf "$(BLUE)Retrying tests with fresh mocks...$(RESET)\n"; \
		cd ../.. && $(PYTEST_CMD) tests/ -v --color=yes --tb=short; \
	fi
	$(call print_success,✓ Python tests passed)

mocks-validate: ## Validate mock data integrity (TOML + output files match)
	$(call print_info,Validating mock data integrity...)
	@cd git-config/lib/python/tests/fixtures && \
	$(PYTHON_CMD) -c "import tomllib; from pathlib import Path; errors = []; \
[toml_file for toml_file in Path('mocks').rglob('*.toml') if (lambda f: ([errors.append(f'Missing: {f.parent / scenario.get(\"output_file\", \"\")}') for scenario in tomllib.load(open(f, 'rb')).get('scenario', []) if not (f.parent / scenario.get('output_file', '')).exists()], None)[1])(toml_file)]; \
exit(1) if errors and print('\n'.join(errors)) else print('$(GREEN)✓ All mock data is valid$(RESET)')"

##@ VHS Screencasts

vhs-deps-install: ## Install VHS tool if not present
	$(call print_info,Installing VHS dependencies...)
	@bash docs/screencasts/bin/vhs-build.sh --install-deps

vhs-check: vhs-deps-install ## Check if VHS is installed
	$(call print_info,Checking VHS installation...)
	@bash docs/screencasts/bin/vhs-build.sh --check

vhs: demo-repo-rebuild-all vhs-deps-install ## Build all GIF/PNG images from VHS tape files
	$(call print_info,Building all VHS screencasts...)
	@bash docs/screencasts/bin/vhs-build.sh --all
	@$(MAKE) vhs-strip-metadata

vhs-build: vhs ## Alias for vhs target

vhs-build-one: vhs-check ## Build a specific VHS tape file (usage: make vhs-build-one TAPE=filename.tape)
	$(call print_info,Building VHS screencast: $(TAPE))
	@if [ -z "$(TAPE)" ]; then \
		printf "$(YELLOW)Usage: make vhs-build-one TAPE=filename.tape$(RESET)\n"; \
		exit 1; \
	fi
	@bash docs/screencasts/bin/vhs-build.sh "$(TAPE)"
	@$(MAKE) vhs-strip-metadata

vhs-dry-run: ## Show what would be built without building
	$(call print_info,Dry run - showing what would be built...)
	@bash docs/screencasts/bin/vhs-build.sh --dry-run --all

vhs-strip-metadata: ## Strip metadata from all PNG/GIF images to make them deterministic
	$(call print_info,Stripping metadata from images...)
	@bash docs/screencasts/bin/vhs-strip-metadata.sh && $(call print_success,Metadata stripped successfully)

vhs-clean: ## Remove generated GIF/PNG files from VHS
	@bash docs/screencasts/bin/vhs-clean.sh

vhs-regenerate: demo-repo vhs-deps-install ## Regenerate VHS images for CI (demo + essential tapes)
	$(call print_info,Regenerating VHS images...)
	@bash docs/screencasts/bin/vhs-build.sh hug-l.tape hug-lo.tape hug-lol.tape hug-sl-states.tape
	$(call print_info,Cleaning up frame directories...)
	@bash docs/screencasts/bin/vhs-cleanup-frames.sh
	$(call print_info,Verifying cleanup...)
	@bash docs/screencasts/bin/vhs-cleanup-frames.sh --verify-strict
	@$(MAKE) vhs-strip-metadata
	$(call print_success,VHS images regenerated successfully)

vhs-commit-push: ## Commit and push VHS image changes (for CI/automation)
	@bash docs/screencasts/bin/vhs-commit-push.sh

##@ Documentation

docs-dev: ## Start documentation development server
	$(call print_info,Starting documentation server...)
	npm run docs:dev

docs-build: ## Build documentation for production
	$(call print_info,Building documentation...)
	npm run docs:build

docs-preview: ## Preview built documentation
	$(call print_info,Previewing documentation...)
	npm run docs:preview

##@ Installation

# NOTE: 'install' is a prohibited name in makefile-dev PRD (ambiguous).
# Exception: This target installs the Hug SCM application itself, not dev dependencies.
# Alternative names considered: user-install, app-install (kept 'install' for discoverability).
install: ## Install Hug SCM to your home directory
	$(call print_info,Installing Hug SCM...)
	./install.sh
	$(call print_success,Installation complete!)
	@echo "Run 'source bin/activate' to activate Hug"

docs-deps-install: ## Install documentation dependencies
	$(call print_info,Installing documentation dependencies...)
	npm ci

deps-docs: ## Install documentation dependencies (DEPRECATED: use 'docs-deps-install')
	$(call print_warning,⚠ 'deps-docs' is deprecated, use 'make docs-deps-install')
	@$(MAKE) docs-deps-install

##@ Development

##@ Debugging

debug-vars: ## Dump all Makefile variables for debugging
	@printf "$(BLUE)=== Makefile Variables ===$(RESET)\n"
	@echo "PYTHON_LIB_DIR=$(PYTHON_LIB_DIR)"
	@echo "UV_CMD=$(UV_CMD)"
	@echo "PYTHON_CMD=$(PYTHON_CMD)"
	@echo "PYTEST_CMD=$(PYTEST_CMD)"
	@echo "PIP_CMD=$(PIP_CMD)"
	@echo "DEMO_REPO_BASE=$(DEMO_REPO_BASE)"
	@echo "DEMO_WORKFLOWS_REPO=$(DEMO_WORKFLOWS_REPO)"
	@echo "DEMO_BEGINNER_REPO=$(DEMO_BEGINNER_REPO)"
	@echo "TERM_COLOR=$(TERM_COLOR)"
	@echo "SHELL=$(SHELL)"
	@echo "MAKEFLAGS=$(MAKEFLAGS)"

debug-self-test: ## Verify Makefile syntax and critical variables
	$(call print_info,Testing Makefile syntax...)
	@make -n test-unit >/dev/null 2>&1 || (printf "$(RED)✗ Makefile syntax error$(RESET)\n" && exit 1)
	@printf "$(GREEN)✓ Syntax OK$(RESET)\n"
	$(call print_info,Testing critical variables...)
	@test -n "$(PYTHON_LIB_DIR)" || (printf "$(RED)✗ PYTHON_LIB_DIR not set$(RESET)\n" && exit 1)
	@test -d "$(PYTHON_LIB_DIR)" || printf "$(YELLOW)⚠ PYTHON_LIB_DIR directory doesn't exist yet$(RESET)\n"
	@printf "$(GREEN)✓ Variables OK$(RESET)\n"

debug-dry-run: ## Show what targets would execute without running
	$(call print_info,Dry run - showing target recipes...)
	@echo "To see specific target recipe, use: make -n <target>"
	@echo "Example: make -n test-unit"

debug: debug-vars debug-self-test ## Run all debug checks
	$(call print_success,✓ Debug checks complete)

format: ## Format code (LLM-friendly: summary only)
	@printf "$(BLUE)Formatting Bash scripts...$(RESET)\n"
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -sr git-config/bin/ git-config/lib/ hg-config/bin/ hg-config/lib/ bin/ tests/ 2>/dev/null || true; \
		printf "$(GREEN)✅ Bash formatting OK$(RESET)\n"; \
	else \
		printf "$(YELLOW)⚠ shfmt not found - run 'make optional-deps-install'$(RESET)\n"; \
	fi
	@printf "$(BLUE)Formatting Python helpers...$(RESET)\n"
	@if command -v uv >/dev/null 2>&1; then \
		$(UV_CMD) run --directory git-config/lib/python ruff format --quiet .; \
		printf "$(GREEN)✅ Python formatting OK$(RESET)\n"; \
	else \
		printf "$(YELLOW)⚠ UV not available - skipping Python formatting$(RESET)\n"; \
	fi
	@printf "$(GREEN)✅ Formatting complete$(RESET)\n"

format-verbose: ## Format code (show changes)
	@printf "$(BLUE)Formatting Bash scripts...$(RESET)\n"
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -sr -d git-config/bin/ git-config/lib/ hg-config/bin/ hg-config/lib/ bin/ tests/; \
	else \
		printf "$(YELLOW)⚠ shfmt not found$(RESET)\n"; \
	fi
	@printf "$(BLUE)Formatting Python helpers...$(RESET)\n"
	@if command -v uv >/dev/null 2>&1; then \
		$(UV_CMD) run --directory git-config/lib/python --extra dev ruff format .; \
	else \
		printf "$(YELLOW)⚠ UV not available$(RESET)\n"; \
	fi

lint: ## Run linting checks (LLM-friendly: summary only)
	@printf "$(BLUE)Linting Bash scripts...$(RESET)\n"
	@if command -v shellcheck >/dev/null 2>&1; then \
		output=$$(shellcheck -S error $(BASH_SOURCES) 2>&1); \
		if echo "$$output" | grep -q 'line [0-9]*:'; then \
			printf "\n$${RED}✗ Bash linting errors found:$${RESET}\n"; \
			echo "$$output"; \
			exit 1; \
		else \
			printf "$(GREEN)✅ Bash linting OK$(RESET)\n"; \
		fi; \
	else \
		printf "$(YELLOW)⚠ ShellCheck not found - run 'make optional-deps-install'$(RESET)\n"; \
	fi
	@printf "$(BLUE)Linting Python helpers...$(RESET)\n"
	@if command -v uv >/dev/null 2>&1; then \
		output=$$($(UV_CMD) run --directory git-config/lib/python --extra dev ruff check --output-format=concise . 2>&1 | grep -vE "(VIRTUAL_ENV|All checks passed)" || true); \
		if [ -n "$$output" ]; then \
			printf "$${RED}✗ Python linting errors found:$${RESET}\n"; \
			echo "$$output"; \
			exit 1; \
		else \
			printf "$(GREEN)✅ Python linting OK$(RESET)\n"; \
		fi; \
	else \
		printf "$(YELLOW)⚠ UV not available - skipping Python linting$(RESET)\n"; \
	fi

lint-verbose: ## Run linting (detailed output)
	@printf "$(BLUE)Linting Bash scripts...$(RESET)\n"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(BASH_SOURCES); \
	else \
		printf "$(YELLOW)⚠ ShellCheck not found$(RESET)\n"; \
	fi
	@printf "$(BLUE)Linting Python helpers...$(RESET)\n"
	@if command -v uv >/dev/null 2>&1; then \
		$(UV_CMD) run --directory git-config/lib/python --extra dev ruff check .; \
	else \
		printf "$(YELLOW)⚠ UV not available$(RESET)\n"; \
	fi

lint-errors-only: ## Run shellcheck showing only error-level issues (debug CI failures)
	@printf "$(BLUE)Linting Bash scripts (error-level only)...$(RESET)\n"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S error $(BASH_SOURCES); \
	else \
		printf "$(YELLOW)⚠ ShellCheck not found$(RESET)\n"; \
	fi

typecheck: ## Type check Python code (LLM-friendly: summary only)
	@printf "$(BLUE)Type checking Python helpers...$(RESET)\n"
	@if command -v uv >/dev/null 2>&1; then \
		output=$$($(UV_CMD) run --directory "$(PYTHON_LIB_DIR)" --extra dev mypy --no-pretty . 2>&1); \
		if echo "$$output" | grep -q 'error:'; then \
			printf "$${RED}✗ Type checking errors found:$${RESET}\n"; \
			echo "$$output"; \
			exit 1; \
		else \
			printf "$(GREEN)✅ Type checking OK$(RESET)\n"; \
		fi; \
	else \
		printf "$(YELLOW)⚠ UV not available - skipping type check$(RESET)\n"; \
	fi

typecheck-verbose: ## Type check Python code (detailed)
	@printf "$(BLUE)Type checking Python helpers...$(RESET)\n"
	@if command -v uv >/dev/null 2>&1; then \
		$(UV_CMD) run --directory "$(PYTHON_LIB_DIR)" --extra dev mypy .; \
	else \
		printf "$(YELLOW)⚠ UV not available$(RESET)\n"; \
	fi

sanitize-check: ## Read-only static checks (lint + typecheck)
	@$(MAKE) lint
	@$(MAKE) typecheck
	@printf "$(GREEN)✅ Static checks complete$(RESET)\n"

sanitize-check-verbose: ## Read-only static checks with detailed output
	@$(MAKE) lint-verbose
	@$(MAKE) typecheck-verbose
	@printf "$(GREEN)✅ Static checks complete$(RESET)\n"

sanitize: ## Run all static checks (format + lint + typecheck)
	@$(MAKE) format
	@$(MAKE) sanitize-check

sanitize-verbose: ## Run all static checks with detailed output
	@$(MAKE) format-verbose
	@$(MAKE) sanitize-check-verbose

# === PRD-Compliant Fast Gate ===
check: ## Fast merge gate (sanitize + unit tests only - PRD-compliant)
	@$(MAKE) sanitize
	@$(MAKE) test-unit
	$(call print_success,✅ Fast checks passed)

check-verbose: ## Fast merge gate with detailed output
	@$(MAKE) sanitize-verbose
	@$(MAKE) test-unit-verbose
	$(call print_success,✅ Fast checks passed)

check-full: ## Enhanced merge gate (includes library tests)
	@$(MAKE) sanitize
	@$(MAKE) test-check
	@$(MAKE) test-lib-py
	@$(MAKE) test-lib
	$(call print_success,✅ Enhanced checks passed)

check-full-verbose: ## Enhanced merge gate with detailed output
	@$(MAKE) sanitize-verbose
	@$(MAKE) test-check
	@$(MAKE) test-lib-py-verbose
	@$(MAKE) test-lib TEST_SHOW_ALL_RESULTS=1
	@$(MAKE) test-unit-verbose
	@$(MAKE) test-integration-verbose
	$(call print_success,✅ Enhanced checks passed)

pre-commit: ## Run checks and tests before commit (git hook target)
	@$(MAKE) check
	$(call print_success,✓ Pre-commit checks complete)

coverage: test-lib-py-coverage ## Enforce test coverage thresholds
	$(call print_success,✅ Coverage check complete)

validate: ## Full release validation (sanitize + test + coverage)
	@$(MAKE) sanitize
	@$(MAKE) test
	@$(MAKE) coverage
	$(call print_success,✅ Release validation complete)

validate-full: ## Full release validation including library tests
	@$(MAKE) sanitize
	@$(MAKE) test-full
	@$(MAKE) coverage
	$(call print_success,✅ Release validation complete)

ci: ## Run full CI pipeline (all tests)
	@$(MAKE) sanitize-check
	@$(MAKE) test
	@printf "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)\n"
	@printf "$(GREEN)✓ CI Pipeline Complete$(RESET)\n"
	@printf "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)\n"

clean: ## Clean build artifacts and temporary files
	$(call print_info,Cleaning build artifacts...)
	rm -rf docs/.vitepress/dist
	rm -rf docs/.vitepress/cache
	rm -rf node_modules/.vite
	$(call print_success,Clean complete!)

clean-all: clean demo-clean ## Clean everything including node_modules
	$(call print_info,Cleaning everything...)
	rm -rf node_modules
	$(call print_success,Deep clean complete!)

##@ Demo Repository

demo-repo: ## Create demo repository for tutorials and screencasts
	$(call print_info,Creating demo repository...)
	@$(DEMO_REPO_ENV) bash docs/screencasts/bin/repo-setup.sh "$(DEMO_REPO_BASE)"
	$(call print_success,Demo repository created at $(DEMO_REPO_BASE))

demo-repo-simple: ## Create simple demo repository for CI and quick testing
	$(call print_info,Creating simple demo repository...)
	@$(DEMO_REPO_ENV) bash docs/screencasts/bin/repo-setup-simple.sh "$(DEMO_REPO_BASE)"

demo-repo-workflows: ## Create workflows demo repository for practical workflows screencasts
	$(call print_info,Creating workflows demo repository...)
	@$(DEMO_REPO_ENV) bash docs/screencasts/practical-workflows/bin/repo-setup.sh "$(DEMO_WORKFLOWS_REPO)"
	$(call print_success,Workflows demo repository created at $(DEMO_WORKFLOWS_REPO))

demo-repo-beginner: ## Create beginner demo repository for beginner tutorial screencasts
	$(call print_info,Creating beginner demo repository...)
	@$(DEMO_REPO_ENV) bash docs/screencasts/hug-for-beginners/bin/repo-setup.sh "$(DEMO_BEGINNER_REPO)"
	$(call print_success,Beginner demo repository created at $(DEMO_BEGINNER_REPO))

demo-repo-all: demo-repo demo-repo-workflows demo-repo-beginner ## Create all demo repositories

demo-clean: ## Clean demo repository and remote
	$(call print_info,Cleaning demo repository...)
	@rm -rf $(DEMO_REPO_BASE) $(DEMO_REPO_BASE).git
	$(call print_success,Demo repository cleaned)

demo-clean-all: ## Clean all demo repositories
	$(call print_info,Cleaning all demo repositories...)
	@rm -rf $(DEMO_REPO_BASE) $(DEMO_REPO_BASE).git
	@rm -rf $(DEMO_WORKFLOWS_REPO) $(DEMO_WORKFLOWS_REPO).git
	@rm -rf $(DEMO_BEGINNER_REPO) $(DEMO_BEGINNER_REPO).git
	$(call print_success,All demo repositories cleaned)

demo-repo-rebuild: demo-clean demo-repo ## Rebuild demo repository from scratch

demo-repo-rebuild-all: demo-clean-all demo-repo-all ## Rebuild all demo repositories from scratch

demo-repo-status: ## Show status of demo repository
	@printf "$(BLUE)Demo repository status:$(RESET)\n"
	@if [ ! -d $(DEMO_REPO_BASE) ]; then \
		printf "$(YELLOW)Demo repository does not exist$(RESET)\n"; \
		echo "Run 'make demo-repo' to create it"; \
		exit 1; \
	fi; \
	cd $(DEMO_REPO_BASE) && \
	printf "$(GREEN)Repository exists$(RESET)\n" && \
	echo "" && \
	echo "Commits: $$(git rev-list --all --count 2>/dev/null || echo 'N/A')" && \
	echo "Branches: $$(git branch -a 2>/dev/null | wc -l || echo 'N/A')" && \
	echo "Tags: $$(git tag 2>/dev/null | wc -l || echo 'N/A')" && \
	echo "Remote: $$(git remote -v 2>/dev/null | head -1 || echo 'N/A')"; \
	exit 0

.PHONY: test test-bash test-unit test-integration test-lib test-check test-lib-py test-lib-py-verbose test-lib-py-coverage test-verbose test-full test-full-verbose
.PHONY: dev-test-deps-install test-deps-install test-deps-py-install dev-optional-install optional-deps-install dev-optional-check optional-deps-check
.PHONY: python-check python-venv-create python-install-uv dev-deps-sync dev-env-init doctor
.PHONY: mocks-check mocks-generate mocks-generate-git mocks-regenerate mocks-clean mocks-clean-git mocks-test-with-regenerate mocks-validate
.PHONY: vhs-deps-install
.PHONY: vhs vhs-build vhs-build-one vhs-dry-run vhs-clean vhs-check vhs-regenerate vhs-commit-push
.PHONY: docs-dev docs-build docs-preview docs-deps-install deps-docs
.PHONY: format format-verbose lint lint-verbose lint-errors-only typecheck typecheck-verbose sanitize-check sanitize-check-verbose sanitize sanitize-verbose
.PHONY: check check-verbose check-full check-full-verbose pre-commit coverage validate validate-full ci install clean clean-all
.PHONY: debug-vars debug-self-test debug-dry-run debug
.PHONY: demo-repo demo-repo-simple demo-repo-workflows demo-repo-beginner demo-repo-all demo-clean demo-clean-all demo-repo-rebuild demo-repo-rebuild-all demo-repo-status
