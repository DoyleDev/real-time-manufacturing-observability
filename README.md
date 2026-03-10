# Real-time Manufacturing Line Monitor

A real-time manufacturing floor monitoring system built with FastAPI, PostgreSQL LISTEN/NOTIFY, and WebSockets. Provides live visualization of 30 machines across 4 production lines with integrated manufacturing simulator.

## Overview

This application monitors machine status on a manufacturing floor in real-time. Machine status changes in the database are instantly reflected in the web UI through PostgreSQL notifications and WebSocket broadcasting. An integrated simulator generates realistic manufacturing activity for demonstration and testing.

## Architecture

```
Manufacturing Simulator (background task)
    ↓
Database (machine_feed_stream table)
    ↓
PostgreSQL Trigger → LISTEN/NOTIFY
    ↓
FastAPI Backend (psycopg3 listener)
    ↓
WebSocket Broadcast
    ↓
Browser UI (real-time updates)
```

## Key Features

- **Real-time Visualization**: Machine status changes appear instantly with color coding (green/yellow/red)
- **Manufacturing Simulator**: Background task generates realistic status updates with weighted distribution (60% operational, 30% warning, 10% down)
- **Database-Driven**: All machine status loaded exclusively from PostgreSQL database
- **Multi-Client Support**: WebSocket broadcasting to multiple connected browsers
- **Databricks Integration**: OAuth authentication via Databricks SDK with automatic 50-minute token refresh
- **Production Ready**: Containerized deployment suitable for Databricks Apps

## Databricks Deployment Guide

This application is designed to be deployed as a Databricks App with a Lakebase Autoscaling PostgreSQL database and optional analytics dashboard.

### Prerequisites

- Databricks workspace with Lakebase Autoscaling enabled
- Databricks CLI **v0.285.0+** installed and configured (`databricks configure`)
- `psql` client installed (`brew install postgresql@16` on macOS)
- Access to create postgres projects and apps

### Deployment Steps

#### 1. Initial Bundle Deployment

Deploy the Lakebase Autoscaling postgres project and application infrastructure:

```bash
databricks bundle deploy
```

This creates:
- Lakebase Autoscaling postgres project (`machine-floor-project`) with a `production` branch
- A `primary` read-write endpoint (auto-created with the branch)
- Databricks App (`manufacturing-line-demo`) with its own service principal

**Note:** The app will not fully function yet — we need to set up auth, schema, and grants first.

#### 2. Set Connection Variables

These variables are reused throughout the setup. OAuth tokens expire after ~1 hour, so regenerate `TOKEN` if a command fails with auth errors.

```bash
# Get the endpoint host
HOST=$(databricks postgres list-endpoints \
  projects/machine-floor-project/branches/production \
  -o json | jq -r '.[0].status.hosts.host')

# Generate an OAuth token
TOKEN=$(databricks postgres generate-database-credential \
  projects/machine-floor-project/branches/production/endpoints/primary \
  -o json | jq -r '.token')

# Get your username
EMAIL=$(databricks current-user me -o json | jq -r '.userName')
```

#### 3. Register the App Service Principal for OAuth

The Databricks App runs as a service principal (SP). The SP must be registered at the **Lakebase API level** with `LAKEBASE_OAUTH_V1` authentication — this is separate from SQL-level grants. Without this, the SP cannot authenticate to PostgreSQL even with a valid token.

Find the app's service principal client ID:

```bash
# List apps to find the SP client ID
databricks apps get manufacturing-line-demo -o json | jq '.service_principal'
```

Register the SP role via the Databricks SDK:

```python
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.postgres import Role, RoleRoleSpec, RoleAuthMethod, RoleIdentityType

w = WorkspaceClient()

SP_CLIENT_ID = "<your-app-service-principal-client-id>"

w.postgres.create_role(
    parent="projects/machine-floor-project/branches/production",
    role=Role(
        spec=RoleRoleSpec(
            auth_method=RoleAuthMethod.LAKEBASE_OAUTH_V1,
            identity_type=RoleIdentityType.SERVICE_PRINCIPAL,
            postgres_role=SP_CLIENT_ID,
        )
    ),
)
```

