// Work Order Management JavaScript

class WorkOrderManager {
    constructor() {
        this.workOrders = [];
        this.filteredWorkOrders = [];
        this.statusCounts = { open: 0, in_progress: 0, completed: 0 };
        this.filters = {
            status: '',
            priority: '',
            machine: '',
            assignee: ''
        };
        // Filter listeners will be set up when work orders are loaded
    }

    async loadWorkOrders() {
        try {
            console.log('🔄 Loading work orders...');
            const response = await fetch('/api/work-orders');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const data = await response.json();
            console.log('📋 Work orders data received:', data);

            this.workOrders = data.work_orders || [];
            this.filteredWorkOrders = [...this.workOrders]; // Initialize filtered data with all data
            this.statusCounts = data.status_counts || { open: 0, in_progress: 0, completed: 0 };

            this.setupFilterListeners(); // Set up listeners when we load work orders
            this.populateAssigneeFilter();
            this.applyFilters();
            this.updateStatusCounts();

            console.log(`✅ Loaded ${this.workOrders.length} work orders`);
        } catch (error) {
            console.error('❌ Error loading work orders:', error);
            this.showError('Failed to load work orders');
        }
    }

    setupFilterListeners() {
        const statusFilter = document.getElementById('status-filter');
        const priorityFilter = document.getElementById('priority-filter');
        const machineFilter = document.getElementById('machine-filter');
        const assigneeFilter = document.getElementById('assignee-filter');
        const clearFilters = document.getElementById('clear-filters');

        console.log('🔧 Setting up filter event listeners...', {
            statusFilter: !!statusFilter,
            priorityFilter: !!priorityFilter,
            machineFilter: !!machineFilter,
            assigneeFilter: !!assigneeFilter,
            clearFilters: !!clearFilters
        });

        if (statusFilter) statusFilter.addEventListener('change', () => this.onFilterChange());
        if (priorityFilter) priorityFilter.addEventListener('change', () => this.onFilterChange());
        if (machineFilter) machineFilter.addEventListener('input', () => this.onFilterChange());
        if (assigneeFilter) assigneeFilter.addEventListener('change', () => this.onFilterChange());
        if (clearFilters) clearFilters.addEventListener('click', () => this.clearAllFilters());
    }

    onFilterChange() {
        const statusEl = document.getElementById('status-filter');
        const priorityEl = document.getElementById('priority-filter');
        const machineEl = document.getElementById('machine-filter');
        const assigneeEl = document.getElementById('assignee-filter');

        this.filters.status = statusEl ? statusEl.value : '';
        this.filters.priority = priorityEl ? priorityEl.value : '';
        this.filters.machine = machineEl ? machineEl.value.toLowerCase() : '';
        this.filters.assignee = assigneeEl ? assigneeEl.value : '';

        console.log('🔍 Filter values:', this.filters);
        this.applyFilters();
    }

    applyFilters() {
        console.log('📊 Sample work order data:', this.workOrders[0]);

        this.filteredWorkOrders = this.workOrders.filter(workOrder => {
            let passes = true;

            // Status filter
            if (this.filters.status) {
                const workOrderStatus = workOrder.status.replace(' ', '-').toLowerCase();
                console.log(`Status check: "${workOrderStatus}" vs filter "${this.filters.status}"`);
                if (workOrderStatus !== this.filters.status) {
                    passes = false;
                }
            }

            // Priority filter
            if (this.filters.priority && passes) {
                const workOrderPriority = workOrder.priority.toLowerCase();
                console.log(`Priority check: "${workOrderPriority}" vs filter "${this.filters.priority}"`);
                if (workOrderPriority !== this.filters.priority) {
                    passes = false;
                }
            }

            // Machine filter (partial match)
            if (this.filters.machine && passes) {
                const machineMatch = workOrder.machine_id.toLowerCase().includes(this.filters.machine);
                console.log(`Machine check: "${workOrder.machine_id}" contains "${this.filters.machine}": ${machineMatch}`);
                if (!machineMatch) {
                    passes = false;
                }
            }

            // Assignee filter
            if (this.filters.assignee && passes) {
                console.log(`Assignee check: "${workOrder.assignee}" vs filter "${this.filters.assignee}"`);
                if (workOrder.assignee !== this.filters.assignee) {
                    passes = false;
                }
            }

            return passes;
        });

        this.renderWorkOrdersTable();
        console.log(`🔍 Applied filters: showing ${this.filteredWorkOrders.length} of ${this.workOrders.length} work orders`);
    }

