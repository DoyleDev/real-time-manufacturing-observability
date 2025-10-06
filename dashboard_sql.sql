-- =====================================================================================
-- DATABRICKS DASHBOARD TABLES
-- Manufacturing Floor Monitoring System - Materialized Tables for Dashboard Reporting
-- =====================================================================================
-- 
-- This file contains CREATE TABLE statements for Databricks dashboard tables.
-- These tables will be created and refreshed regularly to provide fast dashboard performance.
--
-- Source Tables:
-- - public.machine_feed_stream: Historical machine status data with timestamps
-- - public.work_orders: Work order tracking with status, priority, and assignments
-- - public.employees: Employee information for assignment and performance tracking
--
-- Usage: Run these statements in Databricks to create dashboard tables
-- Recommended: Set up automated refresh jobs for these tables
-- Date: 2025-07-22
-- =====================================================================================

-- =====================================================================================
-- 1. MACHINE PERFORMANCE & DOWNTIME ANALYTICS TABLES
-- =====================================================================================

-- 1.1 Current Machine Status Summary Table
-- Real-time overview of all machines by status and line
DROP TABLE IF EXISTS dashboard_current_machine_status;

CREATE TABLE dashboard_current_machine_status AS
SELECT 
    CASE 
        WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
        WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
        WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
        ELSE 'Unknown'
    END AS production_line,
    type AS equipment_type,
    status,
    COUNT(*) as machine_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage,
    CURRENT_TIMESTAMP as last_updated
FROM (
    SELECT DISTINCT 
        machine_name,
        type,
        FIRST_VALUE(status) OVER (PARTITION BY machine_name ORDER BY datetime DESC) as status
    FROM public.machine_feed_stream
) current_status
GROUP BY production_line, equipment_type, status;

-- 1.2 Machine Uptime Analysis (Last 7 Days) Table
-- Calculate uptime percentage for each machine over the past week
DROP TABLE IF EXISTS dashboard_machine_uptime_7days;

CREATE TABLE dashboard_machine_uptime_7days AS
WITH machine_status_intervals AS (
    SELECT 
        machine_name,
        type,
        status,
        datetime as status_start,
        LEAD(datetime) OVER (PARTITION BY machine_name ORDER BY datetime) as status_end,
        CASE 
            WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
            WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
            WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
            ELSE 'Unknown'
        END AS production_line
    FROM public.machine_feed_stream
    WHERE datetime >= CURRENT_DATE - INTERVAL '7' DAY
),
uptime_calc AS (
    SELECT 
        production_line,
        machine_name,
        type,
        SUM(CASE WHEN status = 'operational' 
            THEN COALESCE(EXTRACT(EPOCH FROM status_end) - EXTRACT(EPOCH FROM status_start), 
                         EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM status_start))
            ELSE 0 END) as operational_seconds,
        SUM(COALESCE(EXTRACT(EPOCH FROM status_end) - EXTRACT(EPOCH FROM status_start), 
                    EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM status_start))) as total_seconds
    FROM machine_status_intervals
    WHERE status_start IS NOT NULL
    GROUP BY production_line, machine_name, type
)
SELECT 
    production_line,
    machine_name,
    type,
    ROUND((operational_seconds / NULLIF(total_seconds, 0)) * 100, 2) as uptime_percentage,
    ROUND(operational_seconds / 3600, 2) as operational_hours,
    ROUND((total_seconds - operational_seconds) / 3600, 2) as downtime_hours,
    CURRENT_TIMESTAMP as last_updated
FROM uptime_calc;

-- 1.3 Top Problematic Machines (Last 30 Days) Table
-- Machines with most downtime incidents in the last 30 days
DROP TABLE IF EXISTS dashboard_problematic_machines_30days;

