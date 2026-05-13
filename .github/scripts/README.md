# Lakebase PR Validation

Spins up a Lakebase branch per PR, runs the PR's changed SQL files against it, has
Claude (via the Databricks AI Gateway) review the change + execution output, and
posts the result back as a PR comment. The branch is deleted when the PR closes.

## Required GitHub Secrets

| Secret | Example | Notes |
|---|---|---|
| `DATABRICKS_HOST` | `https://fevm-mfg-lb-epl.cloud.databricks.com` | Workspace URL, no trailing slash |
| `DATABRICKS_TOKEN` | `dapi...` | PAT with workspace + Lakebase permissions |
| `LAKEBASE_PROJECT` | `machine-floor-project` | Project id (not the `projects/...` path) |
| `LAKEBASE_SOURCE_BRANCH` | `production` | Branch to fork from (default `production`) |
| `LAKEBASE_DATABASE` | `databricks_postgres` | Postgres database name |
| `LAKEBASE_PG_USER` | `grant.doyle@databricks.com` | Postgres role used to connect |
| `AI_GATEWAY_MODEL` | `databricks-claude-opus-4-7` | Serving endpoint model name |

## Flow

1. PR opened/updated touching `**/*.sql` → workflow triggers.
2. `lakebase_pr_validate.py`:
   - Creates branch `pr-<num>-<slug>` off `LAKEBASE_SOURCE_BRANCH` (24h TTL).
   - Waits for branch READY, fetches the primary endpoint host.
   - Calls `generateDatabaseCredential` for a short-lived token.
   - Runs each changed SQL file with `psql -v ON_ERROR_STOP=1`.
   - Collects per-table `count(*)` for tables referenced in the SQL.
   - Sends PR context + execution output to the AI Gateway and asks for a structured review.
   - Posts the rendered report as a PR comment.
3. On PR close → `lakebase_pr_cleanup.py` deletes the branch.
