import 'dart:async';

import 'package:flutter/material.dart';
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

class _DeviceScreenState extends State<DeviceScreen> {
  int? _rssi;
  int? _mtuSize;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isDiscoveringServices = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  // L2CAP related state
  final Set<int> _activeL2CapChannels = {};
  bool _isListeningL2Cap = false;
  int? _listeningPsm;
  final TextEditingController _psmController = TextEditingController(text: '1001');
  final TextEditingController _l2capDataController = TextEditingController();
  String _l2capReceivedData = '';
  bool _l2capSecure = true;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;
  late StreamSubscription<int> _mtuSubscription;

  @override
  void initState() {
    super.initState();

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
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _mtuSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    _psmController.dispose();
    _l2capDataController.dispose();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
    } catch (e, backtrace) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
        print(e);
        print("backtrace: $backtrace");
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
      // Note: The actual L2CAP API methods would need to be implemented in the main library
      // For now, this shows the intended structure
      // var result = await FlutterBluePlus.listenL2CapChannel(secure: _l2capSecure);
      
      setState(() {
        _isListeningL2Cap = true;
        _listeningPsm = int.tryParse(_psmController.text) ?? 1001;
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
      // var result = await FlutterBluePlus.stopListenL2CapChannel(psm: _listeningPsm!);
      
      setState(() {
        _isListeningL2Cap = false;
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
    
    if (_activeL2CapChannels.contains(psm)) {
      Snackbar.show(ABC.c, "L2CAP channel already open for PSM: $psm", success: false);
      return;
    }

    try {
      // var result = await widget.device.openL2CapChannel(psm: psm, secure: _l2capSecure);
      
      setState(() {
        _activeL2CapChannels.add(psm);
      });
      
      Snackbar.show(ABC.c, "L2CAP channel opened - PSM: $psm", success: true);
      print("L2CAP Channel opened - Device: ${widget.device.remoteId}, PSM: $psm, Secure: $_l2capSecure");
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Open L2CAP Channel Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onDisconnectL2CapPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;
    
    if (!_activeL2CapChannels.contains(psm)) {
      Snackbar.show(ABC.c, "No L2CAP channel open for PSM: $psm", success: false);
      return;
    }

    try {
      // await widget.device.closeL2CapChannel(psm: psm);
      
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

    if (!_activeL2CapChannels.contains(psm)) {
      Snackbar.show(ABC.c, "No L2CAP channel open for PSM: $psm", success: false);
      return;
    }

    try {
      List<int> bytes = data.codeUnits;
      // await widget.device.writeL2CapChannel(psm: psm, value: bytes);
      
      Snackbar.show(ABC.c, "L2CAP data sent - ${bytes.length} bytes", success: true);
      print("L2CAP Data sent - PSM: $psm, Data: $data, Bytes: ${bytes.length}");
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Write L2CAP Channel Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onReadL2CapPressed() async {
    int psm = int.tryParse(_psmController.text) ?? 1001;
    
    if (!_activeL2CapChannels.contains(psm)) {
      Snackbar.show(ABC.c, "No L2CAP channel open for PSM: $psm", success: false);
      return;
    }

    try {
      // var result = await widget.device.readL2CapChannel(psm: psm);
      // String receivedData = String.fromCharCodes(result);
      
      // For demo purposes, simulate received data
      String receivedData = "Sample L2CAP data received at ${DateTime.now().toIso8601String()}";
      
      setState(() {
        _l2capReceivedData = receivedData;
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
          child: Text(
            'L2CAP Channels',
            style: Theme.of(context).textTheme.titleLarge,
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
        
        // Server Operations
        Padding(
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
        ),
        
        const SizedBox(height: 16),
        
        // Client Operations
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('L2CAP Client', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: isConnected ? onConnectL2CapPressed : null,
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
                    'Active channels: ${_activeL2CapChannels.join(", ")}',
                    style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Data Operations
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Data Transfer', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _l2capDataController,
                decoration: const InputDecoration(
                  labelText: 'Data to send',
                  border: OutlineInputBorder(),
                  hintText: 'Enter data to send over L2CAP...',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: onWriteL2CapPressed,
                    icon: const Icon(Icons.send),
                    label: const Text('Send Data'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onReadL2CapPressed,
                    icon: const Icon(Icons.download),
                    label: const Text('Read Data'),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Received Data Display
        if (_l2capReceivedData.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8.0),
                color: Colors.grey[50],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Received Data:',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _l2capReceivedData,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
      ],
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
              buildL2CapSection(context),
              const Divider(),
              ..._buildServiceTiles(context, widget.device),
            ],
          ),
        ),
      ),
    );
  }
}
