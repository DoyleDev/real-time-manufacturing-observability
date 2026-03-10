"""
Authentication and token management for Databricks Lakebase connections.

This module handles OAuth token generation, refresh, and endpoint management
for secure connections to Databricks Lakebase Autoscaling PostgreSQL endpoints.
"""

import asyncio
import logging
import os
import time
from typing import Optional

import psycopg
from databricks.sdk import WorkspaceClient
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

# Global variables for OAuth token management
workspace_client: Optional[WorkspaceClient] = None
postgres_password: Optional[str] = None
last_password_refresh: float = 0
token_refresh_task: Optional[asyncio.Task] = None
token_refresh_event: Optional[asyncio.Event] = None


async def initialize_databricks_client():
    """Initialize Databricks workspace client."""
    global workspace_client

    try:
        workspace_client = WorkspaceClient()
        current_user = workspace_client.current_user.me()
        logger.info(
            f"Initialized Databricks workspace client as: "
            f"{current_user.user_name} (id={current_user.id})"
        )

    except Exception as e:
        logger.error(f"Failed to initialize Databricks client: {e}")
        raise


async def generate_fresh_token():
    """Generate a fresh OAuth token for PostgreSQL via the SDK postgres service."""
    global postgres_password, last_password_refresh

    if workspace_client is None:
        await initialize_databricks_client()

    try:
        logger.info("Generating fresh PostgreSQL OAuth token via SDK")

        endpoint_name = os.environ["ENDPOINT_NAME"]
        credential = workspace_client.postgres.generate_database_credential(
            endpoint=endpoint_name
        )
        postgres_password = credential.token
        last_password_refresh = time.time()
        logger.info(
            f"OAuth token generated successfully "
            f"(expires: {credential.expire_time}, length: {len(postgres_password)})"
        )
        return postgres_password

    except Exception as e:
        logger.error(f"Failed to generate OAuth token: {e}")
        raise


async def refresh_token_background():
    """Background task to refresh tokens every 50 minutes."""
    global token_refresh_event
    retry_count = 0
    max_retries = 3

    while True:
        try:
            await asyncio.sleep(50 * 60)  # Wait 50 minutes
            logger.info("Background token refresh: Generating fresh PostgreSQL OAuth token")

            await generate_fresh_token()
            retry_count = 0
            logger.info("Background token refresh: Token updated successfully")

            if token_refresh_event:
                token_refresh_event.set()
                logger.info("Background token refresh: Signaled database reconnection needed")

        except asyncio.CancelledError:
            logger.info("Background token refresh task cancelled")
            break

        except Exception as e:
            retry_count += 1
            logger.error(f"Background token refresh failed (attempt {retry_count}/{max_retries}): {e}")

            if retry_count >= max_retries:
                logger.error("Max retries exceeded for token refresh, waiting longer before next attempt")
                retry_count = 0
                await asyncio.sleep(5 * 60)
            else:
                await asyncio.sleep(30)


async def start_token_refresh():
    """Start the background token refresh task."""
    global token_refresh_task, token_refresh_event

    if token_refresh_event is None:
        token_refresh_event = asyncio.Event()

    if postgres_password is None:
        await generate_fresh_token()

    if token_refresh_task is None or token_refresh_task.done():
        token_refresh_task = asyncio.create_task(refresh_token_background())
        logger.info("Background token refresh task started")


async def stop_token_refresh():
    """Stop the background token refresh task."""
    global token_refresh_task
    if token_refresh_task and not token_refresh_task.done():
        token_refresh_task.cancel()
        try:
            await token_refresh_task
        except asyncio.CancelledError:
            pass
        logger.info("Background token refresh task stopped")


def check_database_exists() -> bool:
    """Check if the Lakebase postgres endpoint is configured."""
    endpoint_name = os.getenv("ENDPOINT_NAME")
    pghost = os.getenv("PGHOST")

    if not endpoint_name or not pghost:
        logger.warning("ENDPOINT_NAME or PGHOST not set - database check skipped")
        return False

    try:
        w = WorkspaceClient()
        branch_path = "/".join(endpoint_name.split("/")[:4])  # projects/.../branches/...
        endpoints = list(w.postgres.list_endpoints(branch_path))
        if endpoints:
            logger.info(f"Lakebase postgres endpoint is reachable at {pghost}")
            return True
        else:
            logger.info("No endpoints found")
            return False

    except Exception as e:
        logger.error(f"Error checking postgres endpoint: {e}")
        return False


def get_current_token() -> Optional[str]:
    """Get the current PostgreSQL password/token."""
    return postgres_password


def get_workspace_client() -> Optional[WorkspaceClient]:
    """Get the current workspace client."""
    return workspace_client


def get_token_refresh_event() -> Optional[asyncio.Event]:
    """Get the token refresh event for monitoring token updates."""
    return token_refresh_event


def get_connection_params() -> dict:
    """Get database connection parameters for the Autoscaling Lakebase endpoint."""
    if workspace_client is None:
        raise RuntimeError("Workspace client not initialized")

    host = os.environ["PGHOST"]
    port = int(os.environ.get("PGPORT", "5432"))
    database = os.environ.get("PGDATABASE", "databricks_postgres")
    username = os.environ["PGUSER"]
    schema = os.getenv("DEFAULT_POSTGRES_SCHEMA", "public")

    # Generate a fresh token for this connection (matching tutorial pattern)
    endpoint_name = os.environ["ENDPOINT_NAME"]
    credential = workspace_client.postgres.generate_database_credential(
        endpoint=endpoint_name
    )
    password = credential.token

    logger.info(
        f"Connection params: host={host}, port={port}, db={database}, "
        f"user={username}, token_length={len(password)}"
    )

    return {
        "host": host,
        "port": port,
        "user": username,
        "password": password,
        "dbname": database,
        "sslmode": "require",
        "options": f"-c search_path={schema}",
    }
