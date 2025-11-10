import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../rust/api/iroh_client.dart' as rust_api;
import '../services/network_service.dart';
import '../services/terminal_service.dart';
import '../services/keyboard_shortcuts_service.dart';
import '../widgets/interactive_terminal.dart';
import '../widgets/keyboard_shortcuts_dialog.dart';

class TerminalScreen extends StatefulWidget {
  final String sessionId;

  const TerminalScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final NetworkService _networkService = NetworkService();
  final TerminalService _terminalService = TerminalService();
  final KeyboardShortcutsService _keyboardShortcuts = KeyboardShortcutsService();
  final TextEditingController _terminalNameController = TextEditingController();
  final ScrollController _terminalListController = ScrollController();

  // Multiple terminals support
  final Map<String, Terminal> _terminals = {};
  final Map<String, String> _terminalNames = {};
  String? _currentTerminalId;
  String? _terminalStatus;

  // Terminal resize controls
  int _terminalRows = 24;
  int _terminalCols = 80;
  bool _isCreatingTerminal = false;

  @override
  void initState() {
    super.initState();
    _startEventListening();
    _setupKeyboardShortcuts();
  }

  @override
  void dispose() {
    _terminalNameController.dispose();
    _terminalListController.dispose();
    _keyboardShortcuts.dispose();
    // Note: Terminal from xterm doesn't have a dispose method
    _terminals.clear();
    _terminalService.cleanup();
    super.dispose();
  }

  Future<void> _startEventListening() async {
    try {
      await _terminalService.startEventListening(
        widget.sessionId,
        _getCurrentTerminal(),
        onTerminalConnected: (terminalId) {
          setState(() {
            _currentTerminalId = terminalId;
            _terminalNames[terminalId] = _terminalNameController.text.trim().isEmpty
                ? 'Terminal ${_terminals.length}'
                : _terminalNameController.text.trim();
            _terminalStatus = 'Connected to terminal: ${_terminalNames[terminalId]}';
          });
        },
        onTerminalOutput: (output) {
          // Terminal output is handled by TerminalService
        },
        onError: (error) {
          setState(() {
            _terminalStatus = 'Error: $error';
          });
        },
      );
    } catch (e) {
      setState(() {
        _terminalStatus = 'Failed to start event listening: $e';
      });
    }
  }

  Future<void> _createTerminal() async {
    final terminalName = _terminalNameController.text.trim().isEmpty
        ? 'flutter-terminal'
        : _terminalNameController.text.trim();

    setState(() {
      _isCreatingTerminal = true;
      _terminalStatus = 'Creating terminal...';
    });

    try {
      final request = rust_api.TerminalCreateRequest(
        sessionId: widget.sessionId,
        name: terminalName,
        size: (_terminalRows, _terminalCols), // Use current terminal size
      );

      await rust_api.createTerminal(request: request);
      setState(() {
        _terminalStatus = 'Terminal creation requested...';
      });
    } catch (e) {
      setState(() {
        _terminalStatus = 'Failed to create terminal: $e';
      });
    } finally {
      setState(() {
        _isCreatingTerminal = false;
      });
    }
  }

