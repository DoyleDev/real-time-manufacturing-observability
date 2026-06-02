# Lakebase PR Validation — Demo Script

A live-demo narrative for showing **Lakebase branching + GitHub Actions + AI Gateway** as a CI/CD safety net for production schema changes. Built around the `real-time-manufacturing-observability` repo.

> **Known blocker (as of writing):** the target workspace has an IP allow-list that blocks GitHub-hosted runner egress (e.g. `40.116.93.49`). Either run the action from a self-hosted runner inside the allow-listed network, or add the GitHub Actions IP range to the workspace ACL, before running the demo live.

---

## The setup (told live)

> "Every manufacturing ops team I talk to has the same nightmare: somebody pushes a schema change Friday afternoon, the line dashboard goes dark Saturday morning, and on-call spends the weekend reconstructing what 'simple' migration broke production. Today I'll show you how Lakebase branching + an AI reviewer turns that nightmare into a paved road — without copying a single byte of data."

---

## Act 0 — Baseline (already in `main`)

Commit this to `main` first so the demo has a starting state. A realistic manufacturing-floor table:

```sql
-- migrations/001_machine_events.sql
CREATE TABLE IF NOT EXISTS machine_events (
    event_id        BIGSERIAL PRIMARY KEY,
    machine_id      TEXT NOT NULL,
    line_id         TEXT NOT NULL,
    event_ts        TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type      TEXT NOT NULL CHECK (event_type IN ('RUN','IDLE','FAULT','SETUP')),
    temperature_c   NUMERIC(6,2),
    rpm             INTEGER,
    operator_id     TEXT
);

CREATE INDEX IF NOT EXISTS ix_machine_events_machine_ts
    ON machine_events (machine_id, event_ts DESC);

INSERT INTO machine_events (machine_id, line_id, event_type, temperature_c, rpm, operator_id)
SELECT
    'M' || (1 + (g % 12)),
    'LINE-' || (1 + (g % 3)),
    (ARRAY['RUN','RUN','RUN','IDLE','FAULT','SETUP'])[1 + (g % 6)],
    60 + (random() * 40),
    (800 + (random() * 600))::INT,
    'OP-' || (100 + (g % 8))
FROM generate_series(1, 50000) g;
```

Land that on `main` once — now `production` has a real table with 50k rows and a tight, sensible schema.

---

## Act 1 — The safe additive change (the happy path)

**Branch:** `feat/add-quality-score`
**PR title:** *Add quality_score column for downstream OEE dashboard*
**PR body:**
> Field engineering needs a per-event quality score (0-100) to drive the new OEE widget in the line dashboard. Defaulting to 100 (perfect) so historical rows stay valid. Tests: confirm column is nullable-with-default, confirm existing rows are populated, confirm dashboard queries still resolve.

```sql
-- migrations/002_add_quality_score.sql
ALTER TABLE machine_events
    ADD COLUMN quality_score SMALLINT NOT NULL DEFAULT 100
    CHECK (quality_score BETWEEN 0 AND 100);

CREATE INDEX ix_machine_events_low_quality
    ON machine_events (line_id, event_ts DESC)
    WHERE quality_score < 80;
```

**What the audience sees:**
- GitHub Action spins up `pr-1-feat-add-quality-score` off `production` in seconds — no data copy.
- psql runs cleanly. Row count on `machine_events` = 50,000 (preserved).
- AI reviewer comments: *"Additive change, NOT NULL with DEFAULT is safe at this row count. Partial index is well-scoped. **APPROVE.**"*

**Demo punchline:** "Notice we just ran a real `ALTER TABLE` against a real fork of production data. Nothing copied. Production is untouched. Merge → done."

---

## Act 2 — The lurking footgun (AI catches what humans miss)

**Branch:** `feat/operator-pii-cleanup`
**PR title:** *Normalize operator_id to NOT NULL*
**PR body:**
> Compliance asked us to make operator_id required so we always know who was on the line. Adding NOT NULL constraint.

```sql
-- migrations/003_operator_required.sql
ALTER TABLE machine_events
    ALTER COLUMN operator_id SET NOT NULL;
```

**What the audience sees:**
- Branch spins up, psql runs… and **fails** with a constraint violation because some seed rows are NULL (or because a backfill is missing).
- Or even worse — it succeeds, but the AI reviewer flags it: *"This statement acquires an `ACCESS EXCLUSIVE` lock and full-table-scans `machine_events`. At 50k rows it's fine; at 50M (production scale) it will block writes for minutes. **REQUEST_CHANGES.** Recommended pattern: add `CHECK (operator_id IS NOT NULL) NOT VALID`, run `VALIDATE CONSTRAINT` concurrently, then promote to NOT NULL."*

**Demo punchline:** "The branch absorbed the blast. Production never saw it. The AI reviewer didn't just tell us it ran — it told us what would have happened at 1000x the data."

---

## Act 3 — The destructive change (the save)

