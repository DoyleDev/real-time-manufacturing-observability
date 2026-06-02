-- Compliance asked us to make operator_id required so we always know
-- who was on the line at the time of every event.
ALTER TABLE machine_events
    ALTER COLUMN operator_id SET NOT NULL;
