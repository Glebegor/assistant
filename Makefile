# Shortcuts for the scripts in scripts/. Run `make` to see all commands.

.PHONY: help build build-release run install package version notes release clean
.DEFAULT_GOAL := help

help: ## Show this list
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36mmake %-14s\033[0m %s\n", $$1, $$2}'

build: ## Build a debug RightHand.app into build/
	@scripts/build-app.sh debug

build-release: ## Build a release RightHand.app into build/
	@scripts/build-app.sh release

run: ## Build (debug) and launch build/RightHand.app
	@scripts/run.sh

install: ## Build (release), install into /Applications and launch
	@scripts/install.sh

package: ## Zip a release build; optional VERSION=x.y.z (default: next version)
	@scripts/package.sh $(VERSION)

version: ## Show the next release version
	@v="$$(scripts/next-version.sh)"; echo "$${v:-Nothing to release}"

notes: ## Preview the release notes
	@scripts/next-version.sh --notes

release: ## Merge dev into master and push; GitHub Actions publishes the release
	@scripts/release.sh

clean: ## Remove build outputs
	rm -rf build .build
