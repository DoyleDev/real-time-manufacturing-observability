-- Moving temperature readings to a dedicated sensor_readings table.
-- The existing temperature_c column on machine_events is now redundant.
ALTER TABLE machine_events DROP COLUMN temperature_c;
