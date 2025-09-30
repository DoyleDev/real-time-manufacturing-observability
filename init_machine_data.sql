-- Initialize Machine Feed Stream Data
-- This script populates the machine_feed_stream table with initial states for all 29 machines
-- across 4 production lines to ensure every machine has a current status in the database.

-- Clear existing data (optional - uncomment if you want to start fresh)
-- DELETE FROM machine_feed_stream;

-- Line 1 machines (9 machines)
-- Production flow: Source Sorter → Robotic Arm → Injection Molder → Valve → Injection Molder → Robotic Arm → Painter → Robotic Arm → Sorter
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(1, 'Source_Sorter_01_01', 'operational', 'sorter', NOW()),
(2, 'Robotic_Arm_01_01', 'operational', 'robotic_arm', NOW()),
(3, 'Injection_Molder_01_01', 'operational', 'injection_molder', NOW()),
(4, 'Valve_01_01', 'operational', 'valve', NOW()),
(5, 'Injection_Molder_01_02', 'operational', 'injection_molder', NOW()),
(6, 'Robotic_Arm_01_02', 'operational', 'robotic_arm', NOW()),
(7, 'Painter_01_02', 'operational', 'painter', NOW()),
(8, 'Robotic_Arm_01_03', 'operational', 'robotic_arm', NOW()),
(9, 'Sorter_01_01', 'operational', 'sorter', NOW());

-- Line 2 machines (7 machines)
-- Production flow: Injection Molder → Valve → Injection Molder → Robotic Arm → Painter → Robotic Arm → Sorter
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(10, 'Injection_Molder_02_01', 'operational', 'injection_molder', NOW()),
(11, 'Valve_02_01', 'operational', 'valve', NOW()),
(12, 'Injection_Molder_02_02', 'operational', 'injection_molder', NOW()),
(13, 'Robotic_Arm_02_01', 'operational', 'robotic_arm', NOW()),
(14, 'Painter_02_01', 'operational', 'painter', NOW()),
(15, 'Robotic_Arm_02_02', 'operational', 'robotic_arm', NOW()),
(16, 'Sorter_02_01', 'operational', 'sorter', NOW());

-- Line 3 machines (9 machines)
-- Production flow: Sorter → Robotic Arm → Injection Molder → Valve → Injection Molder → Robotic Arm → Painter → Robotic Arm → Injection Molder
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(17, 'Sorter_03_01', 'operational', 'sorter', NOW()),
(18, 'Robotic_Arm_03_01', 'operational', 'robotic_arm', NOW()),
(19, 'Injection_Molder_03_01', 'operational', 'injection_molder', NOW()),
(20, 'Valve_03_01', 'operational', 'valve', NOW()),
(21, 'Injection_Molder_03_02', 'operational', 'injection_molder', NOW()),
(22, 'Robotic_Arm_03_02', 'operational', 'robotic_arm', NOW()),
(23, 'Painter_03_01', 'operational', 'painter', NOW()),
(24, 'Robotic_Arm_03_03', 'operational', 'robotic_arm', NOW()),
(25, 'Injection_Molder_03_03', 'operational', 'injection_molder', NOW());

-- Line 4 machines (5 machines)
-- Production flow: Injection Molder → Valve → Robotic Arm → Painter → Sorter
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(26, 'Injection_Molder_04_01', 'operational', 'injection_molder', NOW()),
(27, 'Valve_04_01', 'operational', 'valve', NOW()),
(28, 'Robotic_Arm_04_01', 'operational', 'robotic_arm', NOW()),
(29, 'Painter_04_01', 'operational', 'painter', NOW()),
(30, 'Sorter_04_01', 'operational', 'sorter', NOW());

-- Add some realistic variety for testing purposes
-- Set some machines to different statuses to test the color system
UPDATE machine_feed_stream SET status = 'warning' WHERE machine_name IN (
    'Valve_02_01',           -- Line 2 valve needs attention
    'Painter_03_01',         -- Line 3 painter has issues
    'Robotic_Arm_01_03'      -- Line 1 robotic arm showing warnings
);

UPDATE machine_feed_stream SET status = 'down' WHERE machine_name IN (
    'Injection_Molder_02_02', -- Line 2 injection molder is down
    'Sorter_04_01'           -- Line 4 sorter is offline
);

-- Verify the data was inserted correctly
SELECT
    machine_name,
    status,
    type,
    datetime,
    CASE
        WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
        WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
        WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
        WHEN machine_name LIKE '%_04_%' THEN 'Line_4'
        ELSE 'Unknown'
    END as production_line
FROM machine_feed_stream
ORDER BY machine_id;

-- Summary statistics
SELECT
    status,
    COUNT(*) as machine_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM machine_feed_stream), 1) as percentage
FROM machine_feed_stream
GROUP BY status
ORDER BY machine_count DESC;

-- Production line summary
SELECT
    CASE
        WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
        WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
        WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
        WHEN machine_name LIKE '%_04_%' THEN 'Line_4'
        ELSE 'Unknown'
    END as production_line,
    COUNT(*) as total_machines,
    SUM(CASE WHEN status = 'operational' THEN 1 ELSE 0 END) as operational,
    SUM(CASE WHEN status = 'warning' THEN 1 ELSE 0 END) as warning,
    SUM(CASE WHEN status = 'down' THEN 1 ELSE 0 END) as down
FROM machine_feed_stream
GROUP BY
    CASE
        WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
        WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
        WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
        WHEN machine_name LIKE '%_04_%' THEN 'Line_4'
        ELSE 'Unknown'
    END
ORDER BY production_line;

-- Note: This script creates a realistic manufacturing floor with:
-- - 25 machines operational (green)
-- - 3 machines with warnings (yellow)
-- - 2 machines down (red)
--
-- This gives you a good mix to test the real-time color system!