  Future<void> _disconnect() async {
    try {
      await _networkService.disconnect();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Show error but still navigate back
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnect error: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // Helper methods for multiple terminals
  Terminal _getCurrentTerminal() {
    if (_currentTerminalId == null || !_terminals.containsKey(_currentTerminalId)) {
      final terminal = Terminal();
      _terminals[_currentTerminalId ?? 'default'] = terminal;
      return terminal;
    }
    return _terminals[_currentTerminalId]!;
  }

  void _switchTerminal(String terminalId) {
    setState(() {
      _currentTerminalId = terminalId;
      _terminalStatus = 'Connected to terminal: ${_terminalNames[terminalId] ?? terminalId}';
    });
  }

  Future<void> _resizeTerminal() async {
    if (_currentTerminalId == null) return;

    try {
      await _terminalService.resizeTerminal(_terminalRows, _terminalCols);
      setState(() {
        _terminalStatus = 'Terminal resized to ${_terminalRows}x${_terminalCols}';
      });
    } catch (e) {
      setState(() {
        _terminalStatus = 'Failed to resize terminal: $e';
      });
    }
  }

  Future<void> _stopCurrentTerminal() async {
    if (_currentTerminalId == null) return;

    try {
      await _terminalService.stopTerminal();
      final terminalId = _currentTerminalId!;
      _terminals.remove(terminalId);
      _terminalNames.remove(terminalId);

      setState(() {
        _currentTerminalId = _terminals.keys.isNotEmpty ? _terminals.keys.first : null;
        _terminalStatus = _currentTerminalId != null
            ? 'Switched to terminal: ${_terminalNames[_currentTerminalId]}'
            : 'All terminals stopped';
      });
    } catch (e) {
      setState(() {
        _terminalStatus = 'Failed to stop terminal: $e';
      });
    }
  }

  // Keyboard shortcuts setup
  void _setupKeyboardShortcuts() {
    // Set up keyboard shortcut callbacks
    _keyboardShortcuts.onNewTerminal = () {
      if (_currentTerminalId != null) {
        _showCreateTerminalDialog();
      } else {
        _createTerminal();
      }
    };

    _keyboardShortcuts.onResizeTerminal = () {
      if (_currentTerminalId != null) {
        _showResizeDialog();
      }
    };

    _keyboardShortcuts.onStopTerminal = () {
      if (_currentTerminalId != null) {
        _stopCurrentTerminal();
      }
    };

    _keyboardShortcuts.onNextTerminal = () {
      if (_terminals.length > 1) {
        final currentIndex = _terminals.keys.toList().indexOf(_currentTerminalId!);
        final nextIndex = (currentIndex + 1) % _terminals.length;
        final nextTerminalId = _terminals.keys.elementAt(nextIndex);
        _switchTerminal(nextTerminalId);
      }
    };

    _keyboardShortcuts.onPreviousTerminal = () {
      if (_terminals.length > 1) {
        final currentIndex = _terminals.keys.toList().indexOf(_currentTerminalId!);
        final prevIndex = (currentIndex - 1 + _terminals.length) % _terminals.length;
        final prevTerminalId = _terminals.keys.elementAt(prevIndex);
        _switchTerminal(prevTerminalId);
      }
    };

    _keyboardShortcuts.onIncreaseSize = () {
      if (_currentTerminalId != null) {
        setState(() {
          _terminalRows = (_terminalRows + 1).clamp(10, 100);
          _terminalCols = (_terminalCols + 2).clamp(40, 200);
        });
        _resizeTerminal();
      }
    };

    _keyboardShortcuts.onDecreaseSize = () {
      if (_currentTerminalId != null) {
        setState(() {
          _terminalRows = (_terminalRows - 1).clamp(10, 100);
          _terminalCols = (_terminalCols - 2).clamp(40, 200);
        });
        _resizeTerminal();
      }
    };

    _keyboardShortcuts.onShowHelp = () {
      _showKeyboardShortcutsHelp();
    };

    // Start listening for keyboard shortcuts
    _keyboardShortcuts.startListening();
  }

  void _switchToTerminalByIndex(int index) {
    if (index >= 0 && index < _terminals.length) {
      final terminalId = _terminals.keys.elementAt(index);
      _switchTerminal(terminalId);
    }
  }

  void _showKeyboardShortcutsHelp() {
    showDialog(
      context: context,
      builder: (context) => const KeyboardShortcutsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RiTerm - Remote Terminal'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showKeyboardShortcutsHelp,
            tooltip: 'Keyboard Shortcuts (F1)',
          ),
          if (_currentTerminalId != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'resize':
                    _showResizeDialog();
                    break;
                  case 'stop':
                    _stopCurrentTerminal();
                    break;
                  case 'new':
                    _showCreateTerminalDialog();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'resize',
                  child: Row(
                    children: [
                      Icon(Icons.aspect_ratio),
                      SizedBox(width: 8),
                      Text('Resize Terminal'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'stop',
                  child: Row(
                    children: [
                      Icon(Icons.stop),
                      SizedBox(width: 8),
                      Text('Stop Terminal'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'new',
                  child: Row(
                    children: [
                      Icon(Icons.add),
                      SizedBox(width: 8),
                      Text('New Terminal'),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _keyboardShortcuts.globalFocusNode,
        onKeyEvent: _keyboardShortcuts.handleKeyEvent,
        child: Column(
          children: [
            // Terminal Status and Controls
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _currentTerminalId != null ? Icons.terminal : Icons.pending,
                        color: _currentTerminalId != null ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _terminalStatus ?? 'Ready to create terminal',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Terminal Creation Controls
                  if (_currentTerminalId == null)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _terminalNameController,
                            decoration: const InputDecoration(
                              labelText: 'Terminal Name (optional)',
                              hintText: 'e.g., my-terminal',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            readOnly: _isCreatingTerminal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isCreatingTerminal ? null : _createTerminal,
                          icon: _isCreatingTerminal
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add),
                          label: Text(_isCreatingTerminal ? 'Creating...' : 'Create Terminal'),
                        ),
                      ],
                    ),

                  // Terminal Resize Controls
                  if (_currentTerminalId != null)
                    Row(
                      children: [
                        Text('Size: $_terminalRows×$_terminalCols'),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            setState(() {
                              _terminalRows = (_terminalRows - 1).clamp(10, 100);
                              _terminalCols = (_terminalCols - 2).clamp(40, 200);
                            });
                          },
                          tooltip: 'Decrease size',
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              _terminalRows = (_terminalRows + 1).clamp(10, 100);
                              _terminalCols = (_terminalCols + 2).clamp(40, 200);
                            });
                          },
                          tooltip: 'Increase size',
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _resizeTerminal,
                          icon: const Icon(Icons.aspect_ratio),
                          label: const Text('Resize'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),

                  // Multiple Terminals Tabs
                  if (_terminals.isNotEmpty)
                    Container(
                      height: 48,
                      margin: const EdgeInsets.only(top: 8),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _terminals.length,
                        itemBuilder: (context, index) {
                          final terminalId = _terminals.keys.elementAt(index);
                          final terminalName = _terminalNames[terminalId] ?? 'Terminal ${index + 1}';
                          final isSelected = terminalId == _currentTerminalId;

                          return Container(
                            margin: const EdgeInsets.only(right: 4),
                            child: FilterChip(
                              label: Text(terminalName),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  _switchTerminal(terminalId);
                                }
                              },
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () async {
                                if (terminalId == _currentTerminalId) {
                                  await _stopCurrentTerminal();
                                } else {
                                  setState(() {
                                    _terminals.remove(terminalId);
                                    _terminalNames.remove(terminalId);
                                  });
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Terminal Display
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _currentTerminalId != null
                      ? InteractiveTerminal(
                          terminal: _getCurrentTerminal(),
                          sessionId: widget.sessionId,
                        )
                      : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.terminal_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No terminal connected\nCreate a terminal to begin',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Dialog methods
  void _showResizeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resize Terminal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current size: $_terminalRows×$_terminalCols'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Rows',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _terminalRows.toString()),
                    onChanged: (value) {
                      final rows = int.tryParse(value);
                      if (rows != null) {
                        setState(() {
                          _terminalRows = rows.clamp(10, 100);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Columns',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _terminalCols.toString()),
                    onChanged: (value) {
                      final cols = int.tryParse(value);
                      if (cols != null) {
                        setState(() {
                          _terminalCols = cols.clamp(40, 200);
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _resizeTerminal();
              Navigator.of(context).pop();
            },
            child: const Text('Resize'),
          ),
        ],
      ),
    );
  }

  void _showCreateTerminalDialog() {
    final nameController = TextEditingController();
    int rows = 24;
    int cols = 80;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Terminal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Terminal Name (optional)',
                  hintText: 'e.g., my-terminal',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Rows',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: rows.toString()),
                      onChanged: (value) {
                        final newRows = int.tryParse(value);
                        if (newRows != null) {
                          setDialogState(() {
                            rows = newRows.clamp(10, 100);
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Columns',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: cols.toString()),
                      onChanged: (value) {
                        final newCols = int.tryParse(value);
                        if (newCols != null) {
                          setDialogState(() {
                            cols = newCols.clamp(40, 200);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                setState(() {
                  _terminalRows = rows;
                  _terminalCols = cols;
                  _terminalNameController.text = nameController.text;
                });

                await _createTerminal();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}