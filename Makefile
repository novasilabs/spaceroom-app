# SPDX-License-Identifier: GPL-3.0-or-later
# Common tasks. Run `make help` for the list.

PROJECT  := Spaceroom.xcodeproj
SCHEME   := Spaceroom
DERIVED  := build/DerivedData
DEBUG_APP := $(DERIVED)/Build/Products/Debug/Spaceroom.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: help bootstrap project open build release run test snapshots check-translations dmg clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install XcodeGen (Homebrew) and generate the Xcode project
	@command -v xcodegen >/dev/null || brew install xcodegen
	@$(MAKE) project

project: ## Regenerate Spaceroom.xcodeproj from project.yml
	xcodegen generate

open: project ## Open the project in Xcode
	open $(PROJECT)

build: project ## Debug build
	$(XCODEBUILD) -configuration Debug build

release: project ## Release build (universal)
	$(XCODEBUILD) -configuration Release build

run: build ## Debug build, then launch
	open "$(DEBUG_APP)"

test: ## Run the engine test suite
	swift test --package-path Packages/SpaceroomCore

snapshots: build ## Read-only UI tour in English and Indonesian → build/snapshots
	@for lang in en id; do \
	  mkdir -p build/snapshots/$$lang; \
	  SPACEROOM_SNAPSHOT_DIR=$(CURDIR)/build/snapshots/$$lang "$(DEBUG_APP)/Contents/MacOS/Spaceroom" -AppleLanguages "($$lang)" >/dev/null 2>&1; \
	  echo "✓ build/snapshots/$$lang"; \
	done

check-translations: ## Fail if any string, engine text or rule lacks Bahasa Indonesia
	python3 scripts/check-translations.py

dmg: ## Release build packaged as dist/Spaceroom-<version>.dmg
	./scripts/make-dmg.sh

clean: ## Remove build products (keeps dist/)
	rm -rf build $(PROJECT)
