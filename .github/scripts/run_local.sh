#!/usr/bin/env bash
# Run the Lakebase PR validation locally against the MFG workspace.
#
# Usage:
#   ./.github/scripts/run_local.sh migrations/002_add_quality_score.sql
#   ./.github/scripts/run_local.sh $(git diff --name-only main -- '*.sql')
#
# Reads DATABRICKS_HOST + DATABRICKS_TOKEN from the MFG databrickscfg profile
# (override with DATABRICKS_CONFIG_PROFILE). Skips the GitHub PR comment.

set -euo pipefail

PROFILE="${DATABRICKS_CONFIG_PROFILE:-MFG}"
CFG="${HOME}/.databrickscfg"

if [[ ! -f "$CFG" ]]; then
  echo "No ~/.databrickscfg found." >&2
  exit 1
fi

# Extract host from the named profile.
HOST=$(awk -v p="[$PROFILE]" '
  $0==p {found=1; next}
  /^\[/ {found=0}
  found && /^host[[:space:]]*=/ {sub(/^host[[:space:]]*=[[:space:]]*/,""); print; exit}
' "$CFG")

if [[ -z "$HOST" ]]; then
  echo "Profile [$PROFILE] not found in $CFG" >&2
  exit 1
fi

export DATABRICKS_HOST="$HOST"

# If DATABRICKS_TOKEN is already set in the environment, use that as-is.
# Otherwise, mint a short-lived token from the CLI for this profile.
if [[ -z "${DATABRICKS_TOKEN:-}" ]]; then
  TOKEN=$(databricks auth token --profile "$PROFILE" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])' 2>/dev/null || true)
  if [[ -z "$TOKEN" ]]; then
    echo "Could not obtain token via 'databricks auth token --profile $PROFILE'." >&2
    echo "Run 'databricks auth login --profile $PROFILE' first, or export DATABRICKS_TOKEN manually." >&2
    exit 1
  fi
  export DATABRICKS_TOKEN="$TOKEN"
fi
export LAKEBASE_PROJECT="${LAKEBASE_PROJECT:-machine-floor-project}"
export LAKEBASE_SOURCE_BRANCH="${LAKEBASE_SOURCE_BRANCH:-production}"
export LAKEBASE_DATABASE="${LAKEBASE_DATABASE:-databricks_postgres}"
export LAKEBASE_PG_USER="${LAKEBASE_PG_USER:-grant.doyle@databricks.com}"
export AI_GATEWAY_MODEL="${AI_GATEWAY_MODEL:-databricks-claude-opus-4-7}"

# Fake PR context so the script + AI prompt have something useful to show.
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "local")
export PR_NUMBER="${PR_NUMBER:-local}"
export PR_TITLE="${PR_TITLE:-Local dry-run on $BRANCH}"
export PR_BODY="${PR_BODY:-Local invocation via run_local.sh — no GitHub PR backing this run.}"
export PR_HEAD_REF="${PR_HEAD_REF:-$BRANCH}"

if [[ $# -eq 0 ]]; then
  # Default: changed (tracked) + untracked migration .sql files vs main.
  FILES=()
  while IFS= read -r line; do
    [[ -n "$line" && -f "$line" ]] && FILES+=("$line")
  done < <(
    {
      git diff --name-only main -- 'migrations/*.sql' 2>/dev/null
      git ls-files --others --exclude-standard -- 'migrations/*.sql' 2>/dev/null
    } | sort -u
  )
  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No SQL files passed and no changed/untracked files under migrations/*.sql vs main." >&2
    echo "Usage: $0 [sql_file ...]" >&2
    exit 2
  fi
  echo "Auto-detected migrations: ${FILES[*]}"
  set -- "${FILES[@]}"
fi

# Install deps into a local venv if not already present.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${SCRIPT_DIR}/.venv-local"
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
fi

exec "$VENV/bin/python" "$SCRIPT_DIR/lakebase_pr_validate.py" "$@"
