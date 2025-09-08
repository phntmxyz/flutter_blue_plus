import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/extra.dart';

class L2CapDemoScreen extends StatefulWidget {
  const L2CapDemoScreen({super.key});

  @override
  State<L2CapDemoScreen> createState() => _L2CapDemoScreenState();
}

class _L2CapDemoScreenState extends State<L2CapDemoScreen> {
  bool _isListeningL2Cap = false;
  int? _listeningPsm;
  final TextEditingController _psmController = TextEditingController(text: '1001');
  final TextEditingController _l2capDataController = TextEditingController();
  final List<String> _logMessages = [];
  bool _l2capSecure = true;

  @override
  void dispose() {
    _psmController.dispose();
    _l2capDataController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.insert(0, "${DateTime.now().toLocal().toString().substring(11, 23)}: $message");
      if (_logMessages.length > 50) {
        _logMessages.removeLast();
      }
    });
  }

  Future onStartL2CapServerPressed() async {
    if (_isListeningL2Cap) {
      Snackbar.show(ABC.a, "L2CAP Server already running", success: false);
      return;
    }

    try {
      // Note: The actual L2CAP API methods would need to be implemented in the main library
      // For now, this shows the intended structure
      // var result = await FlutterBluePlus.listenL2CapChannel(secure: _l2capSecure);
      
      setState(() {
        _isListeningL2Cap = true;
        _listeningPsm = int.tryParse(_psmController.text) ?? 1001;
      });
      
      _addLog("L2CAP Server started on PSM: $_listeningPsm (${_l2capSecure ? "Secure" : "Insecure"})");
      Snackbar.show(ABC.a, "L2CAP Server started on PSM: $_listeningPsm", success: true);
    } catch (e, backtrace) {
      _addLog("Error starting L2CAP Server: $e");
      Snackbar.show(ABC.a, prettyException("Start L2CAP Server Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onStopL2CapServerPressed() async {
    if (!_isListeningL2Cap) {
      Snackbar.show(ABC.a, "No L2CAP Server running", success: false);
      return;
    }

    try {
      // var result = await FlutterBluePlus.stopListenL2CapChannel(psm: _listeningPsm!);
      
      setState(() {
        _isListeningL2Cap = false;
        _listeningPsm = null;
      });
      
      _addLog("L2CAP Server stopped");
      Snackbar.show(ABC.a, "L2CAP Server stopped", success: true);
    } catch (e, backtrace) {
      _addLog("Error stopping L2CAP Server: $e");
      Snackbar.show(ABC.a, prettyException("Stop L2CAP Server Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onSimulateConnectionPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;
    
    // Simulate a device connection to the L2CAP server
    _addLog("Simulated device connected to PSM: $psm");
    
    // Simulate receiving data
    Timer(const Duration(seconds: 2), () {
      _addLog("Received data from client: 'Hello L2CAP Server!'");
    });
    
    // Simulate sending a response
    Timer(const Duration(seconds: 3), () {
      _addLog("Sent response to client: 'Hello from L2CAP Server!'");
    });
    
    Snackbar.show(ABC.a, "Connection simulation started", success: true);
  }

  Widget buildServerSection() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.router, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'L2CAP Server',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // PSM Input and Security Toggle
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _psmController,
                    decoration: const InputDecoration(
                      labelText: 'PSM (Protocol Service Multiplexer)',
                      border: OutlineInputBorder(),
                      helperText: 'Dynamic PSMs start from 4097',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    const Text('Secure'),
                    Switch(
                      value: _l2capSecure,
                      onChanged: (value) => setState(() => _l2capSecure = value),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Server Control Buttons
            Wrap(
              spacing: 8.0,
              children: [
                ElevatedButton.icon(
                  onPressed: _isListeningL2Cap ? null : onStartL2CapServerPressed,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Server'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: !_isListeningL2Cap ? null : onStopL2CapServerPressed,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Server'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isListeningL2Cap ? onSimulateConnectionPressed : null,
                  icon: const Icon(Icons.devices),
                  label: const Text('Simulate Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            
            if (_isListeningL2Cap) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green[300]!),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Server listening on PSM: $_listeningPsm (${_l2capSecure ? "Secure" : "Insecure"})',
                        style: TextStyle(
                          color: Colors.green[700], 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildInfoSection() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'L2CAP Information',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'L2CAP (Logical Link Control and Adaptation Protocol) provides:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Direct socket-like communication'),
                Text('• Higher throughput than GATT characteristics'),
                Text('• Custom protocol implementation capabilities'),
                Text('• Bidirectional streaming data channels'),
                Text('• Support for secure and insecure connections'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Use Cases:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• High-speed sensor data streaming'),
                Text('• File transfers between devices'),
                Text('• Custom gaming protocols'),
                Text('• Audio/video streaming applications'),
                Text('• IoT device communication'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber[300]!),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Note: L2CAP channels require Android Q (API 29) or higher. iOS support varies by device capabilities.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLogSection() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.list_alt, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Activity Log',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _logMessages.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8.0),
                color: Colors.grey[50],
              ),
              child: _logMessages.isEmpty
                  ? const Center(
                      child: Text(
                        'No activity yet...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logMessages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            _logMessages[index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyA,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('L2CAP Demo'),
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              buildInfoSection(),
              buildServerSection(),
              buildLogSection(),
            ],
          ),
        ),
      ),
    );
  }
}