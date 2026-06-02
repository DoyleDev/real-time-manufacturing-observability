-- migrations/002_add_quality_score.sql
ALTER TABLE machine_events
    ADD COLUMN quality_score SMALLINT NOT NULL DEFAULT 100
    CHECK (quality_score BETWEEN 0 AND 100);

CREATE INDEX ix_machine_events_low_quality
    ON machine_events (line_id, event_ts DESC)
    WHERE quality_score < 80;
