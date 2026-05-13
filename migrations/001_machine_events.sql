-- Baseline schema: production line event stream.
-- Apply once to `production` so the demo branches have a real table to mutate.

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
    CASE WHEN g % 97 = 0 THEN NULL ELSE 'OP-' || (100 + (g % 8)) END
FROM generate_series(1, 50000) g;
