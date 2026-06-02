#!/usr/bin/env bash
# Demo helper — stage a single migration from migrations/stage/, simulate a PR,
# run the local validator, and (on `reset`) clean up the Lakebase branch.
#
# Usage:
#   ./.github/scripts/run_act.sh 2          # Stage migrations/stage/002_*.sql and run
#   ./.github/scripts/run_act.sh 3
#   ./.github/scripts/run_act.sh reset      # Unstage all and delete that act's branch
#   ./.github/scripts/run_act.sh list       # Show which migrations are staged vs available
#
# Each act gets its own Lakebase branch named pr-local-act-<N> so the workspace
# UI shows distinct branches per scenario during the demo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS="$REPO_ROOT/migrations"
STAGE="$REPO_ROOT/stage"
PROFILE="${DATABRICKS_CONFIG_PROFILE:-MFG}"
PROJECT="${LAKEBASE_PROJECT:-machine-floor-project}"

usage() {
  cat >&2 <<EOF
Usage: $0 <N> | reset | list
  <N>     Stage migration 00N_*.sql from migrations/stage/ and run validation.
  reset   Move any top-level migrations (except 001_*) back to stage/ and
          delete the Lakebase branch for the most recently run act.
  list    Show staged + available migrations.
EOF
  exit 2
}

list_state() {
  echo "Top-level migrations/ (will run on next validation):"
  ls -1 "$MIGRATIONS"/*.sql 2>/dev/null | sed 's|.*/|  |' || echo "  (none)"
  echo
  echo "Staged in migrations/stage/ (waiting for an act):"
  ls -1 "$STAGE"/*.sql 2>/dev/null | sed 's|.*/|  |' || echo "  (none)"
}

find_stage_file() {
  local n="$1"
  local padded
  padded=$(printf "%03d" "$n")
  local match
  match=$(ls -1 "$STAGE/${padded}_"*.sql 2>/dev/null | head -1 || true)
  if [[ -z "$match" ]]; then
    echo "::error::No file matching ${padded}_*.sql in $STAGE" >&2
    exit 1
  fi
  echo "$match"
}

unstage_all() {
  shopt -s nullglob
  for f in "$MIGRATIONS"/*.sql; do
    base=$(basename "$f")
    # Never move the baseline 001 back into stage.
    if [[ "$base" == 001_* ]]; then
      continue
    fi
    echo "Unstaging $base"
    mv "$f" "$STAGE/"
  done
}

current_act_branch() {
  # The most recent act number that is currently staged at top level.
  local f base
  for f in "$MIGRATIONS"/*.sql; do
    base=$(basename "$f")
    case "$base" in
      002_*) echo "pr-local-act-2"; return ;;
      003_*) echo "pr-local-act-3"; return ;;
      004_*) echo "pr-local-act-4"; return ;;
      005_*) echo "pr-local-act-5"; return ;;
    esac
  done
  # Fallback: read last-act file written below.
  if [[ -f "$SCRIPT_DIR/.last_act" ]]; then
    cat "$SCRIPT_DIR/.last_act"
  fi
}

delete_branch() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "No branch to delete (no prior act recorded)."
    return 0
  fi
  echo "Deleting Lakebase branch: projects/$PROJECT/branches/$branch"
  DATABRICKS_CONFIG_PROFILE="$PROFILE" databricks postgres delete-branch \
    "projects/$PROJECT/branches/$branch" >/dev/null 2>&1 \
    && echo "  deleted." \
    || echo "  (delete failed or branch didn't exist — continuing.)"
}

case "${1:-}" in
  "" ) usage ;;
  list ) list_state ;;
  reset )
    branch=$(current_act_branch)
    unstage_all
    delete_branch "$branch"
    rm -f "$SCRIPT_DIR/.last_act"
    ;;
  [1-9]|0[0-9]|[1-9][0-9] )
    n="$1"
    padded=$(printf "%03d" "$n")
    # Prefer a file already at migrations/ top level; otherwise pull from stage/.
    existing=$(ls -1 "$MIGRATIONS/${padded}_"*.sql 2>/dev/null | head -1 || true)
    if [[ -n "$existing" ]]; then
      dest="$existing"
      echo "$(basename "$dest") already in migrations/ — running validation as-is."
    else
      src=$(find_stage_file "$n")
      dest="$MIGRATIONS/$(basename "$src")"
      echo "Staging $(basename "$src") -> migrations/"
      mv "$src" "$dest"
    fi
    branch="pr-local-act-$n"
    echo "$branch" > "$SCRIPT_DIR/.last_act"
    # Override the per-run Lakebase branch name so each act gets its own.
    PR_HEAD_REF="act-$n" PR_NUMBER="local" \
      PR_TITLE="Act $n demo — $(basename "$dest")" \
      "$SCRIPT_DIR/run_local.sh" "$dest"
    ;;
  * ) usage ;;
esac
