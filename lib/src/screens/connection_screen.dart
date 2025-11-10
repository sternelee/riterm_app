import 'package:flutter/material.dart';
import '../services/network_service.dart';
import 'terminal_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final NetworkService _networkService = NetworkService();
  final TextEditingController _ticketController = TextEditingController();
  bool _isConnecting = false;
  String? _connectionError;

  @override
  void dispose() {
    _ticketController.dispose();
    super.dispose();
  }

  Future<void> _connectToPeer() async {
    if (_ticketController.text.trim().isEmpty) {
      setState(() {
        _connectionError = 'Please enter a session ticket';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      final sessionId = await _networkService.connectToPeer(_ticketController.text.trim());

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TerminalScreen(sessionId: sessionId),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _connectionError = e.toString();
      });
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RiTerm - Connect to Peer'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Network Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wifi,
                          color: _networkService.isInitialized ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Network Status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _networkService.isInitialized
                          ? 'Connected (${_networkService.nodeId ?? "Unknown"})'
                          : 'Not connected',
                      style: TextStyle(
                        color: _networkService.isInitialized ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Connection Form
            Text(
              'Connect to Remote Terminal',
              style: Theme.of(context).textTheme.headlineSmall,
            ),

            const SizedBox(height: 16),

            const Text(
              'Enter the session ticket provided by the host:',
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _ticketController,
              decoration: const InputDecoration(
                labelText: 'Session Ticket',
                hintText: 'Paste session ticket here...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              maxLines: 3,
              readOnly: _isConnecting,
            ),

            const SizedBox(height: 16),

            if (_connectionError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionError!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _isConnecting ? null : _connectToPeer,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.connect_without_contact),
              label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}