    populateAssigneeFilter() {
        const assigneeFilter = document.getElementById('assignee-filter');
        if (!assigneeFilter) return;

        // Get unique assignees
        const assignees = [...new Set(this.workOrders.map(wo => wo.assignee))].sort();

        // Clear existing options (except first one)
        while (assigneeFilter.children.length > 1) {
            assigneeFilter.removeChild(assigneeFilter.lastChild);
        }

        // Add assignee options
        assignees.forEach(assignee => {
            const option = document.createElement('option');
            option.value = assignee;
            option.textContent = assignee;
            assigneeFilter.appendChild(option);
        });
    }

    clearAllFilters() {
        document.getElementById('status-filter').value = '';
        document.getElementById('priority-filter').value = '';
        document.getElementById('machine-filter').value = '';
        document.getElementById('assignee-filter').value = '';

        this.filters = {
            status: '',
            priority: '',
            machine: '',
            assignee: ''
        };

        this.applyFilters();
        console.log('🗑️ All filters cleared');
    }

    updateStatusCounts() {
        document.getElementById('open-count').textContent = this.statusCounts.open;
        document.getElementById('in-progress-count').textContent = this.statusCounts.in_progress;
        document.getElementById('completed-count').textContent = this.statusCounts.completed;
    }

    renderWorkOrdersTable() {
        const tableBody = document.querySelector('#work-orders-table tbody');

        if (this.filteredWorkOrders.length === 0) {
            const message = this.workOrders.length === 0
                ? "No work orders found"
                : "No work orders match the current filters";

            tableBody.innerHTML = `
                <tr class="no-data-row">
                    <td colspan="8" style="text-align: center; padding: 40px; color: #666;">
                        ${message}
                    </td>
                </tr>
            `;
            return;
        }

        tableBody.innerHTML = this.filteredWorkOrders.map(workOrder => `
            <tr>
                <td><strong>${workOrder.id}</strong></td>
                <td>${workOrder.machine_id}</td>
                <td class="issue-description">
                    ${this.truncateText(workOrder.issue_description, 60)}
                </td>
                <td>
                    <span class="priority-badge ${workOrder.priority}">
                        ${workOrder.priority}
                    </span>
                </td>
                <td>${workOrder.reporter_name}</td>
                <td>${workOrder.assignee}</td>
                <td>
                    <span class="work-status-badge ${workOrder.status.replace(' ', '-').toLowerCase()}">
                        ${workOrder.status}
                    </span>
                </td>
                <td>${this.formatDateTime(workOrder.created_at)}</td>
            </tr>
        `).join('');
    }

    truncateText(text, maxLength) {
        if (text.length <= maxLength) return text;
        return text.substring(0, maxLength) + '...';
    }

    formatDateTime(isoString) {
        if (!isoString) return '-';
        const date = new Date(isoString);
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
    }

    showError(message) {
        const tableBody = document.querySelector('#work-orders-table tbody');
        tableBody.innerHTML = `
            <tr class="error-row">
                <td colspan="8" style="text-align: center; padding: 40px; color: #dc3545;">
                    <strong>Error:</strong> ${message}
                </td>
            </tr>
        `;
    }
}

// Initialize work order manager when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    window.workOrderManager = new WorkOrderManager();
});