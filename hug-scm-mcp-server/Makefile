.PHONY: help install install-dev test test-verbose lint format type-check clean

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

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