CREATE TABLE dashboard_problematic_machines_30days AS
WITH downtime_events AS (
    SELECT 
        machine_name,
        type,
        CASE 
            WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
            WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
            WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
            ELSE 'Unknown'
        END AS production_line,
        datetime,
        status,
        LAG(status) OVER (PARTITION BY machine_name ORDER BY datetime) as prev_status
    FROM public.machine_feed_stream
    WHERE datetime >= CURRENT_DATE - INTERVAL '30' DAY
)
SELECT 
    production_line,
    machine_name,
    type,
    COUNT(*) as downtime_incidents,
    COUNT(DISTINCT datetime::date) as days_with_issues,
    MIN(datetime) as first_incident,
    MAX(datetime) as last_incident,
    CURRENT_TIMESTAMP as last_updated
FROM downtime_events
WHERE status = 'down' AND prev_status = 'operational'
GROUP BY production_line, machine_name, type;

-- 1.4 Hourly Machine Status Pattern Table
-- Identifies patterns in machine downtime by hour of day
DROP TABLE IF EXISTS dashboard_hourly_status_patterns;

CREATE TABLE dashboard_hourly_status_patterns AS
SELECT 
    EXTRACT(HOUR FROM datetime) as hour_of_day,
    COUNT(CASE WHEN status = 'operational' THEN 1 END) as operational_count,
    COUNT(CASE WHEN status = 'down' THEN 1 END) as down_count,
    COUNT(CASE WHEN status = 'warning' THEN 1 END) as warning_count,
    COUNT(*) as total_readings,
    ROUND(COUNT(CASE WHEN status = 'down' THEN 1 END) * 100.0 / COUNT(*), 2) as downtime_percentage,
    ROUND(COUNT(CASE WHEN status = 'operational' THEN 1 END) * 100.0 / COUNT(*), 2) as uptime_percentage,
    ROUND(COUNT(CASE WHEN status = 'warning' THEN 1 END) * 100.0 / COUNT(*), 2) as warning_percentage,
    CURRENT_TIMESTAMP as last_updated
FROM public.machine_feed_stream
WHERE datetime >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY EXTRACT(HOUR FROM datetime);

-- 1.5 Production Line Efficiency Comparison
-- Compare efficiency metrics across all three production lines
WITH line_metrics AS (
    SELECT 
        CASE 
            WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
            WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
            WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
            ELSE 'Unknown'
        END AS production_line,
        COUNT(DISTINCT machine_name) as total_machines,
        COUNT(CASE WHEN status = 'operational' THEN 1 END) as operational_readings,
        COUNT(CASE WHEN status = 'down' THEN 1 END) as down_readings,
        COUNT(*) as total_readings
    FROM public.machine_feed_stream
    WHERE datetime >= CURRENT_DATE - INTERVAL '7' DAY
    GROUP BY production_line
)
SELECT 
    production_line,
    total_machines,
    ROUND(operational_readings * 100.0 / total_readings, 2) as efficiency_percentage,
    operational_readings,
    down_readings,
    total_readings
FROM line_metrics
ORDER BY efficiency_percentage DESC;

-- =====================================================================================
-- 2. WORK ORDER MANAGEMENT TABLES
-- =====================================================================================

-- 2.1 Work Order Status Dashboard Table
-- Current snapshot of all work order statuses
DROP TABLE IF EXISTS dashboard_work_order_status_summary;

CREATE TABLE dashboard_work_order_status_summary AS
SELECT 
    status,
    COUNT(*) as order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage,
    ROUND(AVG(CASE WHEN status IN ('completed', 'cancelled') 
        THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END), 2) as avg_resolution_hours,
    COUNT(CASE WHEN priority = 'critical' THEN 1 END) as critical_count,
    COUNT(CASE WHEN assignee IS NULL THEN 1 END) as unassigned_count,
    CURRENT_TIMESTAMP as last_updated
FROM public.work_orders
GROUP BY status;

-- 2.2 Work Order Volume Trends (Last 30 Days) Table
-- Daily work order creation trends with 7-day moving average
DROP TABLE IF EXISTS dashboard_work_order_trends_30days;

