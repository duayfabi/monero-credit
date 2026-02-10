set shell := [ "bash", "-euo", "pipefail", "-c" ]
set script-interpreter := [ "bash", "-euo", "pipefail" ]

default:
  @just --list


# --- PROJECT Build & CI ---

# Nettoyer le workspace
clean:
  cargo clean

# Format + Clippy
lint:
  cargo fmt --all
  cargo clippy --all-targets --all-features -- -D warnings

# Tests unitaires + d’intégration
test:
  cargo test --all-targets --all-features

# Build release natif
build-native:
  cargo build --release

# Build release statique (musl)
build-musl:
  cargo build --release --target x86_64-unknown-linux-musl

# Build global (les deux variantes)
build: build-native build-musl

# CI = fmt + clippy + tests + builds
ci: lint test build



# --- AI Cockpit ---
notes:
  mkdir -p notes/plans/
  mkdir -p notes/briefs/
  test -f notes/ci.md || echo "# CI" > notes/ci.md
  test -f notes/review.md || echo "# Review" > notes/review.md
  test -f notes/handoff.md || echo "# Handoff" > notes/handoff.md

cockpit: notes
  zellij --layout .zellij/aider-agents.kdl

# --- Planner --- initial ---
[script]
agent-plan SLUG OBJECTIF: notes
  set -euo pipefail

  date="$(date +%Y-%m-%d)"
  brief="notes/briefs/${date}-{{SLUG}}.md"
  plan="notes/plans/${date}-{{SLUG}}-v1.md"

  mkdir -p notes/briefs notes/plans

  if [ -f "$brief" ]; then
    echo "❌ Le brief existe déjà: $brief" >&2
    exit 1
  fi

  printf "# Brief %s — %s\n\n## [v1] Objectif (immuable)\n  %s\n\n## [v2] Amendements\n- \n" \
    "$date" "{{SLUG}}" "{{OBJECTIF}}" > "$brief"

  echo "✅ Brief créé: $brief"

  tmp="$(mktemp)"
  cat .aider/prompts/plan.md > "$tmp"
  echo "" >> "$tmp"
  printf "Version demandée: v1\nPlan à créer: %s\nBrief: %s\n\n" "$plan" "$brief" >> "$tmp"
  cat "$brief" >> "$tmp"

  aider --config .aider/plan.yml --no-show-model-warnings --no-stream --no-restore-chat-history --yes --message-file "$tmp"
  rm -f "$tmp"


# --- Planner --- amend ---
# Usage:
#   just agent-plan-amend justfile-ci v2          # date du jour
#   just agent-plan-amend justfile-ci v2 2026-01-10
[script]
agent-amend SLUG VERSION DATE="": notes
  set -euo pipefail

  if [ -n "{{DATE}}" ]; then
    date="{{DATE}}"
  else
    date="$(date +%Y-%m-%d)"
  fi

  brief="notes/briefs/${date}-{{SLUG}}.md"
  plan="notes/plans/${date}-{{SLUG}}-{{VERSION}}.md"

  if [ ! -f "$brief" ]; then
    echo "❌ Brief introuvable: $brief" >&2
    echo "→ Vérifie la date, ou crée-le: just agent-plan {{SLUG}} \"<objectif>\"" >&2
    exit 1
  fi

  if [ -f "$plan" ]; then
    echo "❌ Le plan existe déjà: $plan" >&2
    exit 1
  fi

  tmp="$(mktemp)"
  cat .aider/prompts/plan_amend.md > "$tmp"
  echo "" >> "$tmp"
  printf "Version demandée: %s\nPlan à créer: %s\nBrief: %s\n\n" "{{VERSION}}" "$plan" "$brief" >> "$tmp"
  cat "$brief" >> "$tmp"

  aider --config .aider/plan.yml --no-show-model-warnings --no-stream --no-restore-chat-history --yes --message-file "$tmp"

  rm -f "$tmp"


# --- Developer ---
[script]
agent-dev SLUG VERSION DATE="": notes
  # Branche de travail
  branch="agent/{{SLUG}}-{{VERSION}}"
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"

  # Résoudre le fichier plan
  if [ -n "{{DATE}}" ]; then
    plan="notes/plans/{{DATE}}-{{SLUG}}-{{VERSION}}.md"
  else
    plan="$(ls -1 notes/plans/*-{{SLUG}}-{{VERSION}}.md 2>/dev/null | tail -n 1 || true)"
  fi

  if [ -z "${plan:-}" ] || [ ! -f "$plan" ]; then
    echo "❌ Plan introuvable: {{SLUG}} {{VERSION}}" >&2
    echo "→ Exemples :" >&2
    echo "   just agent-dev {{SLUG}} {{VERSION}}" >&2
    echo "   just agent-dev {{SLUG}} {{VERSION}} 2026-01-10" >&2
    exit 1
  fi

  echo "✅ Branche : $branch"
  echo "✅ Plan    : $plan"

  # Construire le prompt pour Aider
  tmp="$(mktemp)"
  cat .aider/prompts/dev.md > "$tmp"
  echo "" >> "$tmp"
  printf "Branche actuelle: %s\nSLUG: %s\nVersion: %s\nPlan: %s\n\n" \
    "$branch" "{{SLUG}}" "{{VERSION}}" "$plan" >> "$tmp"

  aider --config .aider/dev.yml --no-show-model-warnings --no-stream --no-restore-chat-history --yes . --message-file "$tmp"

  rm -f "$tmp"


# --- Tester ---
agent-test: notes
  cat .aider/prompts/test.md | aider --config .aider/test.yml --no-show-model-warnings --no-stream --no-restore-chat-history --yes

# --- Reviewer ---
agent-review: notes
  cat .aider/prompts/review.md | aider --config .aider/review.yml --no-show-model-warnings --no-stream --no-restore-chat-history --yes