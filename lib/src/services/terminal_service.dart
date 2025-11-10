import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import '../rust/api/iroh_client.dart' as rust_api;

class TerminalService {
  static final TerminalService _instance = TerminalService._internal();
  factory TerminalService() => _instance;
  TerminalService._internal();

  String? _currentSessionId;
  String? _currentTerminalId;
  StreamSubscription<rust_api.StreamEvent>? _eventSubscription;
  Terminal? _terminal;

  void Function(String)? _onTerminalConnected;
  void Function(String)? _onTerminalOutput;
  void Function(String)? _onError;

  Future<void> startEventListening(
    String sessionId,
    Terminal terminal, {
    void Function(String)? onTerminalConnected,
    void Function(String)? onTerminalOutput,
    void Function(String)? onError,
  }) async {
    _currentSessionId = sessionId;
    _terminal = terminal;
    _onTerminalConnected = onTerminalConnected;
    _onTerminalOutput = onTerminalOutput;
    _onError = onError;

    // Cancel any existing subscription
    await _eventSubscription?.cancel();

    try {
      // Start listening to events
      _eventSubscription = _createEventStream(sessionId).listen(
        _handleStreamEvent,
        onError: (error) {
          _onError?.call('Event stream error: $error');
        },
      );
    } catch (e) {
      _onError?.call('Failed to start event listening: $e');
    }
  }

  Stream<rust_api.StreamEvent> _createEventStream(String sessionId) async* {
    while (true) {
      try {
        final event = await rust_api.getEventStream(sessionId: sessionId);
        yield event;
      } catch (e) {
        if (kDebugMode) {
          print('Error getting event: $e');
        }
        // Wait a bit before retrying
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
    }
  }

  void _handleStreamEvent(rust_api.StreamEvent event) {
    try {
      switch (event.eventType) {
        case 'terminal_created':
          final data = jsonDecode(event.data);
          final terminalId = data['terminal_id'] as String;
          _currentTerminalId = terminalId;
          _onTerminalConnected?.call(terminalId);
          break;

        case 'terminal_output':
          if (_terminal != null && _currentTerminalId != null) {
            final data = jsonDecode(event.data);
            if (data['terminal_id'] == _currentTerminalId) {
              final output = data['output'] as String;
              _terminal!.write(output);
              _onTerminalOutput?.call(output);
            }
          }
          break;

        case 'terminal_stopped':
          final data = jsonDecode(event.data);
          final terminalId = data['terminal_id'] as String;
          if (terminalId == _currentTerminalId) {
            _currentTerminalId = null;
            _terminal?.write('\n\r--- Terminal Disconnected ---\n\r');
            _onError?.call('Terminal stopped');
          }
          break;

        case 'error':
          _onError?.call(event.data);
          break;

        default:
          if (kDebugMode) {
            print('Unknown event type: ${event.eventType}');
          }
      }
    } catch (e) {
      _onError?.call('Error handling event: $e');
    }
  }

  Future<void> sendInput(String input) async {
    if (_currentSessionId == null || _currentTerminalId == null) {
      return;
    }

    try {
      final request = rust_api.TerminalInputRequest(
        sessionId: _currentSessionId!,
        terminalId: _currentTerminalId!,
        input: input,
      );

      await rust_api.sendTerminalInputToTerminal(request: request);
    } catch (e) {
      _onError?.call('Failed to send input: $e');
    }
  }

  Future<void> resizeTerminal(int rows, int cols) async {
    if (_currentSessionId == null || _currentTerminalId == null) {
      return;
    }

    try {
      final request = rust_api.TerminalResizeRequest(
        sessionId: _currentSessionId!,
        terminalId: _currentTerminalId!,
        rows: rows,
        cols: cols,
      );

      await rust_api.resizeTerminal(request: request);
    } catch (e) {
      _onError?.call('Failed to resize terminal: $e');
    }
  }

  Future<void> stopTerminal() async {
    if (_currentSessionId == null || _currentTerminalId == null) {
      return;
    }

    try {
      final request = rust_api.TerminalStopRequest(
        sessionId: _currentSessionId!,
        terminalId: _currentTerminalId!,
      );

      await rust_api.stopTerminal(request: request);
      _currentTerminalId = null;
    } catch (e) {
      _onError?.call('Failed to stop terminal: $e');
    }
  }

  void cleanup() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _currentSessionId = null;
    _currentTerminalId = null;
    _terminal = null;
    _onTerminalConnected = null;
    _onTerminalOutput = null;
    _onError = null;
  }
}