CREATE TABLE dashboard_work_order_trends_30days AS
WITH daily_orders AS (
    SELECT 
        created_at::date as order_date,
        COUNT(*) as daily_count
    FROM public.work_orders
    WHERE created_at >= CURRENT_DATE - INTERVAL '30' DAY
    GROUP BY created_at::date
),
trend_analysis AS (
    SELECT 
        order_date,
        daily_count,
        AVG(daily_count) OVER (
            ORDER BY order_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) as seven_day_avg
    FROM daily_orders
)
SELECT 
    order_date,
    daily_count,
    ROUND(seven_day_avg, 2) as seven_day_moving_avg,
    CASE 
        WHEN daily_count > seven_day_avg * 1.2 THEN 'High'
        WHEN daily_count < seven_day_avg * 0.8 THEN 'Low'
        ELSE 'Normal'
    END as volume_indicator,
    CURRENT_TIMESTAMP as last_updated
FROM trend_analysis;

-- 2.3 Priority Analysis and Resolution Time
-- Work order metrics by priority level
SELECT 
    priority,
    COUNT(*) as total_orders,
    COUNT(CASE WHEN status = 'open' THEN 1 END) as open_orders,
    COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress_orders,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_orders,
    ROUND(AVG(CASE WHEN status = 'completed' 
              THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END), 2) as avg_resolution_hours,
    MAX(CASE WHEN status IN ('open', 'in_progress') 
        THEN (EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM timestamp)) / 3600 END) as oldest_open_hours
FROM public.work_orders
GROUP BY priority
ORDER BY 
    CASE priority 
        WHEN 'critical' THEN 1 
        WHEN 'high' THEN 2 
        WHEN 'medium' THEN 3 
        WHEN 'low' THEN 4 
    END;

-- 2.4 Machine Work Order Frequency
-- Which machines generate the most work orders
WITH machine_line AS (
    SELECT 
        machine_id,
        CASE 
            WHEN machine_id LIKE '%_01_%' THEN 'Line_1'
            WHEN machine_id LIKE '%_02_%' THEN 'Line_2'
            WHEN machine_id LIKE '%_03_%' THEN 'Line_3'
            ELSE 'Unknown'
        END AS production_line,
        COUNT(*) as total_orders,
        COUNT(CASE WHEN status = 'open' THEN 1 END) as open_orders,
        COUNT(CASE WHEN priority = 'critical' THEN 1 END) as critical_orders,
        AVG(CASE WHEN status = 'completed' 
            THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END) as avg_resolution_hours,
        MIN(created_at) as first_order,
        MAX(created_at) as last_order
    FROM public.work_orders
    GROUP BY machine_id, production_line
)
SELECT 
    production_line,
    machine_id,
    total_orders,
    open_orders,
    critical_orders,
    ROUND(avg_resolution_hours, 2) as avg_resolution_hours,
    CURRENT_DATE - first_order::date as days_since_first_order,
    CURRENT_DATE - last_order::date as days_since_last_order
FROM machine_line
ORDER BY total_orders DESC, critical_orders DESC
LIMIT 20;

-- 2.5 Work Order Aging Report
-- Track how long work orders have been open
SELECT 
    CASE 
        WHEN age_hours < 24 THEN 'Less than 1 day'
        WHEN age_hours < 72 THEN '1-3 days'
        WHEN age_hours < 168 THEN '3-7 days'
        WHEN age_hours < 720 THEN '1-4 weeks'
        ELSE 'Over 1 month'
    END as age_bucket,
    COUNT(*) as order_count,
    ROUND(AVG(age_hours), 2) as avg_age_hours,
    MIN(machine_id) as example_machine,
    MIN(priority) as min_priority,
    MAX(priority) as max_priority
