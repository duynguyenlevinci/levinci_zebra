import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/print_command_result.dart';
import 'models/printer.dart';
import 'levinci_zebra_platform_interface.dart';

/// An implementation of [LevinciZebraPlatform] that uses method channels.
class MethodChannelLevinciZebra extends LevinciZebraPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('levinci_zebra');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<List<DiscoveredPrinter>?> discoverLanDevices({int? hops}) async {
    final devices = await methodChannel.invokeMethod<dynamic>(
      'get_by_lan',
      <String, dynamic>{
        'hops': hops,
      },
    );
    return devices
        ?.map<DiscoveredPrinter>(
            (e) => DiscoveredPrinter.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<DiscoveredPrinter>?> discoverByLan() async {
    final devices =
        await methodChannel.invokeMethod<dynamic>('discover_by_lan');
    return devices
        ?.map<DiscoveredPrinter>(
            (e) => DiscoveredPrinter.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<DiscoveredPrinter>?> discoverByBroadcast() async {
    final devices = await methodChannel
        .invokeMethod<List<Map<Object?, Object?>>>('discover_by_broadcast');
    return devices
        ?.map<DiscoveredPrinter>(
            (e) => DiscoveredPrinter.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<DiscoveredPrinter>?> discoverByHops({required int hops}) async {
    final devices = await methodChannel.invokeMethod<dynamic>(
      'discover_by_hops',
      <String, dynamic>{'hops': hops},
    );
    return devices
        ?.map<DiscoveredPrinter>(
            (e) => DiscoveredPrinter.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<PrintCommandResult> sendCommand({
    required String ipAddress,
    int? port,
    required String command,
  }) async {
    final response = await methodChannel.invokeMethod<dynamic>(
      'send_command',
      <String, dynamic>{
        'ipAddress': ipAddress,
        'port': port,
        'command': command,
      },
    );
    return PrintCommandResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<List<DiscoveredPrinterUsb>?> discoverByUsb() async {
    final devices = await methodChannel.invokeMethod<dynamic>(
      'discover_by_usb',
    );
    return devices
        ?.map<DiscoveredPrinterUsb>(
            (e) => DiscoveredPrinterUsb.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<PrintCommandResult> sendCommandUsb({
    required String deviceAddress,
    required String command,
  }) async {
    final response = await methodChannel.invokeMethod<dynamic>(
      'send_command_usb',
      <String, dynamic>{
        'deviceAddress': deviceAddress,
        'command': command,
      },
    );
    return PrintCommandResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }
}
