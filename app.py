import asyncio
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Set

import asyncpg
from auth import (
    check_database_exists,
    get_connection_params,
    initialize_databricks_client,
    start_token_refresh,
    stop_token_refresh,
)
from machine_config import get_machine_floor_layout
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

logger = logging.getLogger(__name__)


templates = Jinja2Templates(directory="templates")
db_connection: asyncpg.Connection | None = None


class ConnectionManager:
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)

    async def broadcast(self, message: str):
        disconnected = set()
        for connection in self.active_connections.copy():
            try:
                await connection.send_text(message)
            except Exception:
                disconnected.add(connection)

        # Remove disconnected connections
        self.active_connections -= disconnected


manager = ConnectionManager()


async def database_health() -> bool:
    """Check database connection health"""
    global db_connection

    if db_connection is None or db_connection.is_closed():
        logger.error("Database connection is not available")
        return False

    try:
        await db_connection.execute("SELECT 1")
        logger.info("Database connection is healthy")
        return True
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        return False


async def create_db_connection():
    """Create a new database connection with current OAuth token"""
    global db_connection

    try:
        conn_params = get_connection_params()

        db_connection = await asyncpg.connect(**conn_params)
        logger.info(
            f"Database connection established to {conn_params['database']} at {conn_params['host']}"
        )
        return db_connection

    except Exception as e:
        logger.error(f"Failed to create database connection: {e}")
        raise


async def ensure_db_connection():
    """Ensure we have a valid database connection, reconnect if needed"""
    global db_connection

    if db_connection is None or db_connection.is_closed():
        logger.info("Creating new database connection")
        await create_db_connection()

    try:
        await db_connection.execute("SELECT 1")
        return db_connection

    except Exception as e:
        logger.warning(f"Database connection test failed: {e}")
        logger.info("Attempting to reconnect")

        if db_connection and not db_connection.is_closed():
            await db_connection.close()

        await create_db_connection()
        return db_connection


async def listen_for_changes():
    """Listen for PostgreSQL notifications and broadcast to WebSocket clients"""

    while True:
        try:
            conn = await ensure_db_connection()
            await conn.add_listener("machine_feed_stream_changes", notification_handler)
            logger.info("Listening for machine_feed_stream changes...")

            while True:
                try:
                    await asyncio.sleep(1)
                    if time.time() % 30 == 0:
                        await conn.execute("SELECT 1")

                except asyncio.CancelledError:
                    raise

                except Exception as e:
                    logger.warning(f"Database connection lost: {e}")
                    break

        except asyncio.CancelledError:
            if db_connection and not db_connection.is_closed():
                await db_connection.close()
            raise

        except Exception as e:
            logger.error(f"Error in database listener: {e}")
            await asyncio.sleep(5)


async def notification_handler(_connection, _pid, _channel, payload):
    """Handle database notifications and broadcast to WebSocket clients"""
    print(f"Received notification: {payload}")
    await manager.broadcast(payload)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

    logger.info("Application startup initiated")

    database_exists = check_database_exists()
    listener_task = None
    simulator_task = None

    if database_exists:
        try:
            await initialize_databricks_client()
            await start_token_refresh()
            logger.info("OAuth token management initialized successfully")

            listener_task = asyncio.create_task(listen_for_changes())
            logger.info("Database listener started")

            # Start manufacturing simulator if enabled
            enable_simulator = os.getenv("ENABLE_SIMULATOR", "true").lower() == "true"
            if enable_simulator:
                from simulate_manufacturing import simulate_manufacturing
                simulator_task = asyncio.create_task(simulate_manufacturing(use_colors=False))
                logger.info("Manufacturing simulator started as background task")
            else:
                logger.info("Manufacturing simulator disabled (ENABLE_SIMULATOR=false)")

        except Exception as e:
            logger.error(f"Failed to initialize database functionality: {e}")
            logger.info("Application will start without real-time updates")
    else:
        logger.info(
            "No Lakebase database instance found - starting with limited functionality"
        )

    logger.info("Application startup complete")

    yield

    logger.info("Shutting down application")

    if simulator_task:
        logger.info("Stopping manufacturing simulator")
        simulator_task.cancel()
        try:
            await simulator_task
        except asyncio.CancelledError:
            pass

    if listener_task:
        listener_task.cancel()
        try:
            await listener_task
        except asyncio.CancelledError:
            pass

    await stop_token_refresh()

    if db_connection and not db_connection.is_closed():
        await db_connection.close()
        logger.info("Database connection closed")

    logger.info("Application shutdown complete")


app = FastAPI(lifespan=lifespan)
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/", response_class=HTMLResponse)
async def get(request: Request):
    dashboard_url = os.getenv("DASHBOARD_EMBED_URL")
    return templates.TemplateResponse("index.html", {"request": request, "dashboard_url": dashboard_url})


@app.get("/api/machines")
async def get_machines():
    """Get machine floor layout and configuration"""
    return get_machine_floor_layout()


@app.get("/api/machines/current-status")
async def get_current_machine_status():
    """Get current status of all machines from database"""
    try:
        # Ensure we have a database connection
        connection = await ensure_db_connection()

        # Query to get the latest status for each machine
        query = """
        SELECT DISTINCT ON (machine_name)
            machine_name, status, type, datetime
        FROM machine_feed_stream
        ORDER BY machine_name, datetime DESC
        """

        rows = await connection.fetch(query)

        # Convert to dictionary format
        status_data = {}
        for row in rows:
            status_data[row['machine_name']] = {
                'status': row['status'],
                'type': row['type'],
                'datetime': row['datetime'].isoformat() if row['datetime'] else None
            }

        logger.info(f"Retrieved current status for {len(status_data)} machines")
        return {"machine_statuses": status_data}

    except Exception as e:
        logger.error(f"Failed to get current machine status: {e}")
        return {"error": "Failed to retrieve machine status", "machine_statuses": {}}


