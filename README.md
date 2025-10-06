# Real-time Manufacturing Line Monitor

A real-time manufacturing floor monitoring system built with FastAPI, PostgreSQL LISTEN/NOTIFY, and WebSockets. Provides live visualization of 29 machines across 4 production lines with integrated manufacturing simulator.

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
FastAPI Backend (asyncpg listener)
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
- **Databricks Integration**: OAuth authentication with automatic 50-minute token refresh
- **Production Ready**: Containerized deployment suitable for Databricks Apps

## Databricks Deployment Guide

This application is designed to be deployed as a Databricks App with integrated Lakebase PostgreSQL database and analytics dashboard.

### Prerequisites

- Databricks workspace with Lakebase enabled
- Databricks CLI installed and configured (`databricks configure`)
- Databricks bundle CLI (`databricks bundle`)
- Access to create database instances, catalogs, and apps

### Deployment Steps

#### 1. Initial Bundle Deployment

Deploy the database instance, catalog, and application infrastructure:

```bash
databricks bundle deploy
```

This creates:
- Lakebase PostgreSQL database instance (`mfg-fe-demo`)
- Database catalog (`mfg-fe-demo-catalog`)
- Databricks App (`manufacturing-line-demo`)

**Note:** The app will not fully function yet - we need to create the database schema first.

#### 2. Initialize Database Schema

Run the database initialization script to create tables and triggers:

```bash
# Connect to your Lakebase instance and run:
psql -h <instance-host> -p 5432 -U <username> -d mfg-demo-database -f app_sql_init.sql
```

Or use the Databricks SQL editor to execute `app_sql_init.sql` contents.

This script creates:
- `machine_feed_stream` table with machine status data
- `work_orders` table for maintenance tracking
- `employees` table for work order assignments
- PostgreSQL triggers for real-time LISTEN/NOTIFY
- Sample data for testing

#### 3. Create Dashboard Analytics Tables

Create the gold-layer tables for dashboard analytics:

```bash
psql -h <instance-host> -p 5432 -U <username> -d mfg-demo-database -f dashboard_sql.sql
```

This creates materialized tables optimized for dashboard performance:
- `dashboard_current_machine_status`
- `dashboard_machine_uptime_7days`
- `dashboard_problematic_machines_30days`
- `dashboard_hourly_status_patterns`
- `dashboard_work_order_status_summary`
- `dashboard_work_order_trends_30days`
- `dashboard_executive_kpis`
- `dashboard_machine_status_changes_7days`

#### 4. Configure Dashboard Data Sources

Edit `Manufacturing Line Dashboard.lvdash.json` to update table references:

1. Open the file and find all dataset queries (lines 7, 14, etc.)
2. Update the catalog and schema names to match your deployment:
   ```json
   "queryLines": [
     "SELECT * FROM `your-catalog`.your_schema.dashboard_current_machine_status"
   ]
   ```
3. Replace `mfg-fe-demo-catalog` with your actual catalog name
4. Replace `public` with your actual schema name (e.g., `manufacturing_line` as configured in `app.yaml`)

**Example:**
```json
# Before:
"SELECT * FROM `mfg-fe-demo-catalog`.public.dashboard_current_machine_status"

# After (if using manufacturing_line schema):
"SELECT * FROM `mfg-fe-demo-catalog`.manufacturing_line.dashboard_current_machine_status"
```

#### 5. Redeploy with Updated Dashboard

Deploy the updated dashboard configuration:

```bash
databricks bundle deploy
```

This deploys the dashboard with the correct table references.

#### 6. Get Dashboard Embed URL

1. Navigate to your Databricks workspace
2. Go to **Dashboards** in the left sidebar
3. Find your dashboard: `manufacturing-line-dashboard`
4. Click the **Share** button (top right)
5. Click **Embed** tab
6. Copy the embed URL (it will look like):
   ```
   https://<workspace>.cloud.databricks.com/embed/dashboardsv3/<dashboard-id>?o=<org-id>
   ```

#### 7. Configure App with Dashboard URL

Update `app.yaml` to include the dashboard embed URL:

```yaml
env:
  - name: 'DASHBOARD_EMBED_URL'
    value: 'https://<workspace>.cloud.databricks.com/embed/dashboardsv3/<dashboard-id>?o=<org-id>'
```

#### 8. Final Deployment

Deploy the app with the dashboard embed URL:

```bash
databricks bundle deploy
```

Your manufacturing observability application is now fully deployed! Access it via the Databricks Apps console.

### Environment Configuration

The app uses the following environment variables (configured in `app.yaml`):

