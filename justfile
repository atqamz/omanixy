set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

fmt:
    nix fmt

check:
    nix --option max-jobs 1 flake check --show-trace --print-build-logs
    ./scripts/verify

bootstrap:
    git config core.hooksPath .githooks
    chmod +x .githooks/* scripts/*