> **Important:** Do NOT use `CREATE ROLE` or `databricks_create_role()` in SQL for service principals — these create roles with `NO_LOGIN` auth, which cannot authenticate with OAuth tokens. You **must** use the Databricks SDK/API `postgres.create_role()` with `LAKEBASE_OAUTH_V1`.

#### 4. Initialize Database Schema

Install the `databricks_auth` extension and create tables:

```bash
# Install the auth extension (required in each database)
PGPASSWORD=$TOKEN psql "host=$HOST port=5432 dbname=databricks_postgres user=$EMAIL sslmode=require" \
  -c "CREATE EXTENSION IF NOT EXISTS databricks_auth;"

# Run the init script
PGPASSWORD=$TOKEN psql "host=$HOST port=5432 dbname=databricks_postgres user=$EMAIL sslmode=require" \
  -f app_sql_init.sql
```

> **Note:** `databricks psql` is not supported with Autoscaling Lakebase. Use direct `psql` with an OAuth token as shown above.

This script creates:
- `machine_feed_stream` table with machine status data
- `work_orders` table for maintenance tracking
- `employees` table for work order assignments
- PostgreSQL triggers for real-time LISTEN/NOTIFY
- Sample data for testing

#### 5. Grant Service Principal Access

Grant the SP permissions on all tables in the target database:

```bash
SP_CLIENT_ID="<your-app-service-principal-client-id>"

PGPASSWORD=$TOKEN psql "host=$HOST port=5432 dbname=databricks_postgres user=$EMAIL sslmode=require" -c "
GRANT CONNECT ON DATABASE databricks_postgres TO \"$SP_CLIENT_ID\";
GRANT CREATE, USAGE ON SCHEMA public TO \"$SP_CLIENT_ID\";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"$SP_CLIENT_ID\";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"$SP_CLIENT_ID\";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"$SP_CLIENT_ID\";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"$SP_CLIENT_ID\";
"
```

#### 6. Configure app.yaml

Update `app.yaml` with your endpoint host, SP client ID, and endpoint name:

```yaml
command: ["uvicorn", "app:app"]

env:
  - name: 'PGHOST'
    value: '<your-endpoint-host>'           # from step 2
  - name: 'PGDATABASE'
    value: 'databricks_postgres'
  - name: 'PGUSER'
    value: '<your-sp-client-id>'            # app service principal UUID
  - name: 'PGPORT'
    value: '5432'
  - name: 'PGSSLMODE'
    value: 'require'
  - name: 'ENDPOINT_NAME'
    value: 'projects/machine-floor-project/branches/production/endpoints/primary'

  - name: 'DEFAULT_POSTGRES_SCHEMA'
    value: 'public'
  - name: 'DEFAULT_POSTGRES_TABLE'
    value: 'machine_feed_stream'

  - name: 'DASHBOARD_EMBED_URL'
    value: '<your-embed-url-here>'

  - name: 'ENABLE_SIMULATOR'
    value: 'true'
  - name: 'SIMULATOR_INTERVAL'
    value: '5'
```

#### 7. Deploy the App

```bash
databricks bundle deploy
```

Access it via the Databricks Apps console. You should see:
- All 30 machines rendered on the floor layout
- Real-time status updates via WebSocket (green/yellow/red borders)
- Status changes flowing in the "Real-time Data Stream" panel

#### 8. (Optional) Create Dashboard Analytics Tables

Create gold-layer tables for an embedded dashboard:

```bash
PGPASSWORD=$TOKEN psql "host=$HOST port=5432 dbname=databricks_postgres user=$EMAIL sslmode=require" \
  -f dashboard_sql.sql
```

Then configure `DASHBOARD_EMBED_URL` in `app.yaml` and redeploy.

### Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `PGHOST` | Lakebase endpoint hostname | `ep-xxx.database.us-east-2.cloud.databricks.com` |
| `PGDATABASE` | Database name | `databricks_postgres` |
| `PGUSER` | App service principal client ID | `<app-client-id>` |
| `PGPORT` | PostgreSQL port | `5432` |
| `PGSSLMODE` | SSL mode | `require` |
| `ENDPOINT_NAME` | Full Lakebase endpoint path | `projects/.../branches/.../endpoints/primary` |
| `DEFAULT_POSTGRES_SCHEMA` | Schema for tables | `public` |
| `DEFAULT_POSTGRES_TABLE` | Main status table | `machine_feed_stream` |
| `DASHBOARD_EMBED_URL` | Databricks dashboard embed URL | `https://...` |
| `ENABLE_SIMULATOR` | Enable background simulator | `true` |
| `SIMULATOR_INTERVAL` | Seconds between simulator updates | `5` |

