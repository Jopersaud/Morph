# Morph — local file converter for macOS.
#
# Everything here works with a free Apple ID, or none at all (SPEC §13).
# Requires Xcode and XcodeGen: `brew install xcodegen`.

SHELL := /bin/bash

PROJECT := Morph.xcodeproj
SCHEME := Morph
DERIVED_DATA := build
RELEASE_PRODUCTS := $(DERIVED_DATA)/Build/Products/Release
APP := $(RELEASE_PRODUCTS)/Morph.app
CLI := $(RELEASE_PRODUCTS)/morph

# Where `make install` puts things. Override for a per-user install:
#   make install APP_DIR=~/Applications
APP_DIR ?= /Applications
BIN_DIR ?= $(HOME)/.local/bin

# Signing team, if Local.xcconfig names one. Empty means ad-hoc, which needs no
# Apple account at all.
DEV_TEAM := $(shell test -f Local.xcconfig && \
	sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' Local.xcconfig | tail -1)

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Morph — make targets"
	@echo
	@echo "  make generate       Regenerate Morph.xcodeproj from project.yml"
	@echo "  make build          Debug build"
	@echo "  make test           Package tests + xcodebuild test (the M0 gate)"
	@echo "  make test-packages  Just the Swift package tests (fast)"
	@echo "  make lint           Network guard, formatting, architecture checks"
	@echo "  make format         Reformat sources in place"
	@echo "  make install        Release build, install to $(APP_DIR), register the extension"
	@echo "  make install-cli    Link the morph CLI into $(BIN_DIR) (M6)"
	@echo "  make uninstall      Remove the app, the CLI link and the extension"
	@echo "  make clean          Delete build output and the generated project"

# Fails with an explanation rather than a confusing tool error.
define require_xcode
@command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1 || { \
	echo "error: this target needs Xcode, not just the Command Line Tools."; \
	echo "       Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app"; \
	exit 1; \
}
endef

define require_xcodegen
@command -v xcodegen >/dev/null 2>&1 || { \
	echo "error: XcodeGen is missing. Install it with: brew install xcodegen"; \
	exit 1; \
}
endef

.PHONY: generate
generate:
	$(require_xcodegen)
	xcodegen generate

.PHONY: build
build: generate
	$(require_xcode)
	xcodebuild $(XCODEBUILD_FLAGS) -configuration Debug build

.PHONY: test
test: test-packages test-app

.PHONY: test-packages
test-packages:
	@./Scripts/test-packages.sh test

.PHONY: test-app
test-app: generate
	$(require_xcode)
	xcodebuild $(XCODEBUILD_FLAGS) -configuration Debug -destination 'platform=macOS' test

.PHONY: lint
lint:
	@./Scripts/network-guard.sh
	@./Scripts/lint.sh

.PHONY: format
format:
	swift format --in-place --recursive Apps Packages Tests

# SPEC §13: build Release, sign with the local team or ad-hoc, install, then
# register the Finder extension.
.PHONY: install
install: generate
	$(require_xcode)
ifeq ($(strip $(DEV_TEAM)),)
	@echo "▸ Signing ad-hoc (no DEVELOPMENT_TEAM in Local.xcconfig)."
	@echo "  The Finder extension may refuse to load; see README."
	xcodebuild $(XCODEBUILD_FLAGS) -configuration Release build
else
	@echo "▸ Signing with team $(DEV_TEAM)."
	xcodebuild $(XCODEBUILD_FLAGS) -configuration Release \
		DEVELOPMENT_TEAM=$(DEV_TEAM) build
endif
	@echo "▸ Installing to $(APP_DIR)/Morph.app"
	@rm -rf "$(APP_DIR)/Morph.app"
	@mkdir -p "$(APP_DIR)"
	@cp -R "$(APP)" "$(APP_DIR)/Morph.app"
	@echo "▸ Registering morph:// and the Services menu"
	@$(LSREGISTER) -f "$(APP_DIR)/Morph.app"
	@/System/Library/CoreServices/pbs -update || true
	@extension_id=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
		"$(APP_DIR)/Morph.app/Contents/PlugIns/MorphFinderSync.appex/Contents/Info.plist"); \
	echo "▸ Registering the Finder extension ($$extension_id)"; \
	pluginkit -a "$(APP_DIR)/Morph.app/Contents/PlugIns/MorphFinderSync.appex" 2>/dev/null || true; \
	pluginkit -e use -i "$$extension_id" || \
		echo "  warning: pluginkit could not enable the extension; enable it by hand below"
	@echo
	@echo "Installed. Next steps:"
	@echo "  1. Open $(APP_DIR)/Morph.app once and follow its two setup screens."
	@echo "  2. If 'Convert to' is missing from Finder's context menu, turn it on in"
	@echo "     System Settings → General → Login Items & Extensions → Finder."

# M6 wires this into `make install` (SPEC §12).
.PHONY: install-cli
install-cli:
	@test -x "$(CLI)" || { echo "error: run 'make install' first to build Release"; exit 1; }
	@mkdir -p "$(BIN_DIR)"
	@ln -sf "$(abspath $(CLI))" "$(BIN_DIR)/morph"
	@echo "Linked $(BIN_DIR)/morph"
	@case ":$$PATH:" in \
		*":$(BIN_DIR):"*) ;; \
		*) echo "note: $(BIN_DIR) is not on your PATH" ;; \
	esac

.PHONY: uninstall
uninstall:
	@if [ -d "$(APP_DIR)/Morph.app" ]; then \
		extension_id=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
			"$(APP_DIR)/Morph.app/Contents/PlugIns/MorphFinderSync.appex/Contents/Info.plist" \
			2>/dev/null); \
		if [ -n "$$extension_id" ]; then \
			echo "▸ Deregistering $$extension_id"; \
			pluginkit -e ignore -i "$$extension_id" 2>/dev/null || true; \
		fi; \
		echo "▸ Removing $(APP_DIR)/Morph.app"; \
		$(LSREGISTER) -u "$(APP_DIR)/Morph.app" 2>/dev/null || true; \
		rm -rf "$(APP_DIR)/Morph.app"; \
	else \
		echo "Morph is not installed in $(APP_DIR)"; \
	fi
	@if [ -L "$(BIN_DIR)/morph" ]; then \
		echo "▸ Removing $(BIN_DIR)/morph"; \
		rm -f "$(BIN_DIR)/morph"; \
	fi

.PHONY: clean
clean:
	rm -rf $(DERIVED_DATA) $(PROJECT)
	rm -rf Packages/*/.build Packages/Engines/*/.build
