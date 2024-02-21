NVITOP_VERSION          := latest
NVITOP_EXPORTER_VERSION := latest
PLATFORMS               := linux/amd64
DOCKERCMD               := docker buildx build

REGISTRY ?= fernandezr

all: ubuntu22.04

push:
	$(MAKE) ubuntu22.04 OUTPUT=type=registry

local:
	$(MAKE) PLATFORMS=linux/amd64 OUTPUT=type=docker DOCKERCMD='docker build'

ubuntu22.04:
	$(DOCKERCMD) --pull \
		--output $(OUTPUT) \
		--platform $(PLATFORMS) \
		--tag "$(REGISTRY)/nvitop-exporter:$(NVITOP_EXPORTER_VERSION)" \
		--file Dockerfile.ubuntu22.04 .
