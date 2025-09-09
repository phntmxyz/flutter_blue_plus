// Copyright 2017-2023, Charles Weinberger & Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of '../flutter_blue_plus.dart';

class BluetoothL2capChannel {
  final DeviceIdentifier deviceId;
  final int psm;

  BluetoothL2capChannel({required this.deviceId, required this.psm});

  /// Write data to the L2CAP channel
  Future<void> write(List<int> data) async {
    await FlutterBluePlus._invokeMethod(() => FlutterBluePlusPlatform.instance.writeL2CapChannel(
      WriteL2CapChannelRequest(
        remoteId: deviceId.str,
        psm: psm,
        value: data,
      ),
    ));
  }

  /// Read data from the L2CAP channel
  Future<List<int>> read() async {
    return await FlutterBluePlus._invokeMethod(() => FlutterBluePlusPlatform.instance.readL2CapChannel(
      ReadL2CapChannelRequest(remoteId: deviceId.str, psm: psm),
    ));
  }

  /// Close the L2CAP channel
  Future<void> close() async {
    await FlutterBluePlus._invokeMethod(() => FlutterBluePlusPlatform.instance.closeL2CapChannel(
      CloseL2CapChannelRequest(remoteId: deviceId.str, psm: psm),
    ));
  }

  @override
  String toString() {
    return 'BluetoothL2capChannel{'
        'deviceId: $deviceId, '
        'psm: $psm'
        '}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothL2capChannel &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          psm == other.psm;

  @override
  int get hashCode => deviceId.hashCode ^ psm.hashCode;
}