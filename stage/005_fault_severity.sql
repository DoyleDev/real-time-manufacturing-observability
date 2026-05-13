-- Add a severity classification to fault events so the dashboard can
-- triage CRITICAL events ahead of LOW ones. Backfill is derived from
-- the existing rpm + temperature_c readings on FAULT rows.

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
