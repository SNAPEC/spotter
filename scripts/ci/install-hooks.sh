#!/usr/bin/env bash
# Points git to the versioned hooks in .githooks/. Run once after cloning.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
chmod +x .githooks/*
git config core.hooksPath .githooks
echo "Git hooks installed from .githooks/ (pre-commit, pre-push)."
