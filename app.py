import asyncio
import json
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Set

import psycopg
from auth import (
    check_database_exists,
    get_connection_params,
    get_token_refresh_event,
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

# Separate connections: one for LISTEN (blocking), one for queries
listener_connection: psycopg.AsyncConnection | None = None
query_connection: psycopg.AsyncConnection | None = None


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


async def create_query_connection():
    """Create a new database connection for queries"""
    global query_connection

    try:
        conn_params = get_connection_params()
        query_connection = await psycopg.AsyncConnection.connect(
            **conn_params, autocommit=True
        )
        logger.info(
            f"Query connection established to {conn_params['dbname']} at {conn_params['host']}"
        )
        return query_connection
    except Exception as e:
        logger.error(f"Failed to create query connection: {e}")
        raise


async def ensure_query_connection():
    """Ensure we have a valid query connection, reconnect if needed"""
    global query_connection

    if query_connection is None or query_connection.closed:
        logger.info("Creating new query connection")
        await create_query_connection()

    try:
        await query_connection.execute("SELECT 1")
        return query_connection
    except Exception as e:
        logger.warning(f"Query connection test failed: {e}")
        if query_connection and not query_connection.closed:
            await query_connection.close()
        await create_query_connection()
        return query_connection


async def create_listener_connection():
    """Create a dedicated connection for LISTEN/NOTIFY"""
    global listener_connection

    try:
        conn_params = get_connection_params()
        listener_connection = await psycopg.AsyncConnection.connect(
            **conn_params, autocommit=True
        )
        logger.info("Listener connection established")
        return listener_connection
    except Exception as e:
        logger.error(f"Failed to create listener connection: {e}")
        raise


async def listen_for_changes():
    """Listen for PostgreSQL notifications and broadcast to WebSocket clients"""
    global listener_connection
    token_event = get_token_refresh_event()

    while True:
        try:
            await create_listener_connection()
            conn = listener_connection
            await conn.execute("LISTEN machine_feed_stream_changes")
            logger.info("Listening for machine_feed_stream changes...")

            async for notify in conn.notifies():
                print(f"Received notification: {notify.payload}")
                await manager.broadcast(notify.payload)

                # Check if token was refreshed
                if token_event and token_event.is_set():
                    logger.info("Token refresh detected, reconnecting database listener...")
                    token_event.clear()

                    if conn and not conn.closed:
                        await conn.close()
                    break

        except asyncio.CancelledError:
            if listener_connection and not listener_connection.closed:
                await listener_connection.close()
            raise

        except Exception as e:
            logger.error(f"Error in database listener: {e}")
            await asyncio.sleep(5)


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

            # Create the query connection
            await create_query_connection()

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

    if listener_connection and not listener_connection.closed:
        await listener_connection.close()
    if query_connection and not query_connection.closed:
        await query_connection.close()
        logger.info("Database connections closed")

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
        connection = await ensure_query_connection()

        query = """
        SELECT DISTINCT ON (machine_name)
            machine_name, status, type, datetime
        FROM machine_feed_stream
        ORDER BY machine_name, datetime DESC
        """

        cur = await connection.execute(query)
        rows = await cur.fetchall()

        # Convert to dictionary format
        status_data = {}
        for row in rows:
            status_data[row[0]] = {
                'status': row[1],
                'type': row[2],
                'datetime': row[3].isoformat() if row[3] else None
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
        connection = await ensure_query_connection()

        query = """
        SELECT id, first_name, last_name, email, department
        FROM employees
        WHERE active = true
        ORDER BY last_name, first_name
        """

        cur = await connection.execute(query)
        rows = await cur.fetchall()

        employees = []
        for row in rows:
            employees.append({
                'id': row[0],
                'first_name': row[1],
                'last_name': row[2],
                'email': row[3],
                'department': row[4],
                'full_name': f"{row[1]} {row[2]}"
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
        connection = await ensure_query_connection()

        query = """
        SELECT id, machine_id, issue_description, priority,
               reporter_name, assignee, timestamp, created_at, status
        FROM work_orders
        ORDER BY created_at DESC
        """

        cur = await connection.execute(query)
        rows = await cur.fetchall()

        work_orders = []
        status_counts = {'open': 0, 'in_progress': 0, 'completed': 0}

        for row in rows:
            work_order = {
                'id': row[0],
                'machine_id': row[1],
                'issue_description': row[2],
                'priority': row[3],
                'reporter_name': row[4],
                'assignee': row[5] or 'Unassigned',
                'status': row[8],
                'timestamp': row[6].isoformat() if row[6] else None,
                'created_at': row[7].isoformat() if row[7] else None
            }
            work_orders.append(work_order)

            status_key = row[8].replace(' ', '_').lower()
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
        connection = await ensure_query_connection()

        machine_id = work_order_data.get('machine_id')
        issue_description = work_order_data.get('issue_description')
        priority = work_order_data.get('priority', 'medium')
        reporter_name = work_order_data.get('reporter_name')
        assignee = work_order_data.get('assignee', '')

        if not machine_id:
            return {"error": "machine_id is required", "success": False}
        if not issue_description:
            return {"error": "issue_description is required", "success": False}
        if not reporter_name:
            return {"error": "reporter_name is required", "success": False}

        import uuid
        from datetime import datetime

        work_order_id = f"WO-{datetime.now().strftime('%Y%m%d')}-{str(uuid.uuid4())[:8]}"
        current_timestamp = datetime.now()

        insert_query = """
        INSERT INTO work_orders (
            id, machine_id, issue_description, priority,
            reporter_name, assignee, timestamp, created_at, status
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """

        await connection.execute(
            insert_query,
            (
                str(work_order_id),
                str(machine_id),
                str(issue_description),
                str(priority),
                str(reporter_name),
                str(assignee) if assignee else '',
                current_timestamp,
                current_timestamp,
                'open',
            ),
        )

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
