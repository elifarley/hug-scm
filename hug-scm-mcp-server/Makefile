.PHONY: help install install-dev test test-verbose lint format type-check clean ci-install ci-test ci-lint

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# CI/CD environment detection
CI ?= false

help: ## Display this help message
	@echo "$(BLUE)Hug SCM MCP Server - Makefile Help$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Installation

install: ## Install package
	@echo "$(BLUE)Installing package...$(NC)"
	pip install -e .

install-dev: ## Install package with development dependencies
	@echo "$(BLUE)Installing package with dev dependencies...$(NC)"
	pip install -e ".[dev]"

##@ Testing

test: ## Run tests with pytest
	@echo "$(BLUE)Running tests...$(NC)"
	pytest

test-verbose: ## Run tests with verbose output
	@echo "$(BLUE)Running tests with verbose output...$(NC)"
	pytest -vv

test-cov: ## Run tests with coverage report
	@echo "$(BLUE)Running tests with coverage...$(NC)"
	pytest --cov=hug_scm_mcp_server --cov-report=term-missing --cov-report=html

test-unit: ## Run only unit tests (excluding integration)
	@echo "$(BLUE)Running unit tests...$(NC)"
	pytest tests/test_command_executor.py tests/test_tool_handlers.py -v

test-integration: ## Run only integration tests
	@echo "$(BLUE)Running integration tests...$(NC)"
	pytest tests/test_server.py -v

test-fast: ## Run tests without coverage (faster)
	@echo "$(BLUE)Running fast tests...$(NC)"
	pytest -x --tb=short

##@ Code Quality

lint: ## Run ruff linter
	@echo "$(BLUE)Running linter...$(NC)"
	ruff check src/ tests/

lint-fix: ## Run ruff linter with auto-fix
	@echo "$(BLUE)Running linter with auto-fix...$(NC)"
	ruff check --fix src/ tests/

format: ## Format code with black
	@echo "$(BLUE)Formatting code...$(NC)"
	black src/ tests/

format-check: ## Check code formatting without changes
	@echo "$(BLUE)Checking code formatting...$(NC)"
	black --check src/ tests/

type-check: ## Run mypy type checker
	@echo "$(BLUE)Running type checker...$(NC)"
	mypy src/

##@ Development

dev: install-dev ## Setup development environment
	@echo "$(GREEN)Development environment ready!$(NC)"

check: lint format-check type-check test ## Run all checks (lint, format, type-check, test)
	@echo "$(GREEN)All checks passed!$(NC)"

check-ci: ci-lint format-check type-check ci-test ## Run all CI checks (optimized for CI)
	@echo "$(GREEN)All CI checks passed!$(NC)"

##@ CI/CD

ci-install: ## Install package for CI (with dev dependencies)
	@echo "$(BLUE)Installing package for CI...$(NC)"
	pip install --upgrade pip
	pip install -e ".[dev]"

ci-test: ## Run tests for CI (with coverage)
	@echo "$(BLUE)Running tests for CI...$(NC)"
	pytest --cov=hug_scm_mcp_server --cov-report=term --cov-report=xml --junitxml=junit.xml -v

ci-lint: ## Run linter for CI (strict mode)
	@echo "$(BLUE)Running linter for CI...$(NC)"
	ruff check src/ tests/ --output-format=github

##@ Cleanup

clean: ## Clean up generated files
	@echo "$(BLUE)Cleaning up...$(NC)"
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info
	rm -rf .pytest_cache/
	rm -rf .coverage
	rm -rf htmlcov/
	rm -rf .mypy_cache/
	rm -rf .ruff_cache/
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete

clean-all: clean ## Clean everything including dependencies
	@echo "$(BLUE)Cleaning everything...$(NC)"
	rm -rf venv/
	rm -rf .venv/

clean-ci: clean ## Clean CI artifacts (junit.xml, coverage.xml)
	@echo "$(BLUE)Cleaning CI artifacts...$(NC)"
	rm -rf junit.xml coverage.xml

##@ Verification

verify-install: ## Verify package is installed correctly
	@echo "$(BLUE)Verifying installation...$(NC)"
	@python -c "import hug_scm_mcp_server; print('✓ Package imported successfully')"
	@python -c "from hug_scm_mcp_server.server import main; print('✓ Server module loaded')"
	@python -c "from hug_scm_mcp_server.command_executor import CommandExecutor; print('✓ CommandExecutor loaded')"
	@python -c "from hug_scm_mcp_server.tool_handlers import ToolRegistry; print('✓ ToolRegistry loaded')"
	@echo "$(GREEN)Installation verified!$(NC)"

verify-deps: ## Verify all dependencies are installed
	@echo "$(BLUE)Verifying dependencies...$(NC)"
	@python -c "import mcp; print('✓ mcp installed')" 2>/dev/null || echo "$(RED)✗ mcp not installed$(NC)"
	@python -c "import pytest; print('✓ pytest installed')" 2>/dev/null || echo "$(YELLOW)⚠ pytest not installed (dev only)$(NC)"
	@python -c "import black; print('✓ black installed')" 2>/dev/null || echo "$(YELLOW)⚠ black not installed (dev only)$(NC)"
	@python -c "import ruff; print('✓ ruff installed')" 2>/dev/null || echo "$(YELLOW)⚠ ruff not installed (dev only)$(NC)"
	@echo "$(GREEN)Dependency verification complete!$(NC)"
