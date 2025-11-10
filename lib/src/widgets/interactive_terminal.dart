import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../services/terminal_service.dart';

class InteractiveTerminal extends StatefulWidget {
  final Terminal terminal;
  final String sessionId;

  const InteractiveTerminal({
    super.key,
    required this.terminal,
    required this.sessionId,
  });

  @override
  State<InteractiveTerminal> createState() => _InteractiveTerminalState();
}

class _InteractiveTerminalState extends State<InteractiveTerminal> {
  final TerminalService _terminalService = TerminalService();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Request focus when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      String input = '';

      // Handle special keys using LogicalKeyboardKey
      switch (event.logicalKey.keyId) {
        case 0x0000000d: // Return/Enter
          input = '\r';
          break;
        case 0x00000008: // Backspace
          input = '\x7f';
          break;
        case 0x00000009: // Tab
          input = '\t';
          break;
        case 0x0000001b: // Escape
          input = '\x1b';
          break;
        case 0x00000071: // Left arrow
          input = '\x1b[D';
          break;
        case 0x00000072: // Right arrow
          input = '\x1b[C';
          break;
        case 0x0000006d: // Up arrow
          input = '\x1b[A';
          break;
        case 0x0000006e: // Down arrow
          input = '\x1b[B';
          break;
        case 0x00000046: // Home
          input = '\x1b[H';
          break;
        case 0x0000004b: // End
          input = '\x1b[F';
          break;
        case 0x0000004e: // Delete
          input = '\x1b[3~';
          break;
        case 0x00000043: // Page up
          input = '\x1b[5~';
          break;
        case 0x00000045: // Page down
          input = '\x1b[6~';
          break;
        default:
          // Try to get character input
          if (event.character != null && event.character!.isNotEmpty) {
            input = event.character!;
          }
      }

      // Send input to terminal service
      if (input.isNotEmpty) {
        _terminalService.sendInput(input);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: TerminalView(widget.terminal),
      ),
    );
  }
}