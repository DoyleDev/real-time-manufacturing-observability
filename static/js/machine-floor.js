// Machine Floor Visualization JavaScript

class MachineFloor {
    constructor() {
        this.floorData = null;
        this.machineStatuses = new Map();
        this.container = document.getElementById('machine-floor-container');

        this.init();
    }

    async init() {
        try {
            await this.loadMachineData();
            this.renderFloor();
            await this.loadCurrentStatusFromDatabase();
            console.log('Machine floor initialized successfully with database status');
        } catch (error) {
            console.error('Error initializing machine floor:', error);
            this.showError('Failed to load machine floor data');
        }
    }

    async loadMachineData() {
        try {
            const response = await fetch('/api/machines');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            this.floorData = await response.json();
            console.log('Machine data loaded:', this.floorData);
        } catch (error) {
            console.error('Error loading machine data:', error);
            throw error;
        }
    }

    async loadEmployees() {
        try {
            console.log('🔄 Loading employees for assignee dropdown...');
            const response = await fetch('/api/employees');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const employeeData = await response.json();
            console.log('👥 Employee data received:', employeeData);

            return employeeData.employees || [];
        } catch (error) {
            console.error('❌ Error loading employees:', error);
            return [];
        }
    }

    async loadCurrentStatusFromDatabase() {
        try {
            console.log('🔄 Loading current machine status from database...');
            const response = await fetch('/api/machines/current-status');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const statusData = await response.json();
            console.log('📊 Current status data received:', statusData);

            if (statusData.machine_statuses) {
                const statuses = statusData.machine_statuses;
                let updatedCount = 0;

                // Apply status to each machine that has data in database
                Object.keys(statuses).forEach(machineName => {
                    const machineStatus = statuses[machineName];
                    const status = machineStatus.status || 'unknown';

                    // Map database status to display status (same logic as real-time updates)
                    const statusLower = status.toLowerCase();
                    let displayStatus = 'unknown';

                    if (statusLower === 'operational' || statusLower.includes('running')) {
                        displayStatus = 'operational';
                    } else if (statusLower === 'warning' || statusLower.includes('caution') || statusLower.includes('warn')) {
                        displayStatus = 'warning';
                    } else if (statusLower === 'down' || statusLower.includes('error') || statusLower.includes('fault') || statusLower.includes('failed')) {
                        displayStatus = 'down';
                    }

                    console.log(`📍 Setting ${machineName}: "${status}" → "${displayStatus}"`);
                    this.updateMachineStatus(machineName, displayStatus, machineStatus);
                    updatedCount++;
                });

                console.log(`✅ Applied database status to ${updatedCount} machines`);
            } else {
                console.warn('⚠️ No machine status data received from database');
            }

        } catch (error) {
            console.error('❌ Error loading current status from database:', error);
            // Don't throw - let the floor render with default status if database unavailable
        }
    }

    renderFloor() {
        if (!this.floorData || !this.floorData.lines) {
            this.showError('No machine floor data available');
            return;
        }

        this.container.innerHTML = '';

        // Render each production line
        Object.values(this.floorData.lines).forEach(line => {
            const lineElement = this.createLineElement(line);
            this.container.appendChild(lineElement);
        });
    }

    createLineElement(line) {
        const lineDiv = document.createElement('div');
        lineDiv.className = 'production-line';
        lineDiv.dataset.lineId = line.name;

        // Line header
        const header = document.createElement('div');
        header.className = 'line-header';
        header.innerHTML = `
            <span>${line.name}</span>
            <span class="machine-count">${line.machine_count} machines</span>
        `;

        // Machines container
        const machinesContainer = document.createElement('div');
        machinesContainer.className = 'machines-container';

        // Create machine elements
        line.machines.forEach((machine, index) => {
            const machineElement = this.createMachineElement(machine);
            machinesContainer.appendChild(machineElement);

            // Add flow arrow between machines (except after the last one)
            if (index < line.machines.length - 1) {
                const arrow = document.createElement('span');
                arrow.className = 'flow-arrow';
                arrow.innerHTML = '→';
                machinesContainer.appendChild(arrow);
            }
        });

        lineDiv.appendChild(header);
        lineDiv.appendChild(machinesContainer);

        return lineDiv;
    }