```yaml
# Database Configuration
LAKEBASE_INSTANCE_NAME: 'fe_shared_demo'
LAKEBASE_DATABASE_NAME: 'mfg_fe_demo'
DATABRICKS_DATABASE_PORT: '5432'
DEFAULT_POSTGRES_SCHEMA: 'manufacturing_line'
DEFAULT_POSTGRES_TABLE: 'machine_feed_stream'

# Dashboard Configuration
DASHBOARD_EMBED_URL: '<your-dashboard-embed-url>'

# Simulator Settings
ENABLE_SIMULATOR: 'true'
SIMULATOR_INTERVAL: '5'  # seconds between updates

# Database Connection Pool
DB_POOL_SIZE: '5'
DB_MAX_OVERFLOW: '10'
DB_COMMAND_TIMEOUT: '30'
DB_POOL_TIMEOUT: '10'
DB_POOL_RECYCLE_INTERVAL: '3600'
```

### Local Development

For local development without Databricks deployment:

1. Create a `.env` file with your database credentials:
   ```bash
   LAKEBASE_INSTANCE_NAME=your_instance_name
   LAKEBASE_DATABASE_NAME=your_database_name
   DATABRICKS_DATABASE_PORT=5432
   DEFAULT_POSTGRES_SCHEMA=manufacturing_line
   DEFAULT_POSTGRES_TABLE=machine_feed_stream
   ENABLE_SIMULATOR=true
   SIMULATOR_INTERVAL=5
   ```

2. Start the application:
   ```bash
   uv run uvicorn app:app --reload
   ```

3. Access at `http://localhost:8000`

## Configuration Options

### Simulator Control

**Enable/Disable Simulator:**
```bash
ENABLE_SIMULATOR=true   # Default: true
```

**Adjust Update Frequency:**
```bash
SIMULATOR_INTERVAL=5    # Default: 4 seconds
```

**Run Simulator Standalone:**
```bash
python simulate_manufacturing.py
```

### Manual Status Updates

Update machine status directly via SQL:

```sql
UPDATE machine_feed_stream
SET status = 'warning', datetime = NOW()
WHERE machine_name = 'Injection_Molder_02_01';
```

Status values are case-insensitive: `operational`, `warning`, or `down`

## Project Structure

```
manufacturing_line/
├── app.py                       # FastAPI application with integrated simulator
├── auth.py                      # Databricks OAuth token management
├── machine_config.py            # Machine floor layout configuration
├── simulate_manufacturing.py    # Manufacturing line simulator
├── setup_notifications.sql      # PostgreSQL trigger setup
├── init_machine_data.sql        # Initial machine data population
├── templates/
│   └── index.html              # Main dashboard template
└── static/
    ├── css/style.css           # Machine floor styling
    ├── js/
    │   ├── websocket.js        # Real-time WebSocket client
    │   ├── machine-floor.js    # Floor visualization
    │   └── work-orders.js      # Work order management
    └── icons/                  # Machine type icons
```

## Machine Floor Layout

- **Transmission Line**: 9 machines
- **Engine Line**: 7 machines
- **Exterior Line**: 9 machines
- **Interior Line**: 5 machines

Total: 29 machines across 4 production lines

### Troubleshooting

**Permission Denied Errors:**
- Ensure the app service principal has permissions on the schema (`manufacturing_line`)
- Verify `DEFAULT_POSTGRES_SCHEMA` in `app.yaml` matches where tables were created
- Check that `search_path` is correctly set in the database connection (handled automatically in `auth.py`)

**Dashboard Not Loading:**
- Verify the `DASHBOARD_EMBED_URL` is correct in `app.yaml`
- Ensure the dashboard was deployed successfully (`databricks bundle deploy`)
- Check that the dashboard queries reference the correct catalog and schema

**Tables Not Found:**
- Confirm `app_sql_init.sql` and `dashboard_sql.sql` ran successfully
- Verify tables exist in the correct schema using `\dt` in psql
- Update dashboard `.lvdash.json` file with correct table paths

## Technical Stack

- **Backend**: FastAPI (Python async framework)
- **Database**: PostgreSQL with LISTEN/NOTIFY
- **Real-time**: WebSockets for client communication
- **Authentication**: Databricks SDK with OAuth token management
- **Frontend**: Vanilla JavaScript with Jinja2 templates
- **Database Driver**: asyncpg for async PostgreSQL operations

## Development

The application uses a modular architecture with clear separation of concerns:

- **auth.py**: Handles Databricks authentication and token refresh lifecycle
- **machine_config.py**: Defines floor layout and machine type mappings
- **simulate_manufacturing.py**: Generates realistic manufacturing activity
- **app.py**: Integrates all components with FastAPI lifespan management

All machine status is sourced from the database, ensuring consistency across page refreshes and multiple clients.
