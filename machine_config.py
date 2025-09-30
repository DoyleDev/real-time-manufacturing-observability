"""
Machine floor configuration and mapping utilities.

This module manages the manufacturing floor layout, machine types, and icon mappings.
"""

from typing import Dict, List, Optional

# Machine floor layout - imported from EXAMPLE.py structure
MACHINE_ORDER_BY_LINE = {
    "Transmission Line": [
        "Source_Sorter_01_01",
        "Robotic_Arm_01_01",
        "Injection_Molder_01_01",
        "Valve_01_01",
        "Injection_Molder_01_02",
        "Robotic_Arm_01_02",
        "Painter_01_02",
        "Robotic_Arm_01_03",
        "Sorter_01_01",
    ],
    "Engine Line": [
        "Injection_Molder_02_01",
        "Valve_02_01",
        "Injection_Molder_02_02",
        "Robotic_Arm_02_01",
        "Painter_02_01",
        "Robotic_Arm_02_02",
        "Sorter_02_01",
    ],
    "Exterior Line": [
        "Sorter_03_01",
        "Robotic_Arm_03_01",
        "Injection_Molder_03_01",
        "Valve_03_01",
        "Injection_Molder_03_02",
        "Robotic_Arm_03_02",
        "Painter_03_01",
        "Robotic_Arm_03_03",
        "Injection_Molder_03_03",
    ],
    "Interior Line": [
        "Injection_Molder_04_01",
        "Valve_04_01",
        "Robotic_Arm_04_01",
        "Painter_04_01",
        "Sorter_04_01",
    ],
}

# Machine type to icon file mapping
MACHINE_TYPE_ICONS = {
    "injection_molder": "injection_molder.png",
    "robotic_arm": "robotic_arm.png",
    "sorter": "sorter.png",
    "painter": "painter.png",
    "valve": "valve_icon.png",
}

# Default machine status - updated to match operational state
DEFAULT_MACHINE_STATUS = "operational"


def extract_machine_type(machine_name: str) -> str:
    """
    Extract machine type from machine name.

    Args:
        machine_name: Machine name like "Source_Sorter_01_01" or "Injection_Molder_02_01"

    Returns:
        Machine type string for icon mapping
    """
    # Convert to lowercase and handle different naming patterns
    machine_lower = machine_name.lower()

    if "sorter" in machine_lower:
        return "sorter"
    elif "robotic_arm" in machine_lower or "robotic" in machine_lower:
        return "robotic_arm"
    elif "injection_molder" in machine_lower or "molder" in machine_lower:
        return "injection_molder"
    elif "painter" in machine_lower:
        return "painter"
    elif "valve" in machine_lower:
        return "valve"
    else:
        # Default fallback
        return "sorter"


def get_machine_icon(machine_name: str) -> str:
    """
    Get the icon filename for a given machine.

    Args:
        machine_name: Machine name like "Source_Sorter_01_01"

    Returns:
        Icon filename like "sorter.png"
    """
    machine_type = extract_machine_type(machine_name)
    return MACHINE_TYPE_ICONS.get(machine_type, MACHINE_TYPE_ICONS["sorter"])


def get_machine_floor_layout() -> Dict:
    """
    Get the complete machine floor layout with enriched machine data.

    Returns:
        Dictionary containing lines, machines with types, icons, and positions
    """
    floor_layout = {
        "lines": {},
        "total_machines": 0,
        "machine_types": list(MACHINE_TYPE_ICONS.keys()),
    }

    for line_name, machines in MACHINE_ORDER_BY_LINE.items():
        line_data = {"name": line_name, "machines": [], "machine_count": len(machines)}

        for position, machine_name in enumerate(machines):
            machine_data = {
                "name": machine_name,
                "type": extract_machine_type(machine_name),
                "icon": get_machine_icon(machine_name),
                "position": position,
                "line": line_name,
            }
            line_data["machines"].append(machine_data)

        floor_layout["lines"][line_name] = line_data
        floor_layout["total_machines"] += len(machines)

    return floor_layout


def get_all_machines() -> List[str]:
    """
    Get a flat list of all machine names across all lines.

    Returns:
        List of all machine names
    """
    all_machines = []
    for machines in MACHINE_ORDER_BY_LINE.values():
        all_machines.extend(machines)
    return all_machines


def find_machine_location(machine_name: str) -> Optional[Dict]:
    """
    Find which line and position a machine is located at.

    Args:
        machine_name: Machine name to locate

    Returns:
        Dictionary with line and position info, or None if not found
    """
    for line_name, machines in MACHINE_ORDER_BY_LINE.items():
        if machine_name in machines:
            return {
                "line": line_name,
                "position": machines.index(machine_name),
                "total_in_line": len(machines),
            }
    return None