    createMachineElement(machine) {
        const machineDiv = document.createElement('div');
        machineDiv.className = 'machine status-unknown';
        machineDiv.dataset.machineId = machine.name;
        machineDiv.title = `${machine.name} (${machine.type})`;

        // Status indicator (real DOM element, not pseudo-element)
        const statusIndicator = document.createElement('span');
        statusIndicator.className = 'status-indicator-dot';
        statusIndicator.textContent = '○';  // Unknown placeholder until database loads

        // Machine icon
        const icon = document.createElement('img');
        icon.className = 'machine-icon';
        icon.src = `/static/icons/${machine.icon}`;
        icon.alt = machine.type;
        icon.onerror = () => {
            // Fallback if icon fails to load
            icon.src = '/static/icons/sorter.png';
        };

        // Machine name (abbreviated for display)
        const name = document.createElement('div');
        name.className = 'machine-name';
        name.textContent = this.abbreviateMachineName(machine.name);

        // Machine type
        const type = document.createElement('div');
        type.className = 'machine-type';
        type.textContent = machine.type.replace('_', ' ');

        machineDiv.appendChild(statusIndicator);
        machineDiv.appendChild(icon);
        machineDiv.appendChild(name);
        machineDiv.appendChild(type);

        // Add click handler for future expansion
        machineDiv.addEventListener('click', () => {
            this.onMachineClick(machine);
        });

        return machineDiv;
    }

    getStatusSymbol(status) {
        // Return appropriate symbol for status (case-insensitive)
        const statusLower = status.toLowerCase();
        if (statusLower === 'operational') {
            return '●';
        } else if (statusLower === 'warning') {
            return '⚠';
        } else if (statusLower === 'down') {
            return '●';
        } else {
            return '○';  // Unknown status
        }
    }

    abbreviateMachineName(fullName) {
        // Convert "Source_Sorter_01_01" to "SS_01_01"
        const parts = fullName.split('_');
        if (parts.length >= 3) {
            const abbreviation = parts.slice(0, -2).map(part =>
                part.split('_').map(word => word.charAt(0).toUpperCase()).join('')
            ).join('_');
            const numbers = parts.slice(-2).join('_');
            return `${abbreviation}_${numbers}`;
        }
        return fullName;
    }

    updateMachineStatus(machineId, status, data = null) {
        console.log(`🔧 updateMachineStatus called: machineId="${machineId}", status="${status}"`);

        const machineElement = document.querySelector(`[data-machine-id="${machineId}"]`);
        console.log(`🎯 Element search result:`, machineElement);

        if (machineElement) {
            console.log(`✅ Found machine element for ${machineId}`);

            // Remove old status classes
            machineElement.classList.remove('status-operational', 'status-warning', 'status-down', 'status-unknown');
            console.log(`🧹 Removed old status classes`);

            // Add new status class
            const newClass = `status-${status}`;
            machineElement.classList.add(newClass);
            console.log(`🎨 Added new class: ${newClass}`);

            // Update status indicator symbol
            const statusIndicator = machineElement.querySelector('.status-indicator-dot');
            if (statusIndicator) {
                statusIndicator.textContent = this.getStatusSymbol(status);
                console.log(`🎯 Updated status indicator symbol`);
            }

            // Force browser reflow to ensure CSS changes are applied immediately
            void machineElement.offsetHeight;

            // Store status data
            this.machineStatuses.set(machineId, { status, data, timestamp: Date.now() });
            console.log(`💾 Stored status in machineStatuses map:`, { status, data, timestamp: Date.now() });

            console.log(`✅ Successfully updated machine ${machineId} status to ${status}`);
        } else {
            console.error(`❌ Machine element not found for ID: "${machineId}"`);
            console.log(`🔍 Available machine elements:`, document.querySelectorAll('[data-machine-id]'));
        }
    }

