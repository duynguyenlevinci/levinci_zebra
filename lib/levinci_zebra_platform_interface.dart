import 'package:levinci_zebra/models/print_command_result.dart';
import 'package:levinci_zebra/models/printer.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'levinci_zebra_method_channel.dart';

abstract class LevinciZebraPlatform extends PlatformInterface {
  /// Constructs a LevinciZebraPlatform.
  LevinciZebraPlatform() : super(token: _token);

  static final Object _token = Object();

  static LevinciZebraPlatform _instance = MethodChannelLevinciZebra();

  /// The default instance of [LevinciZebraPlatform] to use.
  ///
  /// Defaults to [MethodChannelLevinciZebra].
  static LevinciZebraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LevinciZebraPlatform] when
  /// they register themselves.
  static set instance(LevinciZebraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<List<DiscoveredPrinter>?> discoverLanDevices({
    int? hops,
  });

  Future<List<DiscoveredPrinter>?> discoverByLan();
  Future<List<DiscoveredPrinter>?> discoverByBroadcast();
  Future<List<DiscoveredPrinter>?> discoverByHops({required int hops});

  Future<PrintCommandResult> sendCommand({
    required String ipAddress,
    required int port,
    required String command,
  });

  Future<PrintCommandResult> sendCommandUsb({
    required String deviceAddress,
    required String command,
  });

  Future<List<DiscoveredPrinter>?> discoverByUsb();
}
