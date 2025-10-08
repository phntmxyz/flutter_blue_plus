import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/extra.dart';
import '../utils/snackbar.dart';

class L2CapSection extends StatefulWidget {
  const L2CapSection({super.key, required this.device});

  final BluetoothDevice device;

  @override
  State<L2CapSection> createState() => _L2CapSectionState();
}

class _L2CapSectionState extends State<L2CapSection> with SingleTickerProviderStateMixin {
  // Connection state
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  // L2CAP related state
  final Map<int, BluetoothL2capChannel> _activeL2CapChannels = {};
  final List<int> _serverPsms = []; // Track all active server PSMs
  final TextEditingController _psmController = TextEditingController();
  final TextEditingController _l2capDataController = TextEditingController();
  final Map<int, List<String>> _l2capReceivedByPsm = {}; // Per-channel received data
  StreamSubscription<L2CapChannelData>? _l2capSubscription;
  bool _l2capSecure = false;
  bool _isServerMode = true;
  bool _hasValidPsm = false;
  int? _selectedPsm; // Currently selected PSM for viewing/sending data

  void _onPsmControllerChanged() {
    {
      final int? psm = int.tryParse(_psmController.text);
      final isInvalid = psm == null || (psm < 1 || psm > 65535);
      setState(() {
        _hasValidPsm = !isInvalid;
      });
    }
  }

  // Logs
  final List<String> _logMessages = [];
  StreamSubscription<String>? _logsSubscription;

  // Tabs: 0 => Data, 1 => Logs
  late TabController _tabController;

  bool get isConnected => _connectionState == BluetoothConnectionState.connected;

