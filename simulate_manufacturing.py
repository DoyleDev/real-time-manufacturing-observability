#!/usr/bin/env python3
"""
Manufacturing Line Simulator - Realistic status updates to simulate a real production floor.

This script updates machine statuses in the database with realistic weighted probabilities:
- 60% operational (most machines running normally)
- 30% warning (some machines showing issues)
- 10% down (occasional critical failures)

Updates occur every 4 seconds to simulate real-time manufacturing conditions.
Can be run standalone or as a background task in FastAPI.
"""

import asyncio
import logging
import os
import random
from datetime import datetime

import psycopg
from auth import (
    generate_fresh_token,
    get_connection_params,
    initialize_databricks_client,
)
from machine_config import find_machine_location, get_all_machines

logger = logging.getLogger(__name__)


# ANSI color codes for terminal output
class Colors:
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    RESET = "\033[0m"
    BOLD = "\033[1m"


async def simulate_manufacturing(use_colors: bool = True):
    """
    Simulate a realistic manufacturing line with weighted status updates.

    Args:
        use_colors: Whether to use ANSI color codes in output (default True for standalone, False for background)
    """

    # Get update interval from environment or default to 4 seconds
    update_interval = int(os.getenv("SIMULATOR_INTERVAL", "4"))

    if use_colors:
        print(f"{Colors.BOLD}{Colors.CYAN}{'=' * 70}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}Manufacturing Line Simulator{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{'=' * 70}{Colors.RESET}\n")

    # Initialize auth module
    logger.info("Initializing Databricks authentication for simulator")
    if use_colors:
        print(f"{Colors.BLUE}🔐 Initializing Databricks authentication...{Colors.RESET}")

    await initialize_databricks_client()
    await generate_fresh_token()

    # Connect to database
    logger.info("Connecting to database for simulator")
    if use_colors:
        print(f"{Colors.BLUE}🔗 Connecting to database...{Colors.RESET}")

    conn_params = get_connection_params()
    conn = await psycopg.AsyncConnection.connect(**conn_params, autocommit=True)

    logger.info("Manufacturing simulator connected to database")
    if use_colors:
        print(f"{Colors.GREEN}✅ Connected to database{Colors.RESET}\n")

    # Get all machine names
    all_machines = get_all_machines()

    # Status distribution with weights (60% operational, 30% warning, 10% down)
    statuses = ["operational"] * 60 + ["warning"] * 30 + ["down"] * 10

    logger.info(
        f"Manufacturing simulator started: {len(all_machines)} machines, "
        f"interval={update_interval}s, distribution=60/30/10"
    )

    if use_colors:
        print(f"{Colors.BOLD}Simulation Configuration:{Colors.RESET}")
        print(f"  Total machines: {len(all_machines)}")
        print("  Status distribution: 60% operational, 30% warning, 10% down")
        print(f"  Update interval: {update_interval} seconds")
        print("  Press Ctrl+C to stop\n")
        print(f"{Colors.BOLD}{Colors.CYAN}{'=' * 70}{Colors.RESET}\n")

    update_count = 0

    try:
        while True:
            # Select random machine and status
            machine_name = random.choice(all_machines)
            status = random.choice(statuses)

            # Get machine location for display
            location = find_machine_location(machine_name)
            line_name = location["line"] if location else "Unknown"

            # Update the database - this triggers PostgreSQL LISTEN/NOTIFY
            await conn.execute(
                """
                UPDATE machine_feed_stream
                SET status = %s, datetime = %s
                WHERE machine_name = %s
                """,
                (status, datetime.now(), machine_name),
            )

            update_count += 1

            # Log the update
            logger.debug(
                f"Simulator update #{update_count}: {line_name} | {machine_name} → {status.upper()}"
            )

            # Print formatted update if using colors (standalone mode)
            if use_colors:
                # Color-coded output based on status
                if status == "operational":
                    status_color = Colors.GREEN
                    status_symbol = "✓"
                elif status == "warning":
                    status_color = Colors.YELLOW
                    status_symbol = "⚠"
                else:  # down
                    status_color = Colors.RED
                    status_symbol = "✗"

                timestamp = datetime.now().strftime("%H:%M:%S")
                print(
                    f"[{Colors.CYAN}{timestamp}{Colors.RESET}] "
                    f"#{update_count:04d} | "
                    f"{Colors.BLUE}{line_name:20s}{Colors.RESET} | "
                    f"{machine_name:25s} → "
                    f"{status_color}{status_symbol} {status.upper():12s}{Colors.RESET}"
                )

            # Wait configured interval before next update
            await asyncio.sleep(update_interval)

    except asyncio.CancelledError:
        logger.info(f"Manufacturing simulator cancelled. Total updates: {update_count}")
        if use_colors:
            print(f"\n\n{Colors.YELLOW}🛑 Stopping simulation...{Colors.RESET}")
            print(f"{Colors.GREEN}Total updates performed: {update_count}{Colors.RESET}")
        raise
    except KeyboardInterrupt:
        logger.info(f"Manufacturing simulator stopped by user. Total updates: {update_count}")
        if use_colors:
            print(f"\n\n{Colors.YELLOW}🛑 Stopping simulation...{Colors.RESET}")
            print(f"{Colors.GREEN}Total updates performed: {update_count}{Colors.RESET}")
    except Exception as e:
        logger.error(f"Manufacturing simulator crashed: {e}", exc_info=True)
    finally:
        await conn.close()
        logger.info("Manufacturing simulator database connection closed")
        if use_colors:
            print(f"{Colors.BLUE}🔌 Database connection closed{Colors.RESET}\n")


if __name__ == "__main__":
    # Run standalone with colors and logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    asyncio.run(simulate_manufacturing(use_colors=True))