    onMachineClick(machine) {
        console.log('🖱️ Machine clicked:', machine);

        // Get current status
        const storedStatus = this.machineStatuses.get(machine.name);
        const statusText = storedStatus ? storedStatus.status : 'unknown';

        console.log(`🔍 Looking up status for machine "${machine.name}":`, storedStatus);
        console.log(`📊 Final status text: "${statusText}"`);

        // Show modal with machine details
        this.showMachineModal(machine, statusText);
    }

    async showMachineModal(machine, status) {
        const modal = document.getElementById('machine-modal');
        const modalMachineName = document.getElementById('modal-machine-name');
        const modalMachineLine = document.getElementById('modal-machine-line');
        const modalMachineType = document.getElementById('modal-machine-type');
        const modalMachineStatus = document.getElementById('modal-machine-status');
        const workOrderSection = document.getElementById('work-order-section');

        // Populate machine details
        modalMachineName.textContent = machine.name;
        modalMachineLine.textContent = machine.line;
        modalMachineType.textContent = machine.type.replace('_', ' ');
        modalMachineStatus.textContent = status;

        // Update status badge styling
        modalMachineStatus.className = `status-badge ${status}`;

        // Show work order section only for down machines
        if (status === 'down') {
            workOrderSection.style.display = 'block';
            // Load and populate employee dropdown
            await this.populateEmployeeDropdown();
        } else {
            workOrderSection.style.display = 'none';
        }

        // Store current machine for work order creation
        this.currentMachine = machine;

        // Show modal
        modal.style.display = 'block';
    }

    async populateEmployeeDropdown() {
        const assigneeSelect = document.getElementById('assignee');

        try {
            // Load employees from API
            const employees = await this.loadEmployees();

            // Clear existing options (except the first "Select employee" option)
            while (assigneeSelect.children.length > 1) {
                assigneeSelect.removeChild(assigneeSelect.lastChild);
            }

            // Add employee options
            employees.forEach(employee => {
                const option = document.createElement('option');
                option.value = employee.full_name;
                option.textContent = `${employee.full_name} (${employee.department})`;
                option.dataset.employeeId = employee.id;
                assigneeSelect.appendChild(option);
            });

            console.log(`✅ Populated assignee dropdown with ${employees.length} employees`);
        } catch (error) {
            console.error('❌ Error populating employee dropdown:', error);
        }
    }

    closeModal() {
        const modal = document.getElementById('machine-modal');
        const workOrderForm = document.getElementById('work-order-form');
        const workOrderSuccess = document.getElementById('work-order-success');
        const workOrderSection = document.getElementById('work-order-section');

        // Hide all sections
        modal.style.display = 'none';
        workOrderForm.style.display = 'none';
        workOrderSuccess.style.display = 'none';
        workOrderSection.style.display = 'none';

        // Reset form
        const form = document.getElementById('work-order-form-element');
        form.reset();
    }

    showWorkOrderForm() {
        const workOrderSection = document.getElementById('work-order-section');
        const workOrderForm = document.getElementById('work-order-form');

        workOrderSection.style.display = 'none';
        workOrderForm.style.display = 'block';
    }

    hideWorkOrderForm() {
        const workOrderSection = document.getElementById('work-order-section');
        const workOrderForm = document.getElementById('work-order-form');

        workOrderForm.style.display = 'none';
        workOrderSection.style.display = 'block';
    }

