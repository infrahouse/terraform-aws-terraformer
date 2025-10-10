.DEFAULT_GOAL := help

define PRINT_HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
    match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
    if match:
        target, help = match.groups()
        print("%-40s %s" % (target, help))
endef
export PRINT_HELP_PYSCRIPT

TEST_REGION="us-west-2"
TEST_ROLE="arn:aws:iam::303467602807:role/terraformer-tester"

help: install-hooks
	@python -c "$$PRINT_HELP_PYSCRIPT" < Makefile

.PHONY: install-hooks
install-hooks:  ## Install repo hooks
	@echo "Checking and installing hooks"
	@test -d .git/hooks || (echo "Looks like you are not in a Git repo" ; exit 1)
	@test -L .git/hooks/pre-commit || ln -fs ../../hooks/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit


.PHONY: test
test:  ## Run tests on the module
	pytest -xvvs tests/

.PHONY: test-keep
test-keep:  ## Run a test and keep resources
	pytest -xvvs \
		--aws-region=${TEST_REGION} \
		--test-role-arn=${TEST_ROLE} \
		--keep-after \
		-k aws-6 \
		tests/test_module.py

.PHONY: test-clean
test-clean:  ## Run a test and destroy resources
	pytest -xvvs \
		--aws-region=${TEST_REGION} \
		--test-role-arn=${TEST_ROLE} \
		-k aws-6 \
		tests/test_module.py


.PHONY: bootstrap
bootstrap: install-hooks ## bootstrap the development environment
	pip install -U "pip ~= 25.2"
	pip install -U "setuptools ~= 80.9"
	pip install -r requirements.txt

.PHONY: clean
clean: ## clean the repo from cruft
	rm -rf .pytest_cache
	find . -name '.terraform' -exec rm -fr {} +

.PHONY: lint
lint:  ## Check code formatting without modifying files
	@echo "Checking terraform file formatting"
	terraform fmt -recursive -check
	black --check tests

.PHONY: fmt
fmt: format

.PHONY: format
format:  ## Use terraform fmt to format all files in the repo
	@echo "Formatting terraform files"
	terraform fmt -recursive
	black tests

define BROWSER_PYSCRIPT
import os, webbrowser, sys

from urllib.request import pathname2url

webbrowser.open("file://" + pathname2url(os.path.abspath(sys.argv[1])))
endef
export BROWSER_PYSCRIPT

BROWSER := python -c "$$BROWSER_PYSCRIPT"

.PHONY: docs
docs:  ## Generate module docs
	terraform-docs markdown .
