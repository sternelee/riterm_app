import 'package:flutter/material.dart';
import 'src/rust/frb_generated.dart';
import 'src/screens/connection_screen.dart';
import 'src/services/network_service.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const RiTermApp());
}

class RiTermApp extends StatelessWidget {
  const RiTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiTerm - P2P Terminal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  final NetworkService _networkService = NetworkService();
  bool _isInitializing = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeNetwork();
  }

  Future<void> _initializeNetwork() async {
    setState(() {
      _isInitializing = true;
      _initializationError = null;
    });

    try {
      await _networkService.initializeNetwork();
    } catch (e) {
      setState(() {
        _initializationError = e.toString();
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing network...'),
            ],
          ),
        ),
      );
    }

    if (_initializationError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Network Initialization Failed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _initializationError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _initializeNetwork,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const ConnectionScreen();
  }
}