    async createWorkOrder(formData) {
        try {
            const workOrderData = {
                machine_id: this.currentMachine.name,
                issue_description: formData.get('issue_description'),
                priority: formData.get('priority'),
                reporter_name: formData.get('reporter_name'),
                assignee: formData.get('assignee') || ''
            };

            console.log('🔧 Creating work order:', workOrderData);

            const response = await fetch('/api/work-orders', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(workOrderData)
            });

            const result = await response.json();

            if (result.success) {
                console.log('✅ Work order created successfully:', result);
                this.showWorkOrderSuccess(result.work_order_id, result.message);
            } else {
                console.error('❌ Work order creation failed:', result.error);
                alert(`Failed to create work order: ${result.error}`);
            }

        } catch (error) {
            console.error('❌ Error creating work order:', error);
            alert(`Error creating work order: ${error.message}`);
        }
    }

    showWorkOrderSuccess(workOrderId, message) {
        const workOrderForm = document.getElementById('work-order-form');
        const workOrderSuccess = document.getElementById('work-order-success');
        const successMessageText = document.getElementById('success-message-text');

        workOrderForm.style.display = 'none';
        workOrderSuccess.style.display = 'block';
        successMessageText.textContent = `${message}`;

        // Auto-close modal after 3 seconds
        setTimeout(() => {
            this.closeModal();
        }, 3000);
    }

    showError(message) {
        this.container.innerHTML = `
            <div style="text-align: center; color: #dc3545; padding: 20px;">
                <strong>Error:</strong> ${message}
            </div>
        `;
    }

    // Method to be called by WebSocket updates
    processRealtimeUpdate(data) {
        console.log('🔄 processRealtimeUpdate called with data:', data);
        try {
            const parsedData = typeof data === 'string' ? JSON.parse(data) : data;
            console.log('📊 Parsed data:', parsedData);

            if (parsedData.new_data && parsedData.new_data.machine_name) {
                const machineId = parsedData.new_data.machine_name;
                const status = parsedData.new_data.status || 'unknown';
                console.log(`🏭 Processing machine: ${machineId}, raw status: "${status}"`);

                // Map database status to our CSS classes
                let displayStatus = 'unknown';

                // Convert to lowercase for consistent case-insensitive matching
                const statusLower = status.toLowerCase();
                console.log(`🔍 Status lowercase: "${statusLower}"`);

                // Match all common variations and map to lowercase CSS classes
                if (statusLower === 'operational' || statusLower.includes('running')) {
                    displayStatus = 'operational';
                } else if (statusLower === 'warning' || statusLower.includes('caution') || statusLower.includes('warn')) {
                    displayStatus = 'warning';
                } else if (statusLower === 'down' || statusLower.includes('error') || statusLower.includes('fault') || statusLower.includes('failed')) {
                    displayStatus = 'down';
                }

                console.log(`✅ Mapped status: "${status}" → "${displayStatus}"`);
                this.updateMachineStatus(machineId, displayStatus, parsedData.new_data);
            } else {
                console.warn('⚠️ Invalid data structure, missing new_data or machine_name');
            }
        } catch (error) {
            console.error('❌ Error processing real-time update:', error);
        }
    }
}

// Initialize machine floor when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    window.machineFloor = new MachineFloor();

    // Modal event listeners
    const modal = document.getElementById('machine-modal');
    const closeBtn = document.querySelector('.close-modal');
    const createWorkOrderBtn = document.getElementById('create-work-order-btn');
    const cancelWorkOrderBtn = document.getElementById('cancel-work-order');
    const workOrderForm = document.getElementById('work-order-form-element');

    // Close modal when clicking X button
    closeBtn.addEventListener('click', () => {
        window.machineFloor.closeModal();
    });

    // Close modal when clicking outside of modal content
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            window.machineFloor.closeModal();
        }
    });

    // Show work order form when clicking Create Work Form button
    createWorkOrderBtn.addEventListener('click', () => {
        window.machineFloor.showWorkOrderForm();
    });

    // Cancel work order form
    cancelWorkOrderBtn.addEventListener('click', () => {
        window.machineFloor.hideWorkOrderForm();
    });

    // Handle work order form submission
    workOrderForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const formData = new FormData(workOrderForm);
        await window.machineFloor.createWorkOrder(formData);
    });

    // Tab navigation functionality
    const navTabs = document.querySelectorAll('.nav-tab');
    const tabContents = document.querySelectorAll('.tab-content');

    navTabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const targetTab = tab.dataset.tab;

            // Remove active class from all tabs and content
            navTabs.forEach(t => t.classList.remove('active'));
            tabContents.forEach(content => content.classList.remove('active'));

            // Add active class to clicked tab and corresponding content
            tab.classList.add('active');
            document.getElementById(`${targetTab}-tab`).classList.add('active');

            // Load work orders when switching to work orders tab
            if (targetTab === 'work-orders') {
                window.workOrderManager.loadWorkOrders();
            }
        });
    });
});