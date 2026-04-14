SHELL := /bin/zsh

PROJECT_NAME := MacTools
REMOTE_URL ?= git@github.com:owner/MacTools.git
PLACEHOLDER_REMOTE_URL := git@github.com:owner/MacTools.git
PROJECT_FILE := $(PROJECT_NAME).xcodeproj
WORKSPACE_FILE := $(PROJECT_NAME).xcworkspace
DERIVED_DATA := build/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/$(PROJECT_NAME).app

.PHONY: setup generate build run clean release-local

setup:
	@if [ ! -f LocalConfig.xcconfig ]; then cp LocalConfig.sample.xcconfig LocalConfig.xcconfig; fi
	@if [ ! -d .git ]; then git init; fi
	@git branch -M main
	@if [ "$(REMOTE_URL)" = "$(PLACEHOLDER_REMOTE_URL)" ]; then echo "Skipping origin remote setup. Pass REMOTE_URL=git@github.com:<owner>/MacTools.git to make setup when ready."; \
	else \
		if git remote get-url origin >/dev/null 2>&1; then git remote set-url origin $(REMOTE_URL); else git remote add origin $(REMOTE_URL); fi; \
	fi

generate:
	@xcodegen generate

build: generate
	@xcodebuild -project $(PROJECT_FILE) -scheme $(PROJECT_NAME) -configuration Debug -derivedDataPath $(DERIVED_DATA) build -quiet

run: build
	@open $(APP_PATH)

clean:
	@rm -rf build $(PROJECT_FILE) $(WORKSPACE_FILE)

release-local:
	@./scripts/release-local.sh $(ARGS)
