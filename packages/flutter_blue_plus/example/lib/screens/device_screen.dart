import 'dart:async';

import 'package:flutter/material.dart';
// import 'package:flutter/cupertino.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/service_tile.dart';
import '../widgets/characteristic_tile.dart';
import '../widgets/descriptor_tile.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> with SingleTickerProviderStateMixin {
  int? _rssi;
  int? _mtuSize;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isDiscoveringServices = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  // L2CAP related state
  final Map<int, BluetoothL2capChannel> _activeL2CapChannels = {};
  bool _isListeningL2Cap = false;
  int? _listeningPsm;
  final TextEditingController _psmController = TextEditingController(text: '1001');
  final TextEditingController _l2capDataController = TextEditingController();
  final List<String> _l2capReceivedList = [];
  StreamSubscription<L2CapChannelData>? _l2capSubscription;
  bool _l2capSecure = true;
  bool _isServerMode = true;
  final List<String> _logMessages = [];
  late TabController _dataLogsController; // 0: Data, 1: Logs

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;
  late StreamSubscription<int> _mtuSubscription;
  StreamSubscription<String>? _logsSubscription;

  @override
  void initState() {
    super.initState();
    _dataLogsController = TabController(length: 2, vsync: this, initialIndex: 0);
    _dataLogsController.addListener(() {
      if (mounted) setState(() {});
    });

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        _services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected && _rssi == null) {
        _rssi = await widget.device.readRssi();
      }
      if (mounted) {
        setState(() {});
      }
    });

    _mtuSubscription = widget.device.mtu.listen((value) {
      _mtuSize = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    // Subscribe to FBP logs for the Logs view
    _logsSubscription = FlutterBluePlus.logs.listen((line) {
      _logMessages.insert(0, line);
      if (_logMessages.length > 300) {
        _logMessages.removeRange(300, _logMessages.length);
      }
      if (mounted && _dataLogsController.index == 1) {
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
      _l2capReceivedList.insert(0, receivedData);
      if (_l2capReceivedList.length > 200) {
        _l2capReceivedList.removeRange(200, _l2capReceivedList.length);
      }
      if (mounted && _dataLogsController.index == 0) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _mtuSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    _psmController.dispose();
    _l2capDataController.dispose();
    _logsSubscription?.cancel();
    _l2capSubscription?.cancel();
    _dataLogsController.dispose();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
    } catch (e) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
        print(e);
        // backtrace omitted
      }
    }
  }

  Future onCancelPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream(queue: false);
      Snackbar.show(ABC.c, "Cancel: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Cancel Error:", e), success: false);
      print("$e");
      print("backtrace: $backtrace");
    }
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e), success: false);
      print("$e backtrace: $backtrace");
    }
  }

  Future onDiscoverServicesPressed() async {
    if (mounted) {
      setState(() {
        _isDiscoveringServices = true;
      });
    }
    try {
      _services = await widget.device.discoverServices();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Future onRequestMtuPressed() async {
    try {
      await widget.device.requestMtu(223, predelay: 0);
      Snackbar.show(ABC.c, "Request Mtu: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Change Mtu Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  // L2CAP Methods
  Future onStartL2CapServerPressed() async {
    if (_isListeningL2Cap) {
      Snackbar.show(ABC.c, "L2CAP Server already running", success: false);
      return;
    }

    try {
      var psm = await FlutterBluePlus.listenL2capChannel(secure: _l2capSecure);

      setState(() {
        _isListeningL2Cap = true;
        _listeningPsm = psm;
        // Update the PSM text field with the actual assigned PSM
        _psmController.text = psm.toString();
        // Create a server-side channel placeholder so Read/Write work on the server
        // We use a special remoteId 'server' that the native layer recognizes
        _activeL2CapChannels[psm] = BluetoothL2capChannel(
          deviceId: DeviceIdentifier('server'),
          psm: psm,
        );
      });

      Snackbar.show(ABC.c, "L2CAP Server started on PSM: $_listeningPsm", success: true);
      print("L2CAP Server started - PSM: $_listeningPsm, Secure: $_l2capSecure");
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Start L2CAP Server Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onStopL2CapServerPressed() async {
    if (!_isListeningL2Cap) {
      Snackbar.show(ABC.c, "No L2CAP Server running", success: false);
      return;
    }

    try {
      await FlutterBluePlus.stopListenL2capChannel(_listeningPsm!);

      setState(() {
        _isListeningL2Cap = false;
        // remove server-side channel placeholder if present
        _activeL2CapChannels.remove(_listeningPsm);
        _listeningPsm = null;
      });

      Snackbar.show(ABC.c, "L2CAP Server stopped", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Stop L2CAP Server Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onConnectL2CapPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;

    if (_activeL2CapChannels.containsKey(psm)) {
      Snackbar.show(ABC.c, "L2CAP channel already open for PSM: $psm", success: false);
      return;
    }

    try {
      // Ensure we're connected (secure handshake may have dropped connection)
      if (!isConnected) {
        await widget.device.connectAndUpdateStream();
      }
      var channel = await widget.device.openL2CapChannel(psm, secure: _l2capSecure);

      setState(() {
        _activeL2CapChannels[psm] = channel;
      });

      Snackbar.show(ABC.c, "L2CAP channel opened - PSM: $psm", success: true);
      print("L2CAP Channel opened - Device: ${widget.device.remoteId}, PSM: $psm, Secure: $_l2capSecure");
    } catch (e) {
      // Retry once after reconnect if secure handshake caused a transient drop
      try {
        if (!isConnected) {
          await widget.device.connectAndUpdateStream();
        }
        var channel = await widget.device.openL2CapChannel(psm, secure: _l2capSecure);
        setState(() {
          _activeL2CapChannels[psm] = channel;
        });
        Snackbar.show(ABC.c, "L2CAP channel opened after retry - PSM: $psm", success: true);
        print("L2CAP Channel opened after retry - Device: ${widget.device.remoteId}, PSM: $psm, Secure: $_l2capSecure");
      } catch (e2, bt2) {
        Snackbar.show(ABC.c, prettyException("Open L2CAP Channel Error:", e2), success: false);
        print(e2);
        print("backtrace: $bt2");
      }
    }
  }

  Future onDisconnectL2CapPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;

    if (!_activeL2CapChannels.containsKey(psm)) {
      Snackbar.show(ABC.c, "No L2CAP channel open for PSM: $psm", success: false);
      return;
    }

    try {
      var channel = _activeL2CapChannels[psm];
      if (channel != null) {
        await channel.close();
      }

      setState(() {
        _activeL2CapChannels.remove(psm);
      });

      Snackbar.show(ABC.c, "L2CAP channel closed - PSM: $psm", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Close L2CAP Channel Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onWriteL2CapPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;
    String data = _l2capDataController.text;

    if (data.isEmpty) {
      Snackbar.show(ABC.c, "Please enter data to send", success: false);
      return;
    }

    if (!_activeL2CapChannels.containsKey(psm)) {
      Snackbar.show(ABC.c, "No L2CAP channel open for PSM: $psm", success: false);
      return;
    }

    try {
      List<int> bytes = data.codeUnits;
      var channel = _activeL2CapChannels[psm];
      if (channel != null) {
        await channel.write(bytes);
      }

      Snackbar.show(ABC.c, "L2CAP data sent - ${bytes.length} bytes", success: true);
      print("L2CAP Data sent - PSM: $psm, Data: $data, Bytes: ${bytes.length}");
      _l2capDataController.clear();
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Write L2CAP Channel Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onReadL2CapPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;

    if (!_activeL2CapChannels.containsKey(psm)) {
      Snackbar.show(ABC.c, "No L2CAP channel open for PSM: $psm", success: false);
      return;
    }

    try {
      var channel = _activeL2CapChannels[psm];
      String receivedData;
      if (channel != null) {
        var result = await channel.read();
        receivedData = String.fromCharCodes(result);
      } else {
        // For demo purposes, simulate received data
        receivedData = "Sample L2CAP data received at ${DateTime.now().toIso8601String()}";
      }

      setState(() {
        _l2capReceivedList.insert(0, receivedData);
        if (_l2capReceivedList.length > 200) {
          _l2capReceivedList.removeRange(200, _l2capReceivedList.length);
        }
      });

      Snackbar.show(ABC.c, "L2CAP data received - ${receivedData.length} chars", success: true);
      print("L2CAP Data received - PSM: $psm, Data: $receivedData");
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Read L2CAP Channel Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  List<Widget> _buildServiceTiles(BuildContext context, BluetoothDevice d) {
    return _services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics.map((c) => _buildCharacteristicTile(c)).toList(),
          ),
        )
        .toList();
  }

  CharacteristicTile _buildCharacteristicTile(BluetoothCharacteristic c) {
    return CharacteristicTile(
      characteristic: c,
      descriptorTiles: c.descriptors.map((d) => DescriptorTile(descriptor: d)).toList(),
    );
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: CircularProgressIndicator(
          backgroundColor: Colors.black12,
          color: Colors.black26,
        ),
      ),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${widget.device.remoteId}'),
    );
  }

  Widget buildRssiTile(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isConnected ? const Icon(Icons.bluetooth_connected) : const Icon(Icons.bluetooth_disabled),
        Text(((isConnected && _rssi != null) ? '${_rssi!} dBm' : ''), style: Theme.of(context).textTheme.bodySmall)
      ],
    );
  }

  Widget buildGetServices(BuildContext context) {
    return IndexedStack(
      index: (_isDiscoveringServices) ? 1 : 0,
      children: <Widget>[
        TextButton(
          onPressed: onDiscoverServicesPressed,
          child: const Text("Get Services"),
        ),
        const IconButton(
          icon: SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.grey),
            ),
          ),
          onPressed: null,
        )
      ],
    );
  }

  Widget buildMtuTile(BuildContext context) {
    return ListTile(
        title: const Text('MTU Size'),
        subtitle: Text('$_mtuSize bytes'),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: onRequestMtuPressed,
        ));
  }

  Widget buildL2CapSection(BuildContext context) {
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Client'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Switch(
                      value: _isServerMode,
                      onChanged: (_isListeningL2Cap || _activeL2CapChannels.isNotEmpty)
                          ? null
                          : (value) => setState(() {
                                _isServerMode = value;
                                final bool canTransfer =
                                    _isServerMode ? _isListeningL2Cap : _activeL2CapChannels.isNotEmpty;
                                if (_dataLogsController.index == 0 && !canTransfer) {
                                  _dataLogsController.index = 1; // force Logs if Data would be disabled
                                }
                              }),
                    ),
                  ),
                  const Text('Server'),
                ],
              ),
            ],
          ),
        ),

        // PSM Input and Security Toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _psmController,
                  decoration: const InputDecoration(
                    labelText: 'PSM (Protocol Service Multiplexer)',
                    border: OutlineInputBorder(),
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
        ),

        const SizedBox(height: 16),

        // Server Operations (conditional)
        if (_isServerMode) _buildL2CapServerControl(context) else _buildL2CapClientControl(context),

        const SizedBox(height: 16),

        // Tabs: Data / Logs (Data default, but content is guarded when not available)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TabBar(
            controller: _dataLogsController,
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
              controller: _dataLogsController,
              children: [
                // Data tab
                Builder(builder: (context) {
                  final bool canTransfer = _isServerMode ? _isListeningL2Cap : _activeL2CapChannels.isNotEmpty;
                  if (!canTransfer) {
                    return Center(
                      child: Text(
                        _isServerMode ? 'Please start the server first' : 'Please open a channel first',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return L2CapListSection(
                    entries: _l2capReceivedList,
                    title: 'Data Transfer',
                    actions: [
                      TextField(
                        onEditingComplete: onWriteL2CapPressed,
                        controller: _l2capDataController,
                        decoration: InputDecoration(
                          labelText: 'Data to send',
                          border: OutlineInputBorder(),
                          hintText: 'Enter data to send over L2CAP...',
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: IconButton(onPressed: onWriteL2CapPressed, icon: const Icon(Icons.send, size: 16)),
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ],
                    topRightWidget: ElevatedButton.icon(
                      onPressed: onReadL2CapPressed,
                      icon: const Icon(Icons.download),
                      label: const Text('Read Data'),
                    ),
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
          Text('L2CAP Server', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: !_isListeningL2Cap ? null : onStopL2CapServerPressed,
                icon: const Icon(Icons.stop),
                label: const Text('Stop Server'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (_isListeningL2Cap)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Server listening on PSM: $_listeningPsm (${_l2capSecure ? "Secure" : "Insecure"})',
                style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Padding _buildL2CapClientControl(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('L2CAP Client', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onConnectL2CapPressed,
                icon: const Icon(Icons.link),
                label: const Text('Open Channel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: isConnected ? onDisconnectL2CapPressed : null,
                icon: const Icon(Icons.link_off),
                label: const Text('Close Channel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (_activeL2CapChannels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Active channels: ${_activeL2CapChannels.keys.join(", ")}',
                style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildConnectButton(BuildContext context) {
    return Row(children: [
      if (_isConnecting || _isDisconnecting) buildSpinner(context),
      ElevatedButton(
          onPressed: _isConnecting ? onCancelPressed : (isConnected ? onDisconnectPressed : onConnectPressed),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: Text(
            _isConnecting ? "CANCEL" : (isConnected ? "DISCONNECT" : "CONNECT"),
            style: Theme.of(context).primaryTextTheme.labelLarge?.copyWith(color: Colors.white),
          ))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          actions: [buildConnectButton(context), const SizedBox(width: 15)],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              buildRemoteId(context),
              ListTile(
                leading: buildRssiTile(context),
                title: Text('Device is ${_connectionState.toString().split('.')[1]}.'),
                trailing: buildGetServices(context),
              ),
              buildMtuTile(context),
              const Divider(),
              ..._buildServiceTiles(context, widget.device),
              const Divider(),
              buildL2CapSection(context),
              const Divider(),
            ],
          ),
        ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                topRightWidget ?? const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 16),
            if (actions.isNotEmpty) Expanded(child: Column(children: actions)),
            Container(
              height: 200,
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
                  : ListView.builder(
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
          ],
        ),
      ),
    );
  }
}
