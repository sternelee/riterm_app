import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard shortcuts service for terminal management
class KeyboardShortcutsService {
  static final KeyboardShortcutsService _instance = KeyboardShortcutsService._internal();
  factory KeyboardShortcutsService() => _instance;
  KeyboardShortcutsService._internal();

  // Callback functions
  VoidCallback? onNewTerminal;
  VoidCallback? onResizeTerminal;
  VoidCallback? onStopTerminal;
  VoidCallback? onNextTerminal;
  VoidCallback? onPreviousTerminal;
  VoidCallback? onShowHelp;
  VoidCallback? onIncreaseSize;
  VoidCallback? onDecreaseSize;

  // Keyboard focus nodes for different contexts
  final FocusNode _globalFocusNode = FocusNode();
  bool _isListening = false;

  FocusNode get globalFocusNode => _globalFocusNode;

  /// Start listening for keyboard shortcuts
  void startListening() {
    if (_isListening) return;
    _isListening = true;
    _globalFocusNode.requestFocus();
  }

  /// Stop listening for keyboard shortcuts
  void stopListening() {
    _isListening = false;
    _globalFocusNode.unfocus();
  }

  /// Handle key events
  bool handleKeyEvent(KeyEvent event) {
    if (!_isListening) return false;

    if (event is KeyDownEvent) {
      final isCtrlPressed = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlRight);

      final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftRight);

      final isAltPressed = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altRight);

      final isMetaPressed = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaRight);

      // Handle Ctrl+ combinations
      if (isCtrlPressed && !isAltPressed && !isMetaPressed) {
        switch (event.logicalKey) {
          // Ctrl+T or Ctrl+N: New Terminal
          case LogicalKeyboardKey.keyT:
          case LogicalKeyboardKey.keyN:
            onNewTerminal?.call();
            return true;

          // Ctrl+W: Close Terminal
          case LogicalKeyboardKey.keyW:
            onStopTerminal?.call();
            return true;

          // Ctrl+R: Resize Terminal
          case LogicalKeyboardKey.keyR:
            onResizeTerminal?.call();
            return true;

          // Ctrl+Plus: Increase Size
          case LogicalKeyboardKey.equal:
          case LogicalKeyboardKey.numpadAdd:
            onIncreaseSize?.call();
            return true;

          // Ctrl+Minus: Decrease Size
          case LogicalKeyboardKey.minus:
          case LogicalKeyboardKey.numpadSubtract:
            onDecreaseSize?.call();
            return true;

          // Ctrl+Tab: Next Terminal
          case LogicalKeyboardKey.tab:
            if (isShiftPressed) {
              onPreviousTerminal?.call();
            } else {
              onNextTerminal?.call();
            }
            return true;

          // Ctrl+Q: Quit/Disconnect
          case LogicalKeyboardKey.keyQ:
            onStopTerminal?.call();
            return true;
        }
      }

      // Handle function keys
      switch (event.logicalKey) {
        // F1: Help
        case LogicalKeyboardKey.f1:
          onShowHelp?.call();
          return true;

        // Ctrl+? or Ctrl+/: Help
        case LogicalKeyboardKey.slash:
          if (isCtrlPressed) {
            onShowHelp?.call();
            return true;
          }
          break;
      }

      // Handle Alt+Number keys for direct terminal switching
      if (isAltPressed && !isCtrlPressed && !isMetaPressed && !isShiftPressed) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.digit1:
          case LogicalKeyboardKey.digit2:
          case LogicalKeyboardKey.digit3:
          case LogicalKeyboardKey.digit4:
          case LogicalKeyboardKey.digit5:
          case LogicalKeyboardKey.digit6:
          case LogicalKeyboardKey.digit7:
          case LogicalKeyboardKey.digit8:
          case LogicalKeyboardKey.digit9:
            final index = int.tryParse(event.logicalKey.keyLabel) ?? 1;
            _switchToTerminalByIndex(index - 1);
            return true;
        }
      }
    }

    return false;
  }

  void _switchToTerminalByIndex(int index) {
    // This will be handled by the terminal screen
    // We'll pass the terminal list management to the screen
  }

  /// Switch to terminal by index (called by terminal screen)
  void switchToTerminalByIndex(int index, Function(int) callback) {
    callback(index);
  }

  /// Get all available shortcuts as a list for help display
  static List<KeyboardShortcut> getAllShortcuts() {
    return [
      const KeyboardShortcut(
        keys: 'Ctrl+T, Ctrl+N',
        description: 'Create new terminal',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+W',
        description: 'Close current terminal',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+Tab',
        description: 'Switch to next terminal',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+Shift+Tab',
        description: 'Switch to previous terminal',
      ),
      const KeyboardShortcut(
        keys: 'Alt+1-9',
        description: 'Switch to terminal by number',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+R',
        description: 'Resize terminal',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+Plus',
        description: 'Increase terminal size',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+Minus',
        description: 'Decrease terminal size',
      ),
      const KeyboardShortcut(
        keys: 'Ctrl+Q',
        description: 'Stop current terminal',
      ),
      const KeyboardShortcut(
        keys: 'F1, Ctrl+?',
        description: 'Show keyboard shortcuts help',
      ),
    ];
  }

  void dispose() {
    _globalFocusNode.dispose();
    _isListening = false;
  }
}

/// Model for keyboard shortcut information
class KeyboardShortcut {
  final String keys;
  final String description;

  const KeyboardShortcut({
    required this.keys,
    required this.description,
  });
}