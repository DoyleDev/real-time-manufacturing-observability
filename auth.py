"""
Authentication and token management for Databricks Lakebase connections.

This module handles OAuth token generation, refresh, and database instance management
for secure connections to Databricks Lakebase PostgreSQL instances.
"""

import asyncio
import logging
import os
import time
import uuid
from typing import Optional

from databricks.sdk import WorkspaceClient
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

# Global variables for OAuth token management
workspace_client: Optional[WorkspaceClient] = None
database_instance = None
postgres_password: Optional[str] = None
last_password_refresh: float = 0
token_refresh_task: Optional[asyncio.Task] = None


async def initialize_databricks_client():
    """Initialize Databricks workspace client and get database instance"""
    global workspace_client, database_instance

    try:
        workspace_client = WorkspaceClient()
        logger.info("Initialized Databricks workspace client")

        instance_name = os.getenv("LAKEBASE_INSTANCE_NAME")
        if not instance_name:
            raise RuntimeError(
                "LAKEBASE_INSTANCE_NAME environment variable is required"
            )

        database_instance = workspace_client.database.get_database_instance(
            name=instance_name
        )
        logger.info(f"Found database instance: {database_instance.name}")

    except Exception as e:
        logger.error(f"Failed to initialize Databricks client: {e}")
        raise


async def generate_fresh_token():
    """Generate a fresh OAuth token for PostgreSQL"""
    global postgres_password, last_password_refresh

    if workspace_client is None or database_instance is None:
        await initialize_databricks_client()

    try:
        logger.info("Generating fresh PostgreSQL OAuth token")

        # Generate initial credentials using the working pattern
        cred = workspace_client.database.generate_database_credential(
            request_id=str(uuid.uuid4()),
            instance_names=[database_instance.name]
        )
        postgres_password = cred.token
        last_password_refresh = time.time()
        logger.info("OAuth token generated successfully")
        return postgres_password

    except Exception as e:
        logger.error(f"Failed to generate OAuth token: {e}")
        raise


async def refresh_token_background():
    """Background task to refresh tokens every 50 minutes"""
    retry_count = 0
    max_retries = 3

    while True:
        try:
            await asyncio.sleep(50 * 60)  # Wait 50 minutes
            logger.info("Background token refresh: Generating fresh PostgreSQL OAuth token")

            await generate_fresh_token()
            retry_count = 0  # Reset retry count on success
            logger.info("Background token refresh: Token updated successfully")

        except asyncio.CancelledError:
            logger.info("Background token refresh task cancelled")
            break

        except Exception as e:
            retry_count += 1
            logger.error(f"Background token refresh failed (attempt {retry_count}/{max_retries}): {e}")

            if retry_count >= max_retries:
                logger.error("Max retries exceeded for token refresh, waiting longer before next attempt")
                retry_count = 0
                await asyncio.sleep(5 * 60)  # Wait 5 minutes before retry
            else:
                await asyncio.sleep(30)  # Wait 30 seconds before retry


async def start_token_refresh():
    """Start the background token refresh task"""
    global token_refresh_task

    # Generate initial token if not already done
    if postgres_password is None:
        await generate_fresh_token()

    # Start background refresh task
    if token_refresh_task is None or token_refresh_task.done():
        token_refresh_task = asyncio.create_task(refresh_token_background())
        logger.info("Background token refresh task started")


async def stop_token_refresh():
    """Stop the background token refresh task"""
    global token_refresh_task
    if token_refresh_task and not token_refresh_task.done():
        token_refresh_task.cancel()
        try:
            await token_refresh_task
        except asyncio.CancelledError:
            pass
        logger.info("Background token refresh task stopped")


def check_database_exists() -> bool:
    """Check if the Lakebase database instance exists"""
    try:
        workspace_client_check = WorkspaceClient()
        instance_name = os.getenv("LAKEBASE_INSTANCE_NAME")

        if not instance_name:
            logger.warning(
                "LAKEBASE_INSTANCE_NAME not set - database instance check skipped"
            )
            return False

        workspace_client_check.database.get_database_instance(name=instance_name)
        logger.info(f"Lakebase database instance '{instance_name}' exists")
        return True
    except Exception as e:
        if "not found" in str(e).lower() or "resource not found" in str(e).lower():
            logger.info(f"Lakebase database instance '{instance_name}' does not exist")
        else:
            logger.error(f"Error checking database instance existence: {e}")
        return False


def get_current_token() -> Optional[str]:
    """Get the current PostgreSQL password/token"""
    return postgres_password


def get_database_instance():
    """Get the current database instance"""
    return database_instance


def get_workspace_client() -> Optional[WorkspaceClient]:
    """Get the current workspace client"""
    return workspace_client


def get_connection_params() -> dict:
    """Get database connection parameters from the current database instance"""
    if database_instance is None:
        raise RuntimeError("Database instance not initialized")

    if workspace_client is None:
        raise RuntimeError("Workspace client not initialized")

    database_name = os.getenv("LAKEBASE_DATABASE_NAME", database_instance.name)
    username = (
        os.getenv("DATABRICKS_CLIENT_ID")
        or workspace_client.current_user.me().user_name
        or None
    )

    # Get schema from environment variable
    schema = os.getenv("DEFAULT_POSTGRES_SCHEMA", "public")

    return {
        "host": database_instance.read_write_dns,
        "port": int(os.getenv("DATABRICKS_DATABASE_PORT", "5432")),
        "user": username,
        "password": postgres_password,
        "database": database_name,
        "ssl": "require",
        "server_settings": {"search_path": schema},
    }