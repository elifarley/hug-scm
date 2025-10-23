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

clean-all: clean ## Clean everything including node_modules
	@echo "$(BLUE)Cleaning everything...$(NC)"
	rm -rf node_modules
	@echo "$(GREEN)Deep clean complete!$(NC)"

.PHONY: test test-unit test-integration test-check
.PHONY: docs-dev docs-build docs-preview deps-docs
.PHONY: install check clean clean-all
