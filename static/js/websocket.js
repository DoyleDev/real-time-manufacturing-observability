// WebSocket connection for real-time machine feed updates
document.addEventListener('DOMContentLoaded', function() {
    const messages = document.getElementById('messages');
    const status = document.getElementById('status');

    // Auto-detect correct protocol (ws:// for http://, wss:// for https://)
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws`;

    console.log('🌐 WebSocket connection attempt:', {
        currentProtocol: window.location.protocol,
        detectedWSProtocol: protocol,
        host: window.location.host,
        fullWSUrl: wsUrl
    });

    const ws = new WebSocket(wsUrl);

    ws.onopen = function(event) {
        console.log('✅ WebSocket connected successfully!', event);
        status.className = "status-indicator connected";
        status.querySelector('.status-text').textContent = "Connected";
    };

    ws.onmessage = function(event) {
        console.log('📡 WebSocket message received:', event.data);

        const message = document.createElement('div');
        message.className = 'message';

        const timestamp = new Date().toLocaleTimeString();
        message.innerHTML = `
            <div class="timestamp">${timestamp}</div>
            <div>${event.data}</div>
        `;

        messages.appendChild(message);
        messages.scrollTop = messages.scrollHeight;

        // Update machine floor with real-time data
        if (window.machineFloor) {
            console.log('🏭 Calling machineFloor.processRealtimeUpdate');
            window.machineFloor.processRealtimeUpdate(event.data);
        } else {
            console.error('❌ window.machineFloor not available!');
        }
    };

    ws.onclose = function(event) {
        console.log('❌ WebSocket connection closed:', {
            code: event.code,
            reason: event.reason,
            wasClean: event.wasClean
        });
        status.className = "status-indicator disconnected";
        status.querySelector('.status-text').textContent = "Disconnected";

        // Try to reconnect after 5 seconds if connection was lost unexpectedly
        if (!event.wasClean) {
            console.log('🔄 Attempting to reconnect in 5 seconds...');
            setTimeout(() => {
                console.log('🔄 Reconnecting WebSocket...');
                location.reload(); // Simple reconnection by reloading page
            }, 5000);
        }
    };

    ws.onerror = function(error) {
        console.error('❌ WebSocket error occurred:', {
            error: error,
            readyState: ws.readyState,
            url: wsUrl
        });
        console.log('🔍 WebSocket ready states: CONNECTING=0, OPEN=1, CLOSING=2, CLOSED=3');
    };
});