@app.get("/api/employees")
async def get_employees():
    """Get list of active employees for assignee dropdown"""
    try:
        # Ensure we have a database connection
        connection = await ensure_db_connection()

        # Query to get active employees ordered by last name, first name
        query = """
        SELECT id, first_name, last_name, email, department
        FROM employees
        WHERE active = true
        ORDER BY last_name, first_name
        """

        rows = await connection.fetch(query)

        # Convert to list of employee objects
        employees = []
        for row in rows:
            employees.append({
                'id': row['id'],
                'first_name': row['first_name'],
                'last_name': row['last_name'],
                'email': row['email'],
                'department': row['department'],
                'full_name': f"{row['first_name']} {row['last_name']}"
            })

        logger.info(f"Retrieved {len(employees)} active employees")
        return {"employees": employees}

    except Exception as e:
        logger.error(f"Failed to get employees: {e}")
        return {"error": "Failed to retrieve employees", "employees": []}


@app.get("/api/work-orders")
async def get_work_orders():
    """Get all work orders from database"""
    try:
        # Ensure we have a database connection
        connection = await ensure_db_connection()

        # Query to get all work orders ordered by created_at DESC
        query = """
        SELECT id, machine_id, issue_description, priority,
               reporter_name, assignee, timestamp, created_at, status
        FROM work_orders
        ORDER BY created_at DESC
        """

        rows = await connection.fetch(query)

        # Convert to list of work order objects
        work_orders = []
        status_counts = {'open': 0, 'in_progress': 0, 'completed': 0}

        for row in rows:
            work_order = {
                'id': row['id'],
                'machine_id': row['machine_id'],
                'issue_description': row['issue_description'],
                'priority': row['priority'],
                'reporter_name': row['reporter_name'],
                'assignee': row['assignee'] or 'Unassigned',
                'status': row['status'],
                'timestamp': row['timestamp'].isoformat() if row['timestamp'] else None,
                'created_at': row['created_at'].isoformat() if row['created_at'] else None
            }
            work_orders.append(work_order)

            # Count statuses for statistics
            status_key = row['status'].replace(' ', '_').lower()
            if status_key in status_counts:
                status_counts[status_key] += 1

        logger.info(f"Retrieved {len(work_orders)} work orders")
        return {
            "work_orders": work_orders,
            "status_counts": status_counts,
            "total": len(work_orders)
        }

    except Exception as e:
        logger.error(f"Failed to get work orders: {e}")
        return {"error": "Failed to retrieve work orders", "work_orders": [], "status_counts": {'open': 0, 'in_progress': 0, 'completed': 0}}


@app.post("/api/work-orders")
async def create_work_order(work_order_data: dict):
    """Create a new work order for a machine"""
    try:
        # Ensure we have a database connection
        connection = await ensure_db_connection()

        # Extract required fields
        machine_id = work_order_data.get('machine_id')
        issue_description = work_order_data.get('issue_description')
        priority = work_order_data.get('priority', 'medium')
        reporter_name = work_order_data.get('reporter_name')
        assignee = work_order_data.get('assignee', '')

        logger.info(f"🔧 Work order data received: machine_id='{machine_id}', priority='{priority}', reporter_name='{reporter_name}', assignee='{assignee}'")

        # Validation
        if not machine_id:
            return {"error": "machine_id is required", "success": False}
        if not issue_description:
            return {"error": "issue_description is required", "success": False}
        if not reporter_name:
            return {"error": "reporter_name is required", "success": False}

        # Generate work order ID
        import uuid
        from datetime import datetime

        work_order_id = f"WO-{datetime.now().strftime('%Y%m%d')}-{str(uuid.uuid4())[:8]}"
        current_timestamp = datetime.now()

        # Insert work order into database
        insert_query = """
        INSERT INTO work_orders (
            id, machine_id, issue_description, priority,
            reporter_name, assignee, timestamp, created_at, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        """

        # Ensure data types match schema expectations
        try:
            await connection.execute(
                insert_query,
                str(work_order_id),           # varchar(50)
                str(machine_id),              # varchar(100)
                str(issue_description),       # string
                str(priority),                # varchar(20)
                str(reporter_name),           # varchar(100)
                str(assignee) if assignee else '',  # varchar(100), handle None
                current_timestamp,            # timestamp
                current_timestamp,            # timestamp
                'open'                        # varchar(20) - using lowercase for consistency
            )
        except Exception as db_error:
            logger.error(f"Database insertion failed with detailed error: {db_error}")
            logger.error(f"Data being inserted: id='{work_order_id}', machine_id='{machine_id}', priority='{priority}', status='open'")
            raise

        logger.info(f"Created work order {work_order_id} for machine {machine_id}")

        return {
            "success": True,
            "work_order_id": work_order_id,
            "message": f"Work order {work_order_id} created successfully"
        }

    except Exception as e:
        logger.error(f"Failed to create work order: {e}")
        return {"error": f"Failed to create work order: {str(e)}", "success": False}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
