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

# UV detection for fast Python package management
UV := $(shell command -v uv 2>/dev/null)
ifeq ($(UV),)
    UV_AVAILABLE := false
    UV_CMD := uv
    PYTHON_CMD := python3
    PYTEST_CMD := python3 -m pytest
    PIP_CMD := python3 -m pip install
    $(warning UV not found - falling back to python3...)
else
    UV_AVAILABLE := true
    UV_CMD := uv
    PYTHON_CMD := uv run python
    PYTEST_CMD := uv run pytest
    PIP_CMD := uv pip install
endif

# Terminal detection for colors (matches canonical framework)
IS_TTY := $(shell test -t 1 && echo 1 || echo 0)

# Python library directory (absolute path for CI reliability)
PYTHON_LIB_DIR := $(realpath git-config/lib/python)

ifeq ($(IS_TTY),1)
    BOLD := \033[1m
    RESET := \033[0m
    GREEN := \033[32m
    YELLOW := \033[33m
    BLUE := \033[34m
    CYAN := \033[36m
    RED := \033[31m
else
    BOLD :=
    RESET :=
    GREEN :=
    YELLOW :=
    BLUE :=
    CYAN :=
    RED :=
endif

# Test customization variables (optional)
TEST_FILE ?=
TEST_FILTER ?=
TEST_SHOW_ALL_RESULTS ?=

DEMO_REPO_BASE := /tmp/demo-repo

# Setup PATH for demo repository creation (includes hug commands)
HUG_BIN_PATH := $(shell pwd)/git-config/bin
DEMO_REPO_ENV := export PATH="$$PATH:$(HUG_BIN_PATH)" &&

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
	@printf "  $(GREEN)make sanitize$(RESET)       - Run all static checks (format + lint + typecheck)\n"
	@printf "\n"
	@printf "$(BOLD)Testing:$(RESET)\n"
	@printf "  $(CYAN)make test-unit$(RESET)       - Run unit tests (LLM-friendly)\n"
	@printf "  $(CYAN)make test-unit-verbose$(RESET) - Run unit tests (detailed)\n"
	@printf "  $(CYAN)make test-integration$(RESET) - Run integration tests (LLM-friendly)\n"
	@printf "  $(CYAN)make test-integration-verbose$(RESET) - Run integration tests (detailed)\n"
	@printf "  $(CYAN)make test-lib-py$(RESET)     - Run Python library tests\n"
	@printf "  $(CYAN)make test$(RESET)            - Run all tests (LLM-friendly)\n"
	@printf "  $(CYAN)make test-verbose$(RESET)    - Run all tests (detailed)\n"
	@printf "\n"
	@printf "$(BOLD)Gates:$(RESET)\n"
	@printf "  $(GREEN)make check$(RESET)          - Fast merge gate (sanitize + unit tests)\n"
	@printf "  $(GREEN)make check-verbose$(RESET)  - Merge gate with detailed output\n"
	@printf "  $(GREEN)make validate$(RESET)       - Full release validation (sanitize + test + coverage)\n"
	@printf "  $(GREEN)make coverage$(RESET)       - Enforce test coverage thresholds\n"
	@printf "  $(GREEN)make pre-commit$(RESET)     - Pre-commit hook\n"
	@printf "\n"
	@printf "$(BOLD)Documentation:$(RESET)\n"
	@grep -E '^(docs-|deps-docs):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "$(BOLD)Screencasts (VHS):$(RESET)\n"
	@grep -E '^vhs.*:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "$(BOLD)Installation & Setup:$(RESET)\n"
	@printf "  $(GREEN)make install$(RESET)        - Install Hug SCM\n"
	@grep -E '^(deps-|optional-|python-):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "$(BOLD)Utilities:$(RESET)\n"
	@grep -E '^(clean|demo-|mocks-):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-24s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
	@printf "For full test filtering options, see $(CYAN)TESTING.md$(RESET)\n"

##@ Testing

test-lump: test-lib-py test-bash  ## Run all tests (BATS + pytest)
	@echo "$(GREEN)All tests completed!$(RESET)"

test: test-check test-lib-py test-lib test-unit test-integration ## Run all tests by category (fastest first)
	@echo "$(GREEN)All tests completed!$(RESET)"

test-bash: ## Run all BATS-based tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	@echo "$(BLUE)Running BATS tests...$(RESET)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh tests/ $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-unit: ## Run only unit tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	@echo "$(BLUE)Running unit tests...$(RESET)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/unit/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --unit $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-integration: ## Run only integration tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	@echo "$(BLUE)Running integration tests...$(RESET)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/integration/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --integration $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-lib: ## Run only library tests (or specific: TEST_FILE=... TEST_FILTER=... TEST_SHOW_ALL_RESULTS=1)
	@echo "$(BLUE)Running library tests...$(RESET)"
	@if [ -n "$(TEST_FILE)" ]; then \
		case "$(TEST_FILE)" in \
		tests/*) \
			./tests/run-tests.sh "$(TEST_FILE)" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		*) \
			ADJUSTED_FILE="tests/lib/$$(basename "$(TEST_FILE)")"; \
			./tests/run-tests.sh "$$ADJUSTED_FILE" $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
			;; \
		esac; \
	else \
		./tests/run-tests.sh --lib $(if $(TEST_SHOW_ALL_RESULTS),-A) $(if $(TEST_FILTER),-f "$(TEST_FILTER)"); \
	fi

test-check: ## Check test prerequisites without actually running tests
	@echo "$(BLUE)Checking test prerequisites...$(RESET)"
	./tests/run-tests.sh --check
	@echo "$(BLUE)Checking Python test prerequisites...$(RESET)"
	@if cd git-config/lib/python && $(PYTEST_CMD) --version >/dev/null 2>&1; then \
		echo "$(GREEN)✓ pytest is available$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ pytest not found - install with 'make test-deps-install' or 'make test-deps-py-install'$(RESET)"; \
	fi

test-lib-py: ## Run Python library tests (pytest, LLM-friendly)
	@echo "$(BLUE)Running Python library tests...$(RESET)"
	@cd git-config/lib/python && \
	if ! $(PYTEST_CMD) --version >/dev/null 2>&1; then \
		echo "$(YELLOW)pytest not installed. Installing pytest and dev dependencies...$(RESET)"; \
		$(PIP_CMD) -q -e ".[dev]" || \
		(echo "$(YELLOW)Warning: Could not install dev dependencies. Tests will be skipped.$(RESET)" && exit 0); \
	fi; \
	$(PYTEST_CMD) tests/ -q --color=yes --tb=short $(if $(TEST_FILTER),-k "$(TEST_FILTER)")

test-lib-py-coverage: ## Run Python library tests with coverage report
	@echo "$(BLUE)Running Python library tests with coverage...$(RESET)"
	@cd git-config/lib/python && \
	$(PIP_CMD) -q -e ".[dev]" 2>/dev/null || true; \
	$(PYTEST_CMD) tests/ -v --cov=. --cov-report=term-missing --cov-report=html

test-lib-py-verbose: ## Run Python library tests (detailed output)
	@echo "$(BLUE)Running Python library tests (verbose)...$(RESET)"
	@cd git-config/lib/python && \
	if ! $(PYTEST_CMD) --version >/dev/null 2>&1; then \
		echo "$(YELLOW)pytest not installed. Installing pytest and dev dependencies...$(RESET)"; \
		$(PIP_CMD) -q -e ".[dev]" || \
		(echo "$(YELLOW)Warning: Could not install dev dependencies. Tests will be skipped.$(RESET)" && exit 0); \
	fi; \
	$(PYTEST_CMD) tests/ -v --color=yes --tb=short $(if $(TEST_FILTER),-k "$(TEST_FILTER)")

test-unit-verbose: ## Run unit tests (detailed output)
	@echo "$(BLUE)Running unit tests...$(RESET)"
	@$(MAKE) test-unit TEST_SHOW_ALL_RESULTS=1

test-integration-verbose: ## Run integration tests (detailed output)
	@echo "$(BLUE)Running integration tests...$(RESET)"
	@$(MAKE) test-integration TEST_SHOW_ALL_RESULTS=1

test-verbose: ## Run all tests (detailed output)
	@$(MAKE) test TEST_SHOW_ALL_RESULTS=1

test-deps-install: ## Install all test dependencies (BATS + Python)
	@echo "$(BLUE)Installing test dependencies...$(RESET)"
	@echo "$(BLUE)Installing BATS dependencies...$(RESET)"
	./tests/run-tests.sh --install-deps
	@echo "$(BLUE)Installing Python test dependencies...$(RESET)"
ifeq ($(UV_AVAILABLE),true)
	@echo "$(CYAN)Using UV for fast dependency installation...$(RESET)"
endif
	@cd git-config/lib/python && $(PIP_CMD) -q -e ".[dev]" || \
	(echo "$(YELLOW)Warning: Could not install Python dev dependencies. Python tests may not work.$(RESET)")
	@echo "$(GREEN)All test dependencies installed$(RESET)"

test-deps-py-install: ## Install Python test dependencies (DEPRECATED: use 'dev-deps-sync')
	@echo "$(YELLOW)⚠ 'test-deps-py-install' is deprecated, use 'make dev-deps-sync'$(RESET)"
	@$(MAKE) dev-deps-sync

dev-deps-sync: ## Sync dependencies from lockfiles
	@echo "$(BLUE)Syncing dependencies...$(RESET)"
	@test -d .venv || (printf "$(RED)❌ .venv not found$(RESET)\n" && printf "$(BLUE)ℹ️ Run: make dev-env-init$(RESET)\n" && exit 1)
	@echo "$(BLUE)Installing Python test dependencies...$(RESET)"
ifeq ($(UV_AVAILABLE),true)
	@echo "$(CYAN)Using UV for fast dependency installation...$(RESET)"
endif
	@cd git-config/lib/python && $(PIP_CMD) -e ".[dev]"
	@echo "$(GREEN)Python test dependencies installed$(RESET)"

optional-deps-install: ## Install optional dependencies (gum, shfmt, ShellCheck)
	@echo "$(BLUE)Installing optional dependencies...$(RESET)"
	@bash bin/optional-deps-install.sh
	@echo "$(BLUE)Installing shfmt...$(RESET)"
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "$(GREEN)✓ shfmt already installed$(RESET)"; \
	else \
		if [ "$$(uname)" = "Darwin" ]; then \
			brew install shfmt 2>/dev/null || echo "$(YELLOW)⚠ Install shfmt manually from https://github.com/mvdan/sh$(RESET)"; \
		elif [ -f /etc/debian_version ]; then \
			sudo apt-get install -y shfmt 2>/dev/null || echo "$(YELLOW)⚠ Install shfmt manually from https://github.com/mvdan/sh$(RESET)"; \
		else \
			echo "$(YELLOW)⚠ Install shfmt manually from https://github.com/mvdan/sh$(RESET)"; \
		fi; \
	fi
	@echo "$(BLUE)Installing ShellCheck...$(RESET)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "$(GREEN)✓ ShellCheck already installed$(RESET)"; \
	else \
		if [ "$$(uname)" = "Darwin" ]; then \
			brew install shellcheck 2>/dev/null || echo "$(YELLOW)⚠ Install ShellCheck manually from https://www.shellcheck.net/$(RESET)"; \
		elif [ -f /etc/debian_version ]; then \
			sudo apt-get install -y shellcheck 2>/dev/null || echo "$(YELLOW)⚠ Install ShellCheck manually from https://www.shellcheck.net/$(RESET)"; \
		else \
			echo "$(YELLOW)⚠ Install ShellCheck manually from https://www.shellcheck.net/$(RESET)"; \
		fi; \
	fi

optional-deps-check: ## Check if optional dependencies are installed
	@echo "$(BLUE)Checking optional dependencies...$(RESET)"
	@bash bin/optional-deps-install.sh --check

doctor: ## Check environment and tool readiness
	@echo "$(BLUE)Checking environment...$(RESET)"
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
	@command -v shfmt >/dev/null || printf "$(YELLOW)⚠ shfmt not found (run 'make optional-deps-install')$(RESET)\n"
	@command -v shellcheck >/dev/null || printf "$(YELLOW)⚠ ShellCheck not found (run 'make optional-deps-install')$(RESET)\n"
	@echo ""
	@echo "UV (for Python helpers):"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		printf "$(GREEN)✅ UV available$(RESET)\n"; \
	else \
		printf "$(YELLOW)⚠ UV not found (optional, run 'make python-install-uv')$(RESET)\n"; \
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
	@echo "$(YELLOW)⚠ 'python-check' is deprecated, use 'make doctor'$(RESET)"
	@$(MAKE) doctor

python-venv-create: ## Create virtual environment using UV (fast) (DEPRECATED: use 'dev-env-init')
	@echo "$(YELLOW)⚠ 'python-venv-create' is deprecated, use 'make dev-env-init'$(RESET)"
	@$(MAKE) dev-env-init

dev-env-init: ## Create virtual environment (one-time setup)
	@echo "$(BLUE)Creating virtual environment...$(RESET)"
ifeq ($(UV_AVAILABLE),true)
	@$(UV) venv .venv
	@echo "$(GREEN)✓ Virtual environment created with UV$(RESET)"
else
	@echo "$(YELLOW)UV not available, using python3 -m venv...$(RESET)"
	@python3 -m venv .venv
	@echo "$(GREEN)✓ Virtual environment created with python3$(RESET)"
endif
	@echo "$(CYAN)Run 'make test-deps-py-install' to install dependencies$(RESET)"

python-install-uv: ## Install UV package manager
	@echo "$(BLUE)Installing UV...$(RESET)"
	@curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo "$(GREEN)UV installed successfully$(RESET)"
	@echo "$(CYAN)Run 'source ~/.bashrc' or restart your shell to use UV$(RESET)"

##@ Mock Data Management

mocks-check: ## Check status of recorded mock data
	@echo "$(BLUE)Checking mock data status...$(RESET)"
	@cd git-config/lib/python/tests/fixtures && \
	if [ ! -d mocks/git/log ]; then \
		echo "$(YELLOW)⚠ No mock data found$(RESET)"; \
		echo "Run 'make mocks-generate' to create mock data"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓ Mock data exists$(RESET)"; \
	echo ""; \
	echo "TOML files:"; \
	find mocks -name "*.toml" -type f | sed 's/^/  - /'; \
	echo ""; \
	echo "Output files:"; \
	find mocks -name "*.txt" -type f | wc -l | xargs printf "  %s output files\n"

mocks-generate: ## Regenerate all mock data from real commands
	@echo "$(BLUE)Regenerating all mock data...$(RESET)"
	@cd git-config/lib/python/tests/fixtures && $(PYTHON_CMD) generate_mocks.py
	@echo "$(GREEN)✓ All mock data regenerated successfully$(RESET)"

mocks-generate-git: ## Regenerate Git command mocks only
	@echo "$(BLUE)Regenerating Git command mocks...$(RESET)"
	@cd git-config/lib/python/tests/fixtures && $(PYTHON_CMD) generate_mocks.py
	@echo "$(GREEN)✓ Git mocks regenerated$(RESET)"

mocks-regenerate: mocks-generate ## Alias for mocks-generate

mocks-clean: ## Remove all generated mock data
	@echo "$(BLUE)Cleaning mock data...$(RESET)"
	@cd git-config/lib/python/tests/fixtures/mocks && \
	find . -name "*.toml" -type f -delete && \
	find . -name "*.txt" -type f -delete
	@echo "$(GREEN)✓ Mock data cleaned$(RESET)"
	@echo "$(YELLOW)Run 'make mocks-generate' to recreate$(RESET)"

mocks-clean-git: ## Remove Git command mocks only
	@echo "$(BLUE)Cleaning Git command mocks...$(RESET)"
	@rm -rf git-config/lib/python/tests/fixtures/mocks/git/log/*.toml
	@rm -rf git-config/lib/python/tests/fixtures/mocks/git/log/outputs/*.txt
	@echo "$(GREEN)✓ Git mocks cleaned$(RESET)"

mocks-test-with-regenerate: ## Run Python tests and regenerate mocks on failure
	@echo "$(BLUE)Running Python tests with mock regeneration...$(RESET)"
	@cd git-config/lib/python && \
	if ! $(PYTEST_CMD) tests/ -v --color=yes --tb=short; then \
		echo "$(YELLOW)Tests failed - regenerating mocks...$(RESET)"; \
		cd tests/fixtures && $(PYTHON_CMD) generate_mocks.py; \
		echo "$(BLUE)Retrying tests with fresh mocks...$(RESET)"; \
		cd ../.. && $(PYTEST_CMD) tests/ -v --color=yes --tb=short; \
	fi
	@echo "$(GREEN)✓ Python tests passed$(RESET)"

mocks-validate: ## Validate mock data integrity (TOML + output files match)
	@echo "$(BLUE)Validating mock data integrity...$(RESET)"
	@cd git-config/lib/python/tests/fixtures && \
	$(PYTHON_CMD) -c "import tomllib; from pathlib import Path; errors = []; \
[toml_file for toml_file in Path('mocks').rglob('*.toml') if (lambda f: ([errors.append(f'Missing: {f.parent / scenario.get(\"output_file\", \"\")}') for scenario in tomllib.load(open(f, 'rb')).get('scenario', []) if not (f.parent / scenario.get('output_file', '')).exists()], None)[1])(toml_file)]; \
exit(1) if errors and print('\n'.join(errors)) else print('$(GREEN)✓ All mock data is valid$(RESET)')"

##@ VHS Screencasts

vhs-deps-install: ## Install VHS tool if not present
	@echo "$(BLUE)Installing VHS dependencies...$(RESET)"
	@bash docs/screencasts/bin/vhs-build.sh --install-deps

vhs-check: vhs-deps-install ## Check if VHS is installed
	@echo "$(BLUE)Checking VHS installation...$(RESET)"
	@bash docs/screencasts/bin/vhs-build.sh --check

vhs: demo-repo-rebuild-all vhs-deps-install ## Build all GIF/PNG images from VHS tape files
	@echo "$(BLUE)Building all VHS screencasts...$(RESET)"
	@bash docs/screencasts/bin/vhs-build.sh --all
	@$(MAKE) vhs-strip-metadata

vhs-build: vhs ## Alias for vhs target

vhs-build-one: vhs-check ## Build a specific VHS tape file (usage: make vhs-build-one TAPE=filename.tape)
	@echo "$(BLUE)Building VHS screencast: $(TAPE)$(RESET)"
	@if [ -z "$(TAPE)" ]; then \
		echo "$(YELLOW)Usage: make vhs-build-one TAPE=filename.tape$(RESET)"; \
		exit 1; \
	fi
	@bash docs/screencasts/bin/vhs-build.sh "$(TAPE)"
	@$(MAKE) vhs-strip-metadata

vhs-dry-run: ## Show what would be built without building
	@echo "$(BLUE)Dry run - showing what would be built...$(RESET)"
	@bash docs/screencasts/bin/vhs-build.sh --dry-run --all

vhs-strip-metadata: ## Strip metadata from all PNG/GIF images to make them deterministic
	@echo "$(BLUE)Stripping metadata from images...$(RESET)"
	@bash docs/screencasts/bin/vhs-strip-metadata.sh && echo "$(GREEN)Metadata stripped successfully$(RESET)"

vhs-clean: ## Remove generated GIF/PNG files from VHS
	@bash docs/screencasts/bin/vhs-clean.sh

vhs-regenerate: demo-repo vhs-deps-install ## Regenerate VHS images for CI (demo + essential tapes)
	@echo "$(BLUE)Regenerating VHS images...$(RESET)"
	@bash docs/screencasts/bin/vhs-build.sh hug-l.tape hug-lo.tape hug-lol.tape hug-sl-states.tape
	@echo "$(BLUE)Cleaning up frame directories...$(RESET)"
	@bash docs/screencasts/bin/vhs-cleanup-frames.sh
	@echo "$(BLUE)Verifying cleanup...$(RESET)"
	@bash docs/screencasts/bin/vhs-cleanup-frames.sh --verify-strict
	@$(MAKE) vhs-strip-metadata
	@echo "$(GREEN)VHS images regenerated successfully$(RESET)"

vhs-commit-push: ## Commit and push VHS image changes (for CI/automation)
	@bash docs/screencasts/bin/vhs-commit-push.sh

##@ Documentation

docs-dev: ## Start documentation development server
	@echo "$(BLUE)Starting documentation server...$(RESET)"
	npm run docs:dev

docs-build: ## Build documentation for production
	@echo "$(BLUE)Building documentation...$(RESET)"
	npm run docs:build

docs-preview: ## Preview built documentation
	@echo "$(BLUE)Previewing documentation...$(RESET)"
	npm run docs:preview

##@ Installation

install: ## Install Hug SCM
	@echo "$(BLUE)Installing Hug SCM...$(RESET)"
	./install.sh
	@echo "$(GREEN)Installation complete!$(RESET)"
	@echo "Run 'source bin/activate' to activate Hug"

deps-docs: ## Install documentation dependencies
	@echo "$(BLUE)Installing documentation dependencies...$(RESET)"
	npm ci

##@ Development

format: ## Format code (LLM-friendly: summary only)
	@echo "$(BLUE)Formatting Bash scripts...$(RESET)"
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -sr git-config/bin/ git-config/lib/ hg-config/bin/ hg-config/lib/ bin/ tests/ 2>/dev/null || true; \
		echo "$(GREEN)✅ Bash formatting OK$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ shfmt not found - run 'make optional-deps-install'$(RESET)"; \
	fi
	@echo "$(BLUE)Formatting Python helpers...$(RESET)"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		$(UV_CMD) run --directory git-config/lib/python ruff format --quiet .; \
		echo "$(GREEN)✅ Python formatting OK$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ UV not available - skipping Python formatting$(RESET)"; \
	fi
	@echo "$(GREEN)✅ Formatting complete$(RESET)"

format-verbose: ## Format code (show changes)
	@echo "$(BLUE)Formatting Bash scripts...$(RESET)"
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -sr -d git-config/bin/ git-config/lib/ hg-config/bin/ hg-config/lib/ bin/ tests/; \
	else \
		echo "$(YELLOW)⚠ shfmt not found$(RESET)"; \
	fi
	@echo "$(BLUE)Formatting Python helpers...$(RESET)"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		$(UV_CMD) run --directory git-config/lib/python ruff format .; \
	else \
		echo "$(YELLOW)⚠ UV not available$(RESET)"; \
	fi

lint: ## Run linting checks (LLM-friendly: summary only)
	@echo "$(BLUE)Linting Bash scripts...$(RESET)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S error git-config/bin/* git-config/lib/* hg-config/bin/* hg-config/lib/* bin/* tests/test_helper.bash tests/unit/*.bats tests/lib/*.bats tests/integration/*.bats 2>&1 | \
			{ grep -q '^.*:[0-9]*:.*' && { cat; exit 1; } || echo "$(GREEN)✅ Bash linting OK$(RESET)"; } || \
			(echo "$(GREEN)✅ Bash linting OK$(RESET)"; exit 0); \
	else \
		echo "$(YELLOW)⚠ ShellCheck not found - run 'make optional-deps-install'$(RESET)"; \
	fi
	@echo "$(BLUE)Linting Python helpers...$(RESET)"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		$(UV_CMD) run --directory git-config/lib/python ruff check --output-format=concise . 2>&1 | \
			{ grep -q '.' && { cat; exit 1; } || echo "$(GREEN)✅ Python linting OK$(RESET)"; } || \
			(echo "$(GREEN)✅ Python linting OK$(RESET)"; exit 0); \
	else \
		echo "$(YELLOW)⚠ UV not available - skipping Python linting$(RESET)"; \
	fi

lint-verbose: ## Run linting (detailed output)
	@echo "$(BLUE)Linting Bash scripts...$(RESET)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck git-config/bin/* git-config/lib/* hg-config/bin/* hg-config/lib/* bin/* tests/test_helper.bash tests/unit/*.bats tests/lib/*.bats tests/integration/*.bats; \
	else \
		echo "$(YELLOW)⚠ ShellCheck not found$(RESET)"; \
	fi
	@echo "$(BLUE)Linting Python helpers...$(RESET)"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		$(UV_CMD) run --directory git-config/lib/python ruff check .; \
	else \
		echo "$(YELLOW)⚠ UV not available$(RESET)"; \
	fi

typecheck: ## Type check Python code (LLM-friendly: summary only)
	@echo "$(BLUE)Type checking Python helpers...$(RESET)"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		output=$$($(UV_CMD) run --directory "$(PYTHON_LIB_DIR)" mypy --no-pretty . 2>&1); \
		if echo "$$output" | grep -q 'Success: no issues found'; then \
			echo "$(GREEN)✅ Type checking OK$(RESET)"; \
		else \
			echo "$$output" | grep -vE '^(Success: no issues found|warning:)'; \
			exit 1; \
		fi \
	else \
		echo "$(YELLOW)⚠ UV not available - skipping type check$(RESET)"; \
	fi

typecheck-verbose: ## Type check Python code (detailed)
	@echo "$(BLUE)Type checking Python helpers...$(RESET)"
	@if [ "$(UV_AVAILABLE)" = "true" ]; then \
		$(UV_CMD) run --directory "$(PYTHON_LIB_DIR)" mypy .; \
	else \
		echo "$(YELLOW)⚠ UV not available$(RESET)"; \
	fi

static: ## Run all static checks that don't change the source code
	@$(MAKE) lint
	@$(MAKE) typecheck
	@echo "$(GREEN)✅ Static checks complete$(RESET)"

sanitize: ## Run all static checks (format + lint + typecheck)
	@$(MAKE) format
	@$(MAKE) lint
	@$(MAKE) typecheck
	@echo "$(GREEN)✅ Sanitize complete$(RESET)"

check: sanitize test-check test-lib-py test-lib ## Fast merge gate (sanitize + some tests)
	@echo "$(GREEN)✅ Checks passed$(RESET)"

pre-commit: check ## Run checks and tests before commit (git hook target)
	@echo "$(GREEN)✓ Pre-commit checks complete$(RESET)"

coverage: test-lib-py-coverage ## Enforce test coverage thresholds
	@echo "$(GREEN)✅ Coverage check complete$(RESET)"

validate: sanitize test coverage ## Full release validation (sanitize + test + coverage)
	@echo "$(GREEN)✅ Release validation complete$(RESET)"

ci: static test ## Run full CI pipeline (all tests)
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)✓ CI Pipeline Complete$(RESET)"
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"

clean: ## Clean build artifacts and temporary files
	@echo "$(BLUE)Cleaning build artifacts...$(RESET)"
	rm -rf docs/.vitepress/dist
	rm -rf docs/.vitepress/cache
	rm -rf node_modules/.vite
	@echo "$(GREEN)Clean complete!$(RESET)"

clean-all: clean demo-clean ## Clean everything including node_modules
	@echo "$(BLUE)Cleaning everything...$(RESET)"
	rm -rf node_modules
	@echo "$(GREEN)Deep clean complete!$(RESET)"

##@ Demo Repository

demo-repo: ## Create demo repository for tutorials and screencasts
	@echo "$(BLUE)Creating demo repository...$(RESET)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/bin/repo-setup.sh "$(DEMO_REPO_BASE)"
	@echo "$(GREEN)Demo repository created at $(DEMO_REPO_BASE)$(RESET)"

demo-repo-simple: ## Create simple demo repository for CI and quick testing
	@echo "$(BLUE)Creating simple demo repository...$(RESET)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/bin/repo-setup-simple.sh "$(DEMO_REPO_BASE)"

demo-repo-workflows: ## Create workflows demo repository for practical workflows screencasts
	@echo "$(BLUE)Creating workflows demo repository...$(RESET)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/practical-workflows/bin/repo-setup.sh /tmp/workflows-repo
	@echo "$(GREEN)Workflows demo repository created at /tmp/workflows-repo$(RESET)"

demo-repo-beginner: ## Create beginner demo repository for beginner tutorial screencasts
	@echo "$(BLUE)Creating beginner demo repository...$(RESET)"
	@$(DEMO_REPO_ENV) bash docs/screencasts/hug-for-beginners/bin/repo-setup.sh /tmp/beginner-repo
	@echo "$(GREEN)Beginner demo repository created at /tmp/beginner-repo$(RESET)"

demo-repo-all: demo-repo demo-repo-workflows demo-repo-beginner ## Create all demo repositories

demo-clean: ## Clean demo repository and remote
	@echo "$(BLUE)Cleaning demo repository...$(RESET)"
	@rm -rf $(DEMO_REPO_BASE) $(DEMO_REPO_BASE).git
	@echo "$(GREEN)Demo repository cleaned$(RESET)"

demo-clean-all: ## Clean all demo repositories
	@echo "$(BLUE)Cleaning all demo repositories...$(RESET)"
	@rm -rf $(DEMO_REPO_BASE) $(DEMO_REPO_BASE).git
	@rm -rf /tmp/workflows-repo /tmp/workflows-repo.git
	@rm -rf /tmp/beginner-repo /tmp/beginner-repo.git
	@echo "$(GREEN)All demo repositories cleaned$(RESET)"

demo-repo-rebuild: demo-clean demo-repo ## Rebuild demo repository from scratch

demo-repo-rebuild-all: demo-clean-all demo-repo-all ## Rebuild all demo repositories from scratch

demo-repo-status: ## Show status of demo repository
	@echo "$(BLUE)Demo repository status:$(RESET)"
	@if [ ! -d $(DEMO_REPO_BASE) ]; then \
		echo "$(YELLOW)Demo repository does not exist$(RESET)"; \
		echo "Run 'make demo-repo' to create it"; \
		exit 1; \
	fi; \
	cd $(DEMO_REPO_BASE) && \
	echo "$(GREEN)Repository exists$(RESET)" && \
	echo "" && \
	echo "Commits: $$(git rev-list --all --count 2>/dev/null || echo 'N/A')" && \
	echo "Branches: $$(git branch -a 2>/dev/null | wc -l || echo 'N/A')" && \
	echo "Tags: $$(git tag 2>/dev/null | wc -l || echo 'N/A')" && \
	echo "Remote: $$(git remote -v 2>/dev/null | head -1 || echo 'N/A')"; \
	exit 0

.PHONY: test test-bash test-unit test-integration test-lib test-check test-lib-py test-lib-py-verbose test-lib-py-coverage test-deps-install test-deps-py-install optional-deps-install optional-deps-check python-check python-venv-create python-install-uv
.PHONY: mocks-check mocks-generate mocks-generate-git mocks-regenerate mocks-clean mocks-clean-git mocks-test-with-regenerate mocks-validate
.PHONY: vhs-deps-install
.PHONY: vhs vhs-build vhs-build-one vhs-dry-run vhs-clean vhs-check vhs-regenerate vhs-commit-push
.PHONY: docs-dev docs-build docs-preview deps-docs
.PHONY: format format-verbose lint lint-verbose typecheck typecheck-verbose sanitize check pre-commit coverage validate ci install clean clean-all
.PHONY: demo-repo demo-repo-simple demo-repo-workflows demo-repo-beginner demo-repo-all demo-clean demo-clean-all demo-repo-rebuild demo-repo-rebuild-all demo-repo-status