  void _log(String message) {
    final prefix = 'Mode: ${_isServerMode ? "Server" : "Client"}, message: ';
    final ts = DateTime.now().toIso8601String();
    _logMessages.insert(0, '[$ts] $prefix $message');
    if (_logMessages.length > 500) {
      _logMessages.removeRange(500, _logMessages.length);
    }
    if (mounted && _tabController.index == 1) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Rebuild UI when PSM text changes so buttons update enabled state
    _psmController.addListener(_onPsmControllerChanged);

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;
      // Auto-reset L2CAP state when the peer disconnects
      if (state == BluetoothConnectionState.disconnected) {
        await resetL2cap(keepServerListening: true);
      }
      if (mounted) setState(() {});
    });

    // Subscribe to FBP logs for the Logs view
    _logsSubscription = FlutterBluePlus.logs.listen((line) {
      _logMessages.insert(0, line);
      if (_logMessages.length > 300) {
        _logMessages.removeRange(300, _logMessages.length);
      }
      if (mounted && _tabController.index == 1) {
        setState(() {});
      }
    });

    // Subscribe to L2CAP received data stream
    _l2capSubscription = FlutterBluePlus.onL2capReceived.listen((evt) {
      // Route only events for active channels or server placeholder
      final bool isServerEvent = evt.remoteId.str == 'server';
      final bool isClientEvent = _activeL2CapChannels.containsKey(evt.psm);
      if (!isServerEvent && !isClientEvent) return;

      final receivedData = String.fromCharCodes(evt.value);
      _log('L2CAP RX psm=${evt.psm} remote=${evt.remoteId.str} bytes=${evt.value.length} data="$receivedData"');

      // Store data per PSM
      if (!_l2capReceivedByPsm.containsKey(evt.psm)) {
        _l2capReceivedByPsm[evt.psm] = [];
      }
      _l2capReceivedByPsm[evt.psm]!.insert(0, receivedData);
      if (_l2capReceivedByPsm[evt.psm]!.length > 200) {
        _l2capReceivedByPsm[evt.psm]!.removeRange(200, _l2capReceivedByPsm[evt.psm]!.length);
      }

      if (mounted && _tabController.index == 0) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _psmController.removeListener(_onPsmControllerChanged);
    _psmController.dispose();
    _l2capDataController.dispose();
    _logsSubscription?.cancel();
    _l2capSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // L2CAP Methods
  Future<void> resetL2cap({bool keepServerListening = true, bool clearLogs = false}) async {
    // Close all client-side channels
    final channelsToClose = _activeL2CapChannels.entries
        .where((e) => e.value.deviceId.str != 'server')
        .map((e) => e.value)
        .toList(growable: false);

    for (final ch in channelsToClose) {
      try {
        await ch.close();
      } catch (_) {
        // ignore errors while closing
      }
    }

    // Optionally stop all server listeners
    if (!keepServerListening) {
      for (final psm in _serverPsms.toList()) {
        try {
          await FlutterBluePlus.stopL2capServer(psm);
        } catch (_) {
          // ignore errors while stopping
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _l2capDataController.clear();
      _l2capReceivedByPsm.clear();
      if (clearLogs) _logMessages.clear();

      final bool keepServer = keepServerListening && _serverPsms.isNotEmpty;

      // Reset channel map
      _activeL2CapChannels.removeWhere((psm, ch) => ch.deviceId.str != 'server');
      if (keepServer) {
        // Ensure server placeholders exist for all active servers
        for (final psm in _serverPsms) {
          _activeL2CapChannels[psm] = BluetoothL2capChannel(
            deviceId: DeviceIdentifier('server'),
            psm: psm,
          );
        }
      } else {
        _activeL2CapChannels.clear();
        _serverPsms.clear();
      }

      // Reset selections
      _psmController.clear();
      _selectedPsm = null;
    });
  }

  Future onStartL2CapServerPressed() async {
    _log('>>> USER TAPPED: Start L2CAP Server');
    try {
      var psm = await FlutterBluePlus.listenL2capChannel(secure: _l2capSecure);

      setState(() {
        _serverPsms.add(psm);
        // Create a server-side channel placeholder so Read/Write work on the server
        // We use a special remoteId 'server' that the native layer recognizes
        _activeL2CapChannels[psm] = BluetoothL2capChannel(
          deviceId: DeviceIdentifier('server'),
          psm: psm,
        );
        // Auto-select the new PSM
        _selectedPsm = psm;
        _l2capReceivedByPsm[psm] = [];
      });

      Snackbar.show(ABC.c, "L2CAP Server started on PSM: $psm", success: true);
      // ignore: avoid_print
      print("L2CAP Server started - PSM: $psm, Secure: $_l2capSecure");
      _log('Server listening started psm=$psm secure=$_l2capSecure');
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Start L2CAP Server Error:", e), success: false);
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print("backtrace: $backtrace");
      _log('Server listening start error err=$e');
    }
  }

  Future onStopL2CapServerPressed(int psm) async {
    _log('>>> USER TAPPED: Stop L2CAP Server psm=$psm');
    try {
      await FlutterBluePlus.stopL2capServer(psm);

      setState(() {
        _serverPsms.remove(psm);
        _activeL2CapChannels.remove(psm);
        _l2capReceivedByPsm.remove(psm);
        // If we stopped the selected PSM, select another or null
        if (_selectedPsm == psm) {
          _selectedPsm = _serverPsms.isNotEmpty
              ? _serverPsms.first
              : (_activeL2CapChannels.keys.isNotEmpty ? _activeL2CapChannels.keys.first : null);
        }
      });

      Snackbar.show(ABC.c, "L2CAP Server stopped - PSM: $psm", success: true);
      _log('Server listening stopped psm=$psm');
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Stop L2CAP Server Error:", e), success: false);
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print("backtrace: $backtrace");
      _log('Server listening stop error psm=$psm err=$e');
    }
  }

  Future onConnectL2CapPressed() async {
    if (!_hasValidPsm) return;
    final int psm = int.parse(_psmController.text);

    _log('>>> USER TAPPED: Open L2CAP Channel psm=$psm');

    if (_activeL2CapChannels.containsKey(psm)) {
      Snackbar.show(ABC.c, "L2CAP channel already open for PSM: $psm", success: false);
      return;
    }

    try {
      // Ensure we're connected (secure handshake may have dropped connection)
      if (!isConnected) {
        await widget.device.connectAndUpdateStream();
      }
      _log('Opening client channel psm=$psm secure=$_l2capSecure');
      var channel = await widget.device.openL2CapChannel(psm, secure: _l2capSecure);

      setState(() {
        _activeL2CapChannels[psm] = channel;
        _selectedPsm = psm;
        _l2capReceivedByPsm[psm] = [];
      });

      Snackbar.show(ABC.c, "L2CAP channel opened - PSM: $psm", success: true);
      // ignore: avoid_print
      print("L2CAP Channel opened - Device: ${widget.device.remoteId}, PSM: $psm, Secure: $_l2capSecure");
      _log('Client channel opened psm=$psm');
    } catch (e) {
      // Retry once after reconnect if secure handshake caused a transient drop
      try {
        if (!isConnected) {
          await widget.device.connectAndUpdateStream();
        }
        var channel = await widget.device.openL2CapChannel(psm, secure: _l2capSecure);
        setState(() {
          _activeL2CapChannels[psm] = channel;
          _selectedPsm = psm;
          _l2capReceivedByPsm[psm] = [];
        });
        Snackbar.show(ABC.c, "L2CAP channel opened after retry - PSM: $psm", success: true);
        // ignore: avoid_print
        print("L2CAP Channel opened after retry - Device: ${widget.device.remoteId}, PSM: $psm, Secure: $_l2capSecure");
        _log('Client channel opened after retry psm=$psm');
      } catch (e2, bt2) {
        Snackbar.show(ABC.c, prettyException("Open L2CAP Channel Error:", e2), success: false);
        // ignore: avoid_print
        print(e2);
        // ignore: avoid_print
        print("backtrace: $bt2");
        _log('Client channel open retry error psm=$psm err=$e2');
      }
    }
  }

  Future onDisconnectL2CapPressed() async {
    if (_selectedPsm == null) {
      Snackbar.show(ABC.c, "No channel selected", success: false);
      return;
    }

    final int psm = _selectedPsm!;

    _log('>>> USER TAPPED: Close L2CAP Channel psm=$psm');

    try {
      var channel = _activeL2CapChannels[psm];
      if (channel != null) {
        _log('Closing client channel psm=$psm');
        await channel.close();
      }

      setState(() {
        _activeL2CapChannels.remove(psm);
        _l2capReceivedByPsm.remove(psm);
        // Select another channel if available
        _selectedPsm = _activeL2CapChannels.keys.isNotEmpty ? _activeL2CapChannels.keys.first : null;
      });

      Snackbar.show(ABC.c, "L2CAP channel closed - PSM: $psm", success: true);
      _log('Client channel closed psm=$psm');
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Close L2CAP Channel Error:", e), success: false);
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print("backtrace: $backtrace");
      _log('Client channel close error psm=$psm err=$e');
    }
  }

  Future _onWriteL2CapPressed() async {
    if (_selectedPsm == null) {
      _log('Write not possible, no channel selected. _selectedPsm is null');
      Snackbar.show(ABC.c, "No channel selected", success: false);
      return;
    }

    String data = _l2capDataController.text;
    if (data.isEmpty) {
      Snackbar.show(ABC.c, "Please enter data to send", success: false);
      return;
    }

    final int psm = _selectedPsm!;

    _log('>>> USER TAPPED: Write to L2CAP Channel psm=$psm data="$data"');

    try {
      List<int> bytes = data.codeUnits;
      var channel = _activeL2CapChannels[psm];
      if (channel == null) {
        throw Exception("Channel not found for PSM $psm");
      }

      _log('Write attempt psm=$psm len=${bytes.length}');
      await channel.write(bytes);

      Snackbar.show(ABC.c, "L2CAP data sent - ${bytes.length} bytes", success: true);
      // ignore: avoid_print
      print("L2CAP Data sent - PSM: $psm, Data: $data, Bytes: ${bytes.length}");
      _l2capDataController.clear();
      _log('Write success psm=$psm len=${bytes.length}');
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Write L2CAP Channel Error:", e), success: false);
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print("backtrace: $backtrace");
      _log('Write error psm=$psm err=$e');
    }
  }

  Future _onReadL2CapPressed() async {
    if (_selectedPsm == null) {
      Snackbar.show(ABC.c, "No channel selected", success: false);
      return;
    }

    final int psm = _selectedPsm!;

    _log('>>> USER TAPPED: Read from L2CAP Channel psm=$psm');

    try {
      var channel = _activeL2CapChannels[psm];
      String receivedData;
      if (channel != null) {
        var result = await channel.read();
        receivedData = String.fromCharCodes(result);
      } else {
        receivedData = "Sample L2CAP data received at ${DateTime.now().toIso8601String()}";
      }

      setState(() {
        if (!_l2capReceivedByPsm.containsKey(psm)) {
          _l2capReceivedByPsm[psm] = [];
        }
        _l2capReceivedByPsm[psm]!.insert(0, receivedData);
        if (_l2capReceivedByPsm[psm]!.length > 200) {
          _l2capReceivedByPsm[psm]!.removeRange(200, _l2capReceivedByPsm[psm]!.length);
        }
      });

      Snackbar.show(ABC.c, "L2CAP data received - ${receivedData.length} chars", success: true);
      // ignore: avoid_print
      print("L2CAP Data received - PSM: $psm, Data: $receivedData");
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Read L2CAP Channel Error:", e), success: false);
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print("backtrace: $backtrace");
    }
  }

  // (PSM validation is enforced by input formatter + live state in _hasValidPsm)

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'L2CAP',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: 8.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoSegmentedControl<bool>(
                    padding: EdgeInsets.zero,
                    groupValue: _l2capSecure,
                    children: const {
                      false: _SegmentedControlButton(label: 'Insecure'),
                      true: _SegmentedControlButton(label: 'Secure'),
                    },
                    onValueChanged: (value) => setState(() => _l2capSecure = value),
                  ),
                  SizedBox(width: 8.0),
                  IgnorePointer(
                    ignoring: _serverPsms.isNotEmpty || _activeL2CapChannels.isNotEmpty,
                    child: Opacity(
                      opacity: (_serverPsms.isNotEmpty || _activeL2CapChannels.isNotEmpty) ? 0.5 : 1.0,
                      child: CupertinoSegmentedControl<bool>(
                        padding: EdgeInsets.zero,
                        groupValue: _isServerMode,
                        children: const {
                          false: _SegmentedControlButton(label: 'Client'),
                          true: _SegmentedControlButton(label: 'Server'),
                        },
                        onValueChanged: (value) => setState(() {
                          _isServerMode = value;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // PSM Input
        if (_isServerMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _psmController,
                    decoration: InputDecoration(
                      labelText: _isServerMode ? 'Assigned PSM' : 'PSM (1–65535)',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !_isServerMode,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Server or Client controls
        if (_isServerMode) _buildL2CapServerControl(context) else _buildL2CapClientControl(context),

        const SizedBox(height: 16),

        // Tabs: Data / Logs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Data Transfer'),
              Tab(text: 'Logs'),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Tab contents
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox(
            height: 380,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Data tab
                Builder(builder: (context) {
                  final bool canSend = _selectedPsm != null;
                  final List<String> entries = _selectedPsm != null ? (_l2capReceivedByPsm[_selectedPsm] ?? []) : [];

                  return L2CapListSection(
                    entries: entries,
                    title: _selectedPsm != null ? 'Data Transfer - PSM $_selectedPsm' : 'Data Transfer',
                    actions: [
                      // PSM Selector Dropdown
                      if (_activeL2CapChannels.isNotEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButton<int>(
                                value: _selectedPsm,
                                isExpanded: true,
                                hint: const Text('Select Channel (PSM)'),
                                items: _activeL2CapChannels.keys.map((psm) {
                                  final isServer = _serverPsms.contains(psm);
                                  return DropdownMenuItem(
                                    value: psm,
                                    child: Text('PSM $psm ${isServer ? "(Server)" : "(Client)"}'),
                                  );
                                }).toList(),
                                onChanged: (psm) {
                                  _log('>>> USER SELECTED: PSM $psm from dropdown');
                                  setState(() => _selectedPsm = psm);
                                },
                              ),
                            ),
                            SizedBox(width: 8),
                            TextButton(
                              onPressed: canSend ? _onReadL2CapPressed : null,
                              child: const Text('Read Data'),
                            )
                          ],
                        ),
                      const SizedBox(height: 8),
                      if (!canSend)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            _isServerMode ? 'Start a server or select a channel' : 'Open a channel to enable sending',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      TextField(
                        onEditingComplete: canSend ? _onWriteL2CapPressed : null,
                        controller: _l2capDataController,
                        decoration: InputDecoration(
                          labelText: 'Data to send',
                          border: const OutlineInputBorder(),
                          hintText: 'Enter data to send over L2CAP...',
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: IconButton(
                              onPressed: canSend ? _onWriteL2CapPressed : null,
                              icon: const Icon(Icons.send, size: 16),
                            ),
                          ),
                        ),
                        maxLines: 1,
                        enabled: true,
                      ),
                    ],
                  );
                }),
                // Logs tab
                L2CapListSection(
                  entries: _logMessages,
                  title: 'Activity Log',
                  topRightWidget: TextButton(
                    onPressed: () => setState(() => _logMessages.clear()),
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Padding _buildL2CapServerControl(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('L2CAP Server', style: Theme.of(context).textTheme.titleMedium),
              ElevatedButton.icon(
                onPressed: onStartL2CapServerPressed,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Server'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_serverPsms.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'No servers running. Click "New Server" to start.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...(_serverPsms.map((psm) => Card(
                  color: _selectedPsm == psm ? Colors.green[50] : null,
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.wifi_tethering, color: Colors.green[700]),
                    title: Text('PSM: $psm', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${_l2capSecure ? "Secure" : "Insecure"} Server'),
                    trailing: IconButton(
                      icon: const Icon(Icons.stop, color: Colors.red),
                      onPressed: () => onStopL2CapServerPressed(psm),
                      tooltip: 'Stop Server',
                    ),
                    onTap: () {
                      _log('>>> USER TAPPED: Select server PSM $psm');
                      setState(() => _selectedPsm = psm);
                    },
                  ),
                ))),
        ],
      ),
    );
  }

  Padding _buildL2CapClientControl(BuildContext context) {
    final clientChannels = _activeL2CapChannels.entries.where((e) => !_serverPsms.contains(e.key)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('L2CAP Client', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _psmController,
                  decoration: const InputDecoration(
                    labelText: 'PSM to connect',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _hasValidPsm && isConnected ? onConnectL2CapPressed : null,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Open'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (clientChannels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'No client channels open. Enter a PSM and click "Open".',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...(clientChannels.map((entry) => Card(
                  color: _selectedPsm == entry.key ? Colors.blue[50] : null,
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.link, color: Colors.blue[700]),
                    title: Text('PSM: ${entry.key}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Connected to ${widget.device.remoteId.str.substring(0, 8)}...'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        _log('>>> USER TAPPED: Close button on client PSM ${entry.key}');
                        setState(() => _selectedPsm = entry.key);
                        onDisconnectL2CapPressed();
                      },
                      tooltip: 'Close Channel',
                    ),
                    onTap: () {
                      _log('>>> USER TAPPED: Select client PSM ${entry.key}');
                      setState(() => _selectedPsm = entry.key);
                    },
                  ),
                ))),
        ],
      ),
    );
  }
}

class L2CapListSection extends StatelessWidget {
  const L2CapListSection(
      {super.key,
      required this.entries,
      required this.title,
      this.onClear,
      this.actions = const [],
      this.topRightWidget});

  final String title;
  final List<String> entries;
  final void Function()? onClear;
  final List<Widget> actions;
  final Widget? topRightWidget;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (topRightWidget != null) Align(alignment: Alignment.topRight, child: topRightWidget!),
            const SizedBox(height: 4),
            if (actions.isNotEmpty) ...actions,
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8.0),
                  color: Colors.grey[50],
                ),
                child: entries.isEmpty
                    ? const Center(
                        child: Text(
                          'No entries yet...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : SelectionArea(
                        child: ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                entries[index],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedControlButton extends StatelessWidget {
  const _SegmentedControlButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(label, style: TextStyle(fontSize: 13)),
      ),
    );
  }
}
