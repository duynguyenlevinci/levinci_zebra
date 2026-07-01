import 'package:levinci_zebra/models/print_command_result.dart';
import 'package:levinci_zebra/models/printer.dart';

import 'levinci_zebra_platform_interface.dart';

class LevinciZebra {
  Future<String?> getPlatformVersion() {
    return LevinciZebraPlatform.instance.getPlatformVersion();
  }

  Future<List<DiscoveredPrinter>?> discoverLanDevices({int? hops}) {
    return LevinciZebraPlatform.instance.discoverLanDevices(hops: hops);
  }

  Future<List<DiscoveredPrinter>?> discoverByLan() {
    return LevinciZebraPlatform.instance.discoverByLan();
  }

  Future<List<DiscoveredPrinter>?> discoverByBroadcast() {
    return LevinciZebraPlatform.instance.discoverByBroadcast();
  }

  Future<List<DiscoveredPrinter>?> discoverByHops({required int hops}) {
    return LevinciZebraPlatform.instance.discoverByHops(hops: hops);
  }

  Future<List<DiscoveredPrinter>?> discoverByUsb() {
    return LevinciZebraPlatform.instance.discoverByUsb();
  }

  Future<PrintCommandResult> sendCommand({
    required String ipAddress,
    required int port,
    required String command,
  }) {
    return LevinciZebraPlatform.instance.sendCommand(
      ipAddress: ipAddress,
      port: port,
      command: command,
    );
  }

  Future<PrintCommandResult> sendCommandUsb({
    required String deviceAddress,
    required String command,
  }) {
    return LevinciZebraPlatform.instance.sendCommandUsb(
      deviceAddress: deviceAddress,
      command: command,
    );
  }
}
