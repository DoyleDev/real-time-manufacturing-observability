-- Create a function that sends notifications when machine_feed_stream table changes
CREATE OR REPLACE FUNCTION notify_machine_feed_stream_changes()
RETURNS trigger AS $$
DECLARE
    payload json;
BEGIN
    -- Create a JSON payload with the changed data
    IF TG_OP = 'DELETE' THEN
        payload = json_build_object(
            'operation', TG_OP,
            'table', TG_TABLE_NAME,
            'timestamp', EXTRACT(epoch FROM NOW()),
            'old_data', row_to_json(OLD)
        );
    ELSE
        payload = json_build_object(
            'operation', TG_OP,
            'table', TG_TABLE_NAME,
            'timestamp', EXTRACT(epoch FROM NOW()),
            'new_data', row_to_json(NEW),
            'old_data', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
        );
    END IF;

    -- Send the notification
    PERFORM pg_notify('machine_feed_stream_changes', payload::text);

    -- Return the appropriate row
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for INSERT, UPDATE, and DELETE operations
DROP TRIGGER IF EXISTS machine_feed_stream_notify_trigger ON machine_feed_stream;

CREATE TRIGGER machine_feed_stream_notify_trigger
    AFTER INSERT OR UPDATE OR DELETE ON machine_feed_stream
    FOR EACH ROW EXECUTE FUNCTION notify_machine_feed_stream_changes();

-- Optional: Create an index on commonly queried columns if they don't exist
-- CREATE INDEX IF NOT EXISTS idx_machine_feed_timestamp ON machine_feed (created_at);
-- CREATE INDEX IF NOT EXISTS idx_machine_feed_machine_id ON machine_feed (machine_id);