**Branch:** `refactor/drop-temperature`
**PR title:** *Remove temperature_c — moving to dedicated sensor table*

```sql
-- migrations/004_drop_temperature.sql
ALTER TABLE machine_events DROP COLUMN temperature_c;
```

**What the audience sees:**
- Branch spins up, drop succeeds on the fork.
- AI reviewer: *"`temperature_c` is referenced by [the dashboard query], the index `ix_machine_events_machine_ts` is unaffected but downstream dashboards will 500. PR description does not mention dashboard migration. **BLOCK** pending dashboard PR."*
- You merge nothing. You go fix the dashboard first.

**Demo punchline:** "The branch is disposable. We tried the scariest thing — `DROP COLUMN` — against real production-shaped data, and got a coherent answer about whether the rest of the world is ready for it. Try that with a staging clone that's six weeks stale."

---

## Act 4 — The test-case story (full AI workflow)

**Branch:** `feat/fault-severity`
**PR title:** *Add fault_severity column with backfill*
**PR body:**
> Adding `fault_severity` (LOW/MED/HIGH/CRITICAL) populated from existing fault patterns.
>
> **Test cases:**
> 1. Every existing FAULT row gets a non-null severity.
> 2. No non-FAULT row gets a severity assigned.
> 3. CRITICAL count > 0 (we know we've had critical faults in the seed data).
> 4. Query `SELECT line_id, fault_severity, count(*) FROM machine_events GROUP BY 1,2` runs < 200ms.

```sql
-- migrations/005_fault_severity.sql
ALTER TABLE machine_events
    ADD COLUMN fault_severity TEXT
    CHECK (fault_severity IN ('LOW','MED','HIGH','CRITICAL'));

UPDATE machine_events
SET fault_severity = CASE
    WHEN rpm > 1200 AND temperature_c > 90 THEN 'CRITICAL'
    WHEN temperature_c > 85                THEN 'HIGH'
    WHEN rpm < 500                         THEN 'MED'
    ELSE 'LOW'
END
WHERE event_type = 'FAULT';

CREATE INDEX ix_machine_events_severity
    ON machine_events (fault_severity, event_ts DESC)
    WHERE fault_severity IS NOT NULL;
```

**What the audience sees:** The AI comment renders the test plan inline and answers each one against the executed branch — *"Test 1: PASS — 8,332/8,332 fault rows populated. Test 2: PASS — 0 non-fault rows assigned. Test 3: PASS — 412 CRITICAL events. Test 4: WARN — index helps but consider adding `line_id` as leading column. **APPROVE with suggestion.**"*

**Demo punchline:** "The PR author wrote tests in plain English. The AI ran them against real data on an isolated branch and gave you a per-test verdict. Your reviewer reads four bullet points instead of guessing."

---

## The closer (the slide you end on)

> "Three things just happened that don't happen anywhere else:
>
> 1. **Copy-on-write branching** gave every PR a real production fork in seconds with zero storage cost.
> 2. **psql against the branch** ran the actual migration against actual production-shaped data — not a sanitized clone, not a synthetic fixture.
> 3. **Claude on the AI Gateway** turned execution output into a code review that understands intent, locking, downstream impact, and your written test cases.
>
> And when the PR closes, the branch evaporates. There's nothing to clean up, nothing to pay for, nothing to drift out of sync with prod."

---

## Suggested demo order if you have 10 minutes

1. Show the baseline table already in `main` (30 sec).
2. Open Act 1 PR → watch action run → show green comment (2 min).
3. Open Act 4 PR (the test-cases one) — this is the wow moment (3 min).
4. Open Act 2 or Act 3 (your pick) to show the "save" (3 min).
5. Close one PR, show the branch deleted in the Databricks UI (1 min).

---

## Pre-flight checklist

Before running this demo live, confirm:

- [ ] Repository secrets configured (`DATABRICKS_HOST`, `DATABRICKS_TOKEN`, `LAKEBASE_PROJECT=machine-floor-project`, `LAKEBASE_SOURCE_BRANCH=production`, `LAKEBASE_DATABASE=databricks_postgres`, `LAKEBASE_PG_USER`, `AI_GATEWAY_MODEL=databricks-claude-opus-4-7`).
- [ ] **Workspace IP ACL allows the runner.** Either:
  - Add GitHub Actions egress ranges to the workspace IP allow-list (see GitHub's [meta API](https://api.github.com/meta) → `actions` block), **or**
  - Switch the workflow's `runs-on:` to a self-hosted runner inside an allow-listed network.
- [ ] PAT identity (`grant.doyle@databricks.com`) has a Postgres role on the `production` branch with `CREATE`/`ALTER` on the target schema.
- [ ] Baseline migration `001_machine_events.sql` has been applied to `production` so the table exists with seed data.
- [ ] The four demo branches (`feat/add-quality-score`, `feat/operator-pii-cleanup`, `refactor/drop-temperature`, `feat/fault-severity`) are pre-created so you can open the PRs back-to-back during the talk.