FROM (
    SELECT 
        id,
        machine_id,
        priority,
        (EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM timestamp)) / 3600 as age_hours
    FROM public.work_orders
    WHERE status IN ('open', 'in_progress')
) aged_orders
GROUP BY 
    CASE 
        WHEN age_hours < 24 THEN 'Less than 1 day'
        WHEN age_hours < 72 THEN '1-3 days'
        WHEN age_hours < 168 THEN '3-7 days'
        WHEN age_hours < 720 THEN '1-4 weeks'
        ELSE 'Over 1 month'
    END
ORDER BY MIN(age_hours);

-- =====================================================================================
-- 3. EMPLOYEE & DEPARTMENT ANALYTICS
-- =====================================================================================

-- 3.1 Employee Workload Analysis
-- Current and historical workload distribution across employees
SELECT 
    e.first_name || ' ' || e.last_name as employee_name,
    e.department,
    COUNT(wo.id) as total_assigned,
    COUNT(CASE WHEN wo.status = 'open' THEN 1 END) as open_assignments,
    COUNT(CASE WHEN wo.status = 'in_progress' THEN 1 END) as in_progress_assignments,
    COUNT(CASE WHEN wo.status = 'completed' THEN 1 END) as completed_assignments,
    ROUND(AVG(CASE WHEN wo.status = 'completed' 
              THEN (EXTRACT(EPOCH FROM wo.created_at) - EXTRACT(EPOCH FROM wo.timestamp)) / 3600 END), 2) as avg_completion_hours,
    MIN(wo.created_at) as first_assignment,
    MAX(wo.created_at) as last_assignment
FROM public.employees e
LEFT JOIN public.work_orders wo ON e.first_name || ' ' || e.last_name = wo.assignee
WHERE e.active = true
GROUP BY e.id, e.first_name, e.last_name, e.department
ORDER BY total_assigned DESC, open_assignments DESC;

-- 3.2 Department Performance Metrics
-- Performance comparison across departments
SELECT 
    COALESCE(e.department, 'Unassigned') as department,
    COUNT(DISTINCT e.id) as employee_count,
    COUNT(wo.id) as total_work_orders,
    COUNT(CASE WHEN wo.status = 'completed' THEN 1 END) as completed_orders,
    ROUND(COUNT(CASE WHEN wo.status = 'completed' THEN 1 END) * 100.0 / NULLIF(COUNT(wo.id), 0), 2) as completion_rate,
    ROUND(AVG(CASE WHEN wo.status = 'completed' 
              THEN (EXTRACT(EPOCH FROM wo.created_at) - EXTRACT(EPOCH FROM wo.timestamp)) / 3600 END), 2) as avg_resolution_hours,
    COUNT(CASE WHEN wo.priority = 'critical' AND wo.status = 'completed' THEN 1 END) as critical_resolved
FROM public.employees e
LEFT JOIN public.work_orders wo ON e.first_name || ' ' || e.last_name = wo.assignee
WHERE e.active = true
GROUP BY e.department
ORDER BY completion_rate DESC, avg_resolution_hours ASC;

-- 3.3 Employee Response Time Analysis
-- How quickly employees start working on assigned tickets
WITH response_times AS (
    SELECT 
        wo.assignee,
        wo.priority,
        wo.status,
        (EXTRACT(EPOCH FROM wo.created_at) - EXTRACT(EPOCH FROM wo.timestamp)) / 3600 as response_hours
    FROM public.work_orders wo
    WHERE wo.assignee IS NOT NULL 
    AND wo.status IN ('in_progress', 'completed')
)
SELECT 
    assignee,
    COUNT(*) as total_responded,
    ROUND(AVG(response_hours), 2) as avg_response_hours,
    ROUND(AVG(CASE WHEN priority = 'critical' THEN response_hours END), 2) as avg_critical_response_hours,
    ROUND(AVG(CASE WHEN priority = 'high' THEN response_hours END), 2) as avg_high_response_hours,
    ROUND(AVG(CASE WHEN priority IN ('medium', 'low') THEN response_hours END), 2) as avg_normal_response_hours,
    MIN(response_hours) as fastest_response_hours,
    MAX(response_hours) as slowest_response_hours
FROM response_times
GROUP BY assignee
HAVING COUNT(*) >= 3  -- Only include employees with at least 3 responses
ORDER BY avg_response_hours ASC;

-- =====================================================================================
-- 4. OPERATIONAL KPIs & SUMMARY VIEWS
-- =====================================================================================

-- 4.1 Overall Equipment Effectiveness (OEE) Calculation
-- Key manufacturing KPI combining availability, performance, and quality
WITH machine_availability AS (
    SELECT 
        machine_name,
        CASE 
            WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
            WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
            WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
            ELSE 'Unknown'
        END AS production_line,
        type,
        COUNT(CASE WHEN status = 'operational' THEN 1 END) * 100.0 / COUNT(*) as availability_percent
    FROM public.machine_feed_stream
    WHERE datetime >= CURRENT_DATE - INTERVAL '7' DAY
    GROUP BY machine_name, production_line, type
),
work_order_impact AS (
    SELECT 
        machine_id,
        COUNT(*) as total_orders,
        COUNT(CASE WHEN priority IN ('high', 'critical') THEN 1 END) as priority_orders,
        AVG(CASE WHEN status = 'completed' 
            THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END) as avg_resolution_hours
    FROM public.work_orders
    WHERE created_at >= CURRENT_DATE - INTERVAL '7' DAY
    GROUP BY machine_id
)
SELECT 
    ma.production_line,
    ma.machine_name,
    ma.type,
    ROUND(ma.availability_percent, 2) as availability_percent,
    COALESCE(wo.total_orders, 0) as work_orders_7days,
    COALESCE(wo.priority_orders, 0) as priority_orders_7days,
    ROUND(COALESCE(wo.avg_resolution_hours, 0), 2) as avg_resolution_hours,
    -- Simplified OEE calculation (availability only, assuming 85% performance and 95% quality)
    ROUND(ma.availability_percent * 0.85 * 0.95 / 100, 2) as estimated_oee_percent
FROM machine_availability ma
LEFT JOIN work_order_impact wo ON ma.machine_name = wo.machine_id
ORDER BY estimated_oee_percent DESC, production_line, machine_name;

-- 4.2 Daily Operations Summary
-- Comprehensive daily summary for executive dashboard
SELECT 
    created_at::date as report_date,
    -- Work Order Metrics
    COUNT(*) as total_work_orders,
    COUNT(CASE WHEN priority = 'critical' THEN 1 END) as critical_orders,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_orders,
    ROUND(COUNT(CASE WHEN status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2) as completion_rate,
    -- Response Time Metrics
    ROUND(AVG(CASE WHEN status IN ('in_progress', 'completed') 
              THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END), 2) as avg_response_hours,
    -- Assignment Metrics
    COUNT(CASE WHEN assignee IS NOT NULL THEN 1 END) as assigned_orders,
    COUNT(CASE WHEN assignee IS NULL THEN 1 END) as unassigned_orders,
    COUNT(DISTINCT assignee) as active_assignees
FROM public.work_orders
WHERE created_at >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY created_at::date
ORDER BY report_date DESC;

-- 4.3 Exception Reporting - Critical Issues
-- High-priority items requiring immediate attention
SELECT 
    'Critical Open Work Orders' as alert_type,
    COUNT(*) as count,
    STRING_AGG(
        CONCAT(id, ' (', machine_id, ' - ', 
               ROUND((EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM timestamp)) / 3600, 1), 'h old)'), 
        ', '
    ) as details
FROM public.work_orders
WHERE priority = 'critical' AND status IN ('open', 'in_progress')

UNION ALL

SELECT 
    'Overdue High Priority Orders' as alert_type,
    COUNT(*) as count,
    STRING_AGG(
        CONCAT(id, ' (', machine_id, ' - ', assignee, ')'), 
        ', '
    ) as details
FROM public.work_orders
WHERE priority = 'high' 
    AND status IN ('open', 'in_progress')
    AND (EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM timestamp)) / 3600 > 48

UNION ALL

SELECT 
    'Unassigned Orders Over 24h' as alert_type,
    COUNT(*) as count,
    STRING_AGG(
        CONCAT(id, ' (', machine_id, ' - ', priority, ')'), 
        ', '
    ) as details
FROM public.work_orders
WHERE assignee IS NULL 
    AND status = 'open'
    AND (EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM timestamp)) / 3600 > 24

UNION ALL

SELECT 
    'Machines Down Over 4h' as alert_type,
    COUNT(DISTINCT machine_name) as count,
    STRING_AGG(DISTINCT machine_name, ', ') as details
FROM public.machine_feed_stream mf1
WHERE status = 'down'
    AND datetime >= CURRENT_DATE - INTERVAL '1' DAY
    AND NOT EXISTS (
        SELECT 1 FROM public.machine_feed_stream mf2 
        WHERE mf2.machine_name = mf1.machine_name 
            AND mf2.status = 'operational' 
            AND mf2.datetime > mf1.datetime
            AND mf2.datetime >= CURRENT_DATE - INTERVAL '1' DAY
    )
    AND (EXTRACT(EPOCH FROM NOW()) - EXTRACT(EPOCH FROM datetime)) / 3600 > 4;

-- 4.4 Time Series Analysis - Machine Status Changes Table
-- Track machine status transitions for trend analysis
DROP TABLE IF EXISTS dashboard_machine_status_changes_7days;

CREATE TABLE dashboard_machine_status_changes_7days AS
WITH status_changes AS (
    SELECT 
        datetime::date as status_date,
        EXTRACT(HOUR FROM datetime) as status_hour,
        datetime,
        machine_name,
        CASE 
            WHEN machine_name LIKE '%_01_%' THEN 'Line_1'
            WHEN machine_name LIKE '%_02_%' THEN 'Line_2'
            WHEN machine_name LIKE '%_03_%' THEN 'Line_3'
            ELSE 'Unknown'
        END AS production_line,
        type,
        status,
        LAG(status) OVER (PARTITION BY machine_name ORDER BY datetime) as previous_status
    FROM public.machine_feed_stream
    WHERE datetime >= CURRENT_DATE - INTERVAL '7' DAY
)
SELECT 
    status_date,
    status_hour,
    machine_name,
    production_line,
    type,
    status,
    previous_status,
    CASE 
        WHEN status = 'down' AND previous_status = 'operational'
        THEN 'FAILURE'
        WHEN status = 'operational' AND previous_status = 'down'
        THEN 'RECOVERY'
        ELSE 'STABLE'
    END as status_change_type,
    CURRENT_TIMESTAMP as last_updated
FROM status_changes
WHERE previous_status IS NOT NULL;

-- =====================================================================================
-- 3. EXECUTIVE DASHBOARD TABLES
-- =====================================================================================

-- 3.1 Executive Summary KPIs Table
-- High-level metrics for executive dashboard cards
DROP TABLE IF EXISTS dashboard_executive_kpis;

CREATE TABLE dashboard_executive_kpis AS
SELECT 
    'Manufacturing Overview' as metric_category,
    'Total Machines' as metric_name,
    COUNT(DISTINCT machine_name) as current_value,
    25.0 as target_value,
    'count' as value_type,
    CURRENT_TIMESTAMP as last_updated
FROM public.machine_feed_stream
WHERE datetime >= CURRENT_DATE - INTERVAL '1' DAY

UNION ALL

SELECT 
    'Manufacturing Overview' as metric_category,
    'Current Uptime %' as metric_name,
    ROUND(
        COUNT(CASE WHEN status = 'operational' THEN 1 END) * 100.0 / 
        COUNT(*), 2
    ) as current_value,
    95.0 as target_value,
    'percentage' as value_type,
    CURRENT_TIMESTAMP as last_updated
FROM (
    SELECT DISTINCT 
        machine_name,
        FIRST_VALUE(status) OVER (PARTITION BY machine_name ORDER BY datetime DESC) as status
    FROM public.machine_feed_stream
    WHERE datetime >= CURRENT_DATE - INTERVAL '1' DAY
) current_status

UNION ALL

SELECT 
    'Work Orders' as metric_category,
    'Open Orders' as metric_name,
    COUNT(*) as current_value,
    10.0 as target_value,
    'count' as value_type,
    CURRENT_TIMESTAMP as last_updated
FROM public.work_orders
WHERE status IN ('open', 'in_progress')

UNION ALL

SELECT 
    'Work Orders' as metric_category,
    'Critical Orders' as metric_name,
    COUNT(*) as current_value,
    0.0 as target_value,
    'count' as value_type,
    CURRENT_TIMESTAMP as last_updated
FROM public.work_orders
WHERE priority = 'critical' AND status IN ('open', 'in_progress')

UNION ALL

SELECT 
    'Performance' as metric_category,
    'Avg Resolution Time (hours)' as metric_name,
    ROUND(AVG((EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600), 2) as current_value,
    24.0 as target_value,
    'hours' as value_type,
    CURRENT_TIMESTAMP as last_updated
FROM public.work_orders
WHERE status = 'completed' AND created_at >= CURRENT_DATE - INTERVAL '7' DAY;

-- 5.2 Period-over-Period Comparison
-- Compare current period metrics with previous period
WITH current_period AS (
    SELECT 
        COUNT(*) as work_orders,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_orders,
        AVG(CASE WHEN status = 'completed' 
            THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END) as avg_resolution_hours,
        COUNT(CASE WHEN priority = 'critical' THEN 1 END) as critical_orders
    FROM public.work_orders
    WHERE created_at >= CURRENT_DATE - INTERVAL '7' DAY
),
previous_period AS (
    SELECT 
        COUNT(*) as work_orders,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_orders,
        AVG(CASE WHEN status = 'completed' 
            THEN (EXTRACT(EPOCH FROM created_at) - EXTRACT(EPOCH FROM timestamp)) / 3600 END) as avg_resolution_hours,
        COUNT(CASE WHEN priority = 'critical' THEN 1 END) as critical_orders
    FROM public.work_orders
    WHERE created_at >= CURRENT_DATE - INTERVAL '14' DAY
        AND created_at < CURRENT_DATE - INTERVAL '7' DAY
)
SELECT 
    'Work Orders Created' as metric,
    cp.work_orders as current_period,
    pp.work_orders as previous_period,
    ROUND((cp.work_orders - pp.work_orders) * 100.0 / NULLIF(pp.work_orders, 0), 2) as percent_change
FROM current_period cp, previous_period pp

UNION ALL

SELECT 
    'Orders Completed' as metric,
    cp.completed_orders as current_period,
    pp.completed_orders as previous_period,
    ROUND((cp.completed_orders - pp.completed_orders) * 100.0 / NULLIF(pp.completed_orders, 0), 2) as percent_change
FROM current_period cp, previous_period pp

UNION ALL

SELECT 
    'Avg Resolution Hours' as metric,
    ROUND(cp.avg_resolution_hours, 2) as current_period,
    ROUND(pp.avg_resolution_hours, 2) as previous_period,
    ROUND((cp.avg_resolution_hours - pp.avg_resolution_hours) * 100.0 / NULLIF(pp.avg_resolution_hours, 0), 2) as percent_change
FROM current_period cp, previous_period pp

UNION ALL

SELECT 
    'Critical Orders' as metric,
    cp.critical_orders as current_period,
    pp.critical_orders as previous_period,
    ROUND((cp.critical_orders - pp.critical_orders) * 100.0 / NULLIF(pp.critical_orders, 0), 2) as percent_change
FROM current_period cp, previous_period pp;