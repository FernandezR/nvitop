SHELL := /bin/bash

NVITOP_VERSION          := latest
PLATFORMS               := linux/amd64
DOCKERCMD               := docker buildx build

REGISTRY ?= fernandezr

GITHUB_DEFAULT_BRANCH := main

all: ubuntu22.04

workflow:
ifeq ($(GITHUB_REF_NAME), $(GITHUB_DEFAULT_BRANCH))
	$(MAKE) ubuntu22.04 OUTPUT=type=registry
else
	$(MAKE) ubuntu22.04 OUTPUT=type=registry NVITOP_VERSION=$(GITHUB_REF_NAME)-ubuntu22.04
endif

push:
	$(MAKE) ubuntu22.04 OUTPUT=type=registry

local:
	$(MAKE) PLATFORMS=linux/amd64 OUTPUT=type=docker DOCKERCMD='docker build'

ubuntu22.04:
	$(DOCKERCMD) --pull \
		--output $(OUTPUT) \
		--platform $(PLATFORMS) \
		--tag "$(REGISTRY)/nvitop-exporter:$(NVITOP_VERSION)" \
		--file Dockerfile.ubuntu22.04 .
