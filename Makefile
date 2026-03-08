# Venus OS in Docker — Build automation
#
# Usage:
#   make build                     Build Docker image (full pipeline, requires root)
#   make test                      Run test suite against built image
#   make download                  Download Venus OS image only
#   make extract                   Extract rootfs from downloaded image (requires root)
#   make modify                    Apply container patches to rootfs
#   make clean                     Remove build artifacts
#   make help                      Show this help
#
# Variables (override on command line):
#   MACHINE=raspberrypi5           Target machine
#   FEED=release                   Venus OS feed (release|candidate|testing|develop)
#   VENUS_VERSION=latest           Venus OS version for tagging
#
# SPDX-License-Identifier: GPL-3.0-or-later

# ── Configuration ──────────────────────────────────────────────────────────────

MACHINE        ?= raspberrypi5
FEED           ?= release
VENUS_VERSION  ?= latest
IMAGE_REGISTRY ?= ghcr.io
IMAGE_OWNER    ?= rafaelka
IMAGE_NAME     ?= venus-os

BUILD_DIR      := build
DOWNLOAD_DIR   := $(BUILD_DIR)/downloads
STAGING_DIR    := $(BUILD_DIR)/rootfs-staging
OUTPUT_DIR     := $(BUILD_DIR)/output

SCRIPTS_DIR    := scripts
TESTS_DIR      := tests
DOCKER_DIR     := docker

IMAGE_TAG      := $(IMAGE_REGISTRY)/$(IMAGE_OWNER)/$(IMAGE_NAME):latest-$(MACHINE)
CONTAINER_NAME := venus-os-test

# Export for scripts
export MACHINE FEED VENUS_VERSION IMAGE_REGISTRY IMAGE_OWNER IMAGE_NAME

# ── Targets ────────────────────────────────────────────────────────────────────

.PHONY: help build test download extract modify package clean distclean

help: ## Show this help
	@echo "Venus OS in Docker — Build targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  MACHINE=$(MACHINE)  FEED=$(FEED)  VENUS_VERSION=$(VENUS_VERSION)"

build: download extract modify package ## Full build pipeline (requires root)
	@echo ""
	@echo "Build complete: $(IMAGE_TAG)"
	@echo "Run 'make test' to verify the image."

download: ## Download Venus OS image from Victron
	@chmod +x $(SCRIPTS_DIR)/*.sh
	bash $(SCRIPTS_DIR)/download-image.sh --machine $(MACHINE) --feed $(FEED)

extract: ## Extract rootfs from .wic image (requires root)
	bash $(SCRIPTS_DIR)/extract-rootfs.sh --machine $(MACHINE)

modify: ## Apply container-compatibility patches to rootfs
	bash $(SCRIPTS_DIR)/modify-rootfs.sh --rootfs $(STAGING_DIR) --machine $(MACHINE)

package: ## Create tarball and build Docker image
	@mkdir -p $(OUTPUT_DIR)
	tar -cf $(OUTPUT_DIR)/rootfs.tar -C $(STAGING_DIR) .
	docker build \
		-f $(DOCKER_DIR)/Dockerfile \
		-t $(IMAGE_TAG) \
		--build-arg ROOTFS_TAR=rootfs.tar \
		$(OUTPUT_DIR)
	@echo "Image built: $(IMAGE_TAG)"

test: ## Run test suite against the built image
	@chmod +x $(TESTS_DIR)/*.sh
	@echo "Starting test container..."
	@docker run -d --name $(CONTAINER_NAME) --privileged $(IMAGE_TAG) >/dev/null 2>&1 || true
	@echo "Waiting for Venus OS to initialize (15s)..."
	@sleep 15
	@bash $(TESTS_DIR)/run-all-tests.sh $(CONTAINER_NAME); \
		EXIT=$$?; \
		docker stop $(CONTAINER_NAME) >/dev/null 2>&1 || true; \
		docker rm $(CONTAINER_NAME) >/dev/null 2>&1 || true; \
		exit $$EXIT

run: ## Run the container interactively
	docker run -it --rm \
		--name venus-os \
		--privileged \
		--network host \
		-v venus-data:/data \
		$(IMAGE_TAG)

logs: ## Show logs from the running container
	docker logs -f venus-os 2>/dev/null || echo "No container named 'venus-os' is running."

stop: ## Stop the running container
	docker stop venus-os 2>/dev/null || true
	docker rm venus-os 2>/dev/null || true

push: ## Push the image to ghcr.io (requires docker login)
	docker push $(IMAGE_TAG)

clean: ## Remove build artifacts (keep downloads)
	rm -rf $(STAGING_DIR) $(OUTPUT_DIR)
	docker rm -f $(CONTAINER_NAME) 2>/dev/null || true

distclean: clean ## Remove everything including downloads
	rm -rf $(BUILD_DIR)
