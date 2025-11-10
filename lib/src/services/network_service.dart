import '../rust/api/iroh_client.dart' as rust_api;

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  String? _nodeId;
  String? _currentSessionId;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  String? get nodeId => _nodeId;
  String? get currentSessionId => _currentSessionId;

  Future<void> initializeNetwork({String? relayUrl}) async {
    if (_isInitialized) return;

    try {
      final nodeId = relayUrl != null
          ? await rust_api.initializeNetworkWithRelay(relayUrl: relayUrl)
          : await rust_api.initializeNetwork();

      _nodeId = nodeId;
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      throw Exception('Failed to initialize network: $e');
    }
  }

  Future<String> connectToPeer(String sessionTicket) async {
    if (!_isInitialized) {
      throw Exception('Network not initialized');
    }

    try {
      _currentSessionId = await rust_api.connectToPeer(sessionTicket: sessionTicket);
      return _currentSessionId!;
    } catch (e) {
      throw Exception('Failed to connect to peer: $e');
    }
  }

  Future<void> disconnect() async {
    if (_currentSessionId != null) {
      try {
        await rust_api.disconnectSession(sessionId: _currentSessionId!);
      } catch (e) {
        // Ignore disconnect errors
      } finally {
        _currentSessionId = null;
      }
    }
  }

  Future<String> fetchNodeInfo() async {
    if (!_isInitialized) {
      throw Exception('Network not initialized');
    }

    try {
      return await rust_api.getNodeInfo();
    } catch (e) {
      throw Exception('Failed to get node info: $e');
    }
  }

  Future<rust_api.StreamEvent> getEventStream() async {
    if (_currentSessionId == null) {
      throw Exception('No active session');
    }

    try {
      return await rust_api.getEventStream(sessionId: _currentSessionId!);
    } catch (e) {
      throw Exception('Failed to get event stream: $e');
    }
  }
}