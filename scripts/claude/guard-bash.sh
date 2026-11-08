#!/usr/bin/env bash
# PreToolUse hook for Bash. Exit 2 blocks the command (stderr goes back to Claude).
# Rules written in CLAUDE.md get forgotten by agents; this hook does not.
set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

block() {
  echo "Blocked by scripts/claude/guard-bash.sh: $1" >&2
  exit 2
}

ask() {
  jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# Git: shared index between agents, history on main.
grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(update-index|update-ref|read-tree|write-tree|commit-tree|symbolic-ref)' <<<"$cmd" && block "git plumbing commands are not allowed."
grep -Eq 'git[[:space:]]+add[[:space:]]+(-N|--intent-to-add|-A|--all|\.([[:space:]]|$))' <<<"$cmd" && block "stage files by path (git add <paths>), never -A, . or -N."
grep -Eq 'git[[:space:]]+stash' <<<"$cmd" && block "git stash is not allowed: the working tree is shared."
grep -Eq 'git[[:space:]]+reset[[:space:]]+.*--hard' <<<"$cmd" && block "git reset --hard is not allowed."
grep -Eq 'git[[:space:]]+(checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)' <<<"$cmd" && block "discarding all working-tree changes is not allowed."
grep -Eq 'git[[:space:]]+push([[:space:]].*)?[[:space:]](main|master)([[:space:]]|$)' <<<"$cmd" && block "never push to main: open a pull request."
grep -Eq 'git[[:space:]]+push([[:space:]].*)?[[:space:]](-f|--force)([[:space:]]|$)' <<<"$cmd" && block "force push is not allowed (use --force-with-lease on your own branch, and ask first)."

# Database: destructive tasks only in the test environment.
if grep -Eq 'db:(drop|reset|rollback|purge|schema:load|truncate_all|migrate:reset|seed:replant)' <<<"$cmd" &&
   ! grep -Eq 'RAILS_ENV=test' <<<"$cmd"; then
  block "destructive db:* tasks run only with RAILS_ENV=test. Fix the migration, never the database."
fi

# Secrets.
if grep -Eq '(cat|less|more|head|tail|bat|grep|source|\.)[[:space:]]+[^|;&]*\.env([.[:space:]]|$)' <<<"$cmd" &&
   ! grep -Eq '\.env\.example' <<<"$cmd"; then
  block "reading .env files is not allowed."
fi
grep -Eq 'config/(master\.key|credentials)' <<<"$cmd" && block "secrets in config/ are not readable by Claude."

# Downloads: Hugo is often on a mobile data plan.
grep -Eq 'docker[[:space:]]+pull' <<<"$cmd" && ask "docker pull downloads an image: confirm size and network first."

exit 0
