import 'package:flutter/material.dart';
import '../services/keyboard_shortcuts_service.dart';

class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.keyboard, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Keyboard Shortcuts',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),

            // Shortcuts list
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildShortcutsSection(
                      context,
                      'Terminal Management',
                      [
                        const KeyboardShortcut(keys: 'Ctrl+T, Ctrl+N', description: 'Create new terminal'),
                        const KeyboardShortcut(keys: 'Ctrl+W', description: 'Close current terminal'),
                        const KeyboardShortcut(keys: 'Ctrl+Q', description: 'Stop current terminal'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildShortcutsSection(
                      context,
                      'Terminal Navigation',
                      [
                        const KeyboardShortcut(keys: 'Ctrl+Tab', description: 'Switch to next terminal'),
                        const KeyboardShortcut(keys: 'Ctrl+Shift+Tab', description: 'Switch to previous terminal'),
                        const KeyboardShortcut(keys: 'Alt+1-9', description: 'Switch to terminal by number'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildShortcutsSection(
                      context,
                      'Terminal Sizing',
                      [
                        const KeyboardShortcut(keys: 'Ctrl+R', description: 'Open resize dialog'),
                        const KeyboardShortcut(keys: 'Ctrl+Plus', description: 'Increase terminal size'),
                        const KeyboardShortcut(keys: 'Ctrl+Minus', description: 'Decrease terminal size'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildShortcutsSection(
                      context,
                      'Help & Info',
                      [
                        const KeyboardShortcut(keys: 'F1, Ctrl+?', description: 'Show this help dialog'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Note: These shortcuts work when the terminal window has focus.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutsSection(
    BuildContext context,
    String title,
    List<KeyboardShortcut> shortcuts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...shortcuts.map((shortcut) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              // Keys
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortcut.keys,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Description
              Expanded(
                child: Text(
                  shortcut.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}