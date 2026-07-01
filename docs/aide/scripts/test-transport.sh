#!/usr/bin/env bash
# test-transport.sh — harvested by speckit.aide.feedback-loop on 2026-07-01.
# Captures a command that recurred across multiple work items so every future
# item runs it the same way without re-deriving it. Edit freely; if you change
# what it does, note it in docs/aide/feedback/changelog.md.
set -euo pipefail

raco test mcp/transport/
