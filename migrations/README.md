# Migrations

SQL migrations applied to the Lakebase `production` branch. Every PR that touches
files in this directory is automatically:

1. Run against a fresh copy-on-write Lakebase branch (via [.github/workflows/lakebase-pr-validate.yml](../.github/workflows/lakebase-pr-validate.yml)).
2. Reviewed by Claude on the Databricks AI Gateway, which posts the report as a PR comment.

## Layout

```
migrations/
  001_machine_events.sql     # Baseline schema. Already applied to production.
  README.md                  # This file.

stage/                       # Demo holding pen at the repo root.
  002_add_quality_score.sql  # Act 1 — happy path
  003_operator_required.sql  # Act 2 — lurking footgun
  004_drop_temperature.sql   # Act 3 — destructive change
  005_fault_severity.sql     # Act 4 — test-case story
```

The workflow only watches `migrations/**/*.sql`. Files in `stage/` are invisible
to CI — they're just a parking lot for the demo helper to pull from.

## Demo helper

[`.github/scripts/run_act.sh`](../.github/scripts/run_act.sh) drives the live demo
without needing GitHub (useful while the workspace IP allow-list blocks
GitHub-hosted runners). Each act gets its own Lakebase branch
(`pr-local-act-<N>`) so the workspace UI shows distinct branches as you progress.

```bash
./.github/scripts/run_act.sh list     # See what's staged vs available

./.github/scripts/run_act.sh 2        # Act 1 (file 002) → branch pr-local-act-2
./.github/scripts/run_act.sh reset    # Unstage 002 + delete its branch

./.github/scripts/run_act.sh 3        # Act 2 (file 003) → branch pr-local-act-3
./.github/scripts/run_act.sh reset

./.github/scripts/run_act.sh 4        # Act 3 (file 004) → branch pr-local-act-4
./.github/scripts/run_act.sh reset

./.github/scripts/run_act.sh 5        # Act 4 (file 005) → branch pr-local-act-5
./.github/scripts/run_act.sh reset
```

**`<N>`** — moves `stage/00N_*.sql` to `migrations/`, runs the validator against
a fresh Lakebase branch, prints the AI report.

**`reset`** — moves any `00[2-9]_*.sql` back to `stage/` (leaves `001` alone),
deletes the most recent branch.

## Running ad-hoc (no demo helper)

```bash
# Validate whatever's currently in migrations/ vs main:
./.github/scripts/run_local.sh

# Or pass explicit files:
./.github/scripts/run_local.sh migrations/002_add_quality_score.sql
```

## Files

| File | Purpose | Demo act |
|---|---|---|
| `001_machine_events.sql` | Baseline schema + 50k row seed (with ~515 NULL `operator_id` rows so Act 2 has a real failure). Apply once to `production`. | Act 0 (baseline) |
| `stage/002_add_quality_score.sql` | Additive column with default, partial index. | Act 1 (happy path) |
| `stage/003_operator_required.sql` | `SET NOT NULL` on a column that has NULL rows — will fail. | Act 2 (lurking footgun) |
| `stage/004_drop_temperature.sql` | Destructive `DROP COLUMN`. | Act 3 (downstream-impact save) |
| `stage/005_fault_severity.sql` | Additive + backfill with declared test cases. | Act 4 (test-case story) |

## Bootstrapping production (one-time)

`001_machine_events.sql` must be applied to the `production` branch before the
demo so subsequent acts have a real table to mutate:

```bash
# Mint a credential for the production endpoint:
DATABRICKS_CONFIG_PROFILE=MFG databricks postgres generate-database-credential \
  projects/machine-floor-project/branches/production/endpoints/primary

# Then connect with psql (host from `databricks postgres get-endpoint`):
PGPASSWORD=<token> PGSSLMODE=require psql \
  -h <prod-endpoint-host> \
  -U grant.doyle@databricks.com \
  -d databricks_postgres \
  -f migrations/001_machine_events.sql
```
