set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

fmt:
    nix fmt

check:
    nix flake check --show-trace
    ./scripts/verify

bootstrap:
    git config core.hooksPath .githooks
    chmod +x .githooks/* scripts/*
