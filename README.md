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

## Setup

### 1. Database Configuration

Initialize the PostgreSQL trigger for real-time notifications:

```bash
psql -f setup_notifications.sql
```

Populate initial machine data:

```bash
psql -f init_machine_data.sql
```

### 2. Environment Configuration

Create or update `.env` file:

```bash
# Databricks Lakebase Configuration
LAKEBASE_INSTANCE_NAME=your_instance_name
LAKEBASE_DATABASE_NAME=your_database_name
DATABRICKS_DATABASE_PORT=5432

# Manufacturing Simulator Settings
ENABLE_SIMULATOR=true        # Toggle simulator on/off
SIMULATOR_INTERVAL=5         # Update interval in seconds
```

### 3. Application Startup

Start the application (simulator runs automatically):

```bash
uv run uvicorn app:app --reload
```

Access the dashboard at `http://localhost:8000`

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

## Deployment

This application is designed for containerized deployment as a Databricks App. All components (HTTP server, database listener, and manufacturing simulator) run as concurrent tasks within a single FastAPI application container.

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