### Local Development

For local development with a Databricks CLI profile configured:

1. Create a `.env` file:
   ```bash
   PGHOST=<your-endpoint-host>
   PGDATABASE=databricks_postgres
   PGUSER=<your-email>
   PGPORT=5432
   PGSSLMODE=require
   ENDPOINT_NAME=projects/machine-floor-project/branches/production/endpoints/primary
   DEFAULT_POSTGRES_SCHEMA=public
   DEFAULT_POSTGRES_TABLE=machine_feed_stream
   ENABLE_SIMULATOR=true
   SIMULATOR_INTERVAL=5
   ```

2. Start the application:
   ```bash
   uv run uvicorn app:app --reload
   ```

3. Access at `http://localhost:8000`

> **Note:** Local development uses your personal Databricks credentials (via `WorkspaceClient()`), so set `PGUSER` to your email address, not the SP client ID.

## Project Structure

```
real-time-manufacturing-observability/
├── app.py                       # FastAPI application with WebSocket + LISTEN/NOTIFY
├── auth.py                      # Databricks SDK OAuth token management
├── machine_config.py            # Machine floor layout configuration
├── simulate_manufacturing.py    # Manufacturing line simulator
├── app.yaml                     # Databricks App configuration
├── databricks.yml               # DAB bundle definition (project, branches, app)
├── app_sql_init.sql             # Database schema init (tables, triggers, sample data)
├── dashboard_sql.sql            # Dashboard analytics tables
├── grant_sp_access.sql          # Reference SQL for SP grants
├── templates/
│   └── index.html               # Main dashboard template
└── static/
    ├── css/style.css            # Machine floor styling
    ├── js/
    │   ├── websocket.js         # Real-time WebSocket client
    │   ├── machine-floor.js     # Floor visualization
    │   └── work-orders.js       # Work order management
    └── icons/                   # Machine type icons
```

## Machine Floor Layout

- **Transmission Line**: 9 machines
- **Engine Line**: 7 machines
- **Exterior Line**: 9 machines
- **Interior Line**: 5 machines

Total: 30 machines across 4 production lines

## Troubleshooting

**Password authentication failed:**
- The SP role must be created via the Databricks SDK `postgres.create_role()` with `auth_method=LAKEBASE_OAUTH_V1` — not via SQL
- Verify the role: `w.postgres.list_roles("projects/.../branches/...")` and check `auth_method` is `LAKEBASE_OAUTH_V1`, not `NO_LOGIN`
- The `databricks_auth` extension must be installed in the **target database** (`databricks_postgres`), not just `postgres`
- OAuth tokens expire after ~1 hour — the app refreshes automatically, but CLI tokens need manual regeneration

**Permission denied for table:**
- Run the GRANT statements from step 5 against the correct branch endpoint
- Each branch has its own data and grants — grants on `main` don't apply to `production`
- After creating new tables, re-run `GRANT ... ON ALL TABLES` since default privileges only apply to future tables

**Table does not exist:**
- Verify you ran `app_sql_init.sql` against the same branch the app connects to
- Check with: `\dt public.*` in psql connected to the correct endpoint
- Branches in Lakebase Autoscaling have separate data — `production` and `main` are independent

**Simulator crashes silently:**
- Check app logs for `Manufacturing simulator crashed:` error messages
- Common causes: missing tables, insufficient permissions, connection timeout

**Dashboard not loading:**
- Verify the `DASHBOARD_EMBED_URL` is correct in `app.yaml`
- Ensure the dashboard queries reference the correct catalog and schema

## Technical Stack

- **Backend**: FastAPI (Python async framework)
- **Database**: Lakebase Autoscaling PostgreSQL with LISTEN/NOTIFY
- **Real-time**: WebSockets for client communication
- **Authentication**: Databricks SDK (`databricks-sdk>=0.81.0`) with OAuth token management
- **Frontend**: Vanilla JavaScript with Jinja2 templates
- **Database Driver**: psycopg3 (async) for PostgreSQL operations
- **Deployment**: Databricks Asset Bundles (DABs)
