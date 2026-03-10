-- Grant the app service principal access to the Lakebase Autoscaling database.
-- Run this as the table owner (e.g., grant.doyle@databricks.com)

-- Enable the Databricks authentication extension
CREATE EXTENSION IF NOT EXISTS databricks_auth;

-- Create a Postgres role for the app's service principal
SELECT databricks_create_role('<app-client-id>', 'service_principal');

-- Grant database and schema access
GRANT CONNECT ON DATABASE databricks_postgres TO "<app-client-id>";
GRANT CREATE, USAGE ON SCHEMA public TO "<app-client-id>";

-- All existing tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "<app-client-id>";

-- All existing sequences (needed for SERIAL/auto-increment columns)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "<app-client-id>";

-- Auto-grant on future tables created in this schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "<app-client-id>";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO "<app-client-id>";
