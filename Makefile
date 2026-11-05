# SPDX-License-Identifier: GPL-3.0-or-later
# Common tasks. Run `make help` for the list.

PROJECT  := Spaceroom.xcodeproj
SCHEME   := Spaceroom
DERIVED  := build/DerivedData
DEBUG_APP := $(DERIVED)/Build/Products/Debug/Spaceroom.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)
VERSION  := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
PREFIX   ?= /usr/local
CLI_BUILD := Packages/SpaceroomCore/.build/apple/Products/Release
CLI_DIR  := dist/spaceroom-$(VERSION)

.PHONY: help bootstrap project open build release run test snapshots check-translations dmg cli install-cli clean

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

cli: ## Build the `spaceroom` command (universal) into dist/spaceroom-<version>/
	swift build --package-path Packages/SpaceroomCore -c release --product spaceroom --arch arm64 --arch x86_64
	mkdir -p $(CLI_DIR)
	cp -f $(CLI_BUILD)/spaceroom $(CLI_DIR)/spaceroom
	ditto $(CLI_BUILD)/SpaceroomCore_SpaceroomCore.bundle $(CLI_DIR)/SpaceroomCore_SpaceroomCore.bundle
	codesign --force --sign - --options runtime $(CLI_DIR)/spaceroom
	@echo "✓ $(CLI_DIR)/spaceroom ($$(lipo -archs $(CLI_DIR)/spaceroom))"

install-cli: cli ## Install `spaceroom` into $(PREFIX) (default /usr/local; may need sudo)
	@test -n "$(PREFIX)" || { echo "PREFIX is empty"; exit 1; }
	install -d "$(PREFIX)/lib/spaceroom" "$(PREFIX)/bin"
	cp -f $(CLI_DIR)/spaceroom "$(PREFIX)/lib/spaceroom/spaceroom"
	ditto $(CLI_DIR)/SpaceroomCore_SpaceroomCore.bundle "$(PREFIX)/lib/spaceroom/SpaceroomCore_SpaceroomCore.bundle"
	@# A wrapper, not a symlink: the binary finds its rules next to its real location.
	printf '#!/bin/sh\nexec "%s/lib/spaceroom/spaceroom" "$$@"\n' "$(PREFIX)" > "$(PREFIX)/bin/spaceroom"
	chmod 755 "$(PREFIX)/bin/spaceroom"
	@echo "✓ installed $(PREFIX)/bin/spaceroom"

clean: ## Remove build products (keeps dist/)
	rm -rf build $(PROJECT)
