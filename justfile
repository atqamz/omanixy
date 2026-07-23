set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

fmt:
    nix fmt

check:
    nix flake check --show-trace
    ./scripts/verify

status:
    git status --porcelain=v1

review:
    git status --short
    git diff --stat
    git diff

staged:
    git diff --cached --stat
    git diff --cached

upstream-diff:
    ./scripts/upstream-diff

task-context task:
    ./scripts/task-context "{{task}}"

bootstrap:
    git config core.hooksPath .githooks
    chmod +x .githooks/* scripts/*
