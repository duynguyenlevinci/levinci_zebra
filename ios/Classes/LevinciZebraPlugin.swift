import Flutter
import UIKit

public class LevinciZebraPlugin: NSObject, FlutterPlugin {
  // Serial queue để in tuần tự (1 lệnh 1 lần)
  private let zebraPrintQueue = DispatchQueue(label: "com.yourapp.zebra.print.queue")
  
  // ✅ Flag to track if we should clear buffer on next successful connection
  private static var shouldClearBufferOnNextSuccess: Bool = true

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel( 
      name: "levinci_zebra", binaryMessenger: registrar.messenger())
    let instance = LevinciZebraPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  // MARK: - Discover Methods
  // Helper để serialize DiscoveredPrinterNetwork thành dictionary
  func serializePrinter(_ printer: DiscoveredPrinterNetwork) -> [String: Any] {
    return [
      "address": printer.address,
      "dnsName": printer.dnsName,
      "port": printer.port,
    ]
  }

  func discoverPrintersByLan() -> [[String: Any]] {
    print("[DEBUG] discoverPrintersByLan called")
    var error: NSError?
    let printers =
      NetworkDiscovererWrapper.discoverByLanWithError(&error) as? [DiscoveredPrinterNetwork] ?? []
    if let err = error {
      print("[DEBUG] Error in discoverPrintersByLan: \(err.localizedDescription)")
      return []
    }
    let result = printers.map { serializePrinter($0) }
    print("[DEBUG] Printers by LAN: \(result)")
    return result
  }

  func discoverPrintersByBroadcast() -> [[String: Any]] {
    print("[DEBUG] discoverPrintersByBroadcast called")
    var error: NSError?
    let printers =
      NetworkDiscovererWrapper.discoverByBroadcastWithError(&error) as? [DiscoveredPrinterNetwork]
      ?? []
    if let err = error {
      print("[DEBUG] Error in discoverPrintersByBroadcast: \(err.localizedDescription)")
      return []
    }
    let result = printers.map { serializePrinter($0) }
    print("[DEBUG] Printers by Broadcast: \(result)")
    return result
  }

  func discoverPrintersByHops(hops: Int) -> [[String: Any]] {
    print("[DEBUG] discoverPrintersByHops called with hops = \(hops)")
    var error: NSError?
    let printers =
      NetworkDiscovererWrapper.discover(byHops: NSNumber(value: hops), error: &error)
      as? [DiscoveredPrinterNetwork] ?? []
    if let err = error {
      print("[DEBUG] Error in discoverPrintersByHops: \(err.localizedDescription)")
      return []
    }
    let result = printers.map { serializePrinter($0) }
    print("[DEBUG] Printers by Hops: \(result)")
    return result
  }

  // MARK: - Print command response helpers
  private func printSuccess() -> [String: Any] {
    return ["success": true]
  }

  private func printFailure(code: String, message: String) -> [String: Any] {
    return [
      "success": false,
      "errorCode": code,
      "errorMessage": message,
    ]
  }

  func sendCommand(
  ipAddress: String,
  port: Int,
  command: String,
  result: @escaping FlutterResult
) {
  let timeoutSeconds: TimeInterval = 5

  let lock = NSLock()
  var didFinish = false
  var cancelled = false

  func finish(_ value: Any) {
    lock.lock(); defer { lock.unlock() }
    guard !didFinish else { return }
    didFinish = true
    DispatchQueue.main.async { result(value) }
  }

  zebraPrintQueue.async {
    if cancelled { 
      print("[DEBUG] Task cancelled before starting")
      return 
    }

    // ✅ Start timeout timer only when the task actually starts executing in the queue
    self.zebraPrintQueue.asyncAfter(deadline: .now() + timeoutSeconds) {
      lock.lock()
      let alreadyFinished = didFinish
      if !alreadyFinished { cancelled = true }
      lock.unlock()

      guard !alreadyFinished else { return }

      finish(self.printFailure(
        code: "TIMEOUT",
        message: "Send command timed out after \(Int(timeoutSeconds))s during execution"))
    }

    guard let connection = TcpPrinterConnection(address: ipAddress, andWithPort: port) else {
      finish(self.printFailure(
        code: "FAILED_TO_CREATE_CONNECTION",
        message: "Could not create connection to Zebra printer"))
      return
    }

    var error: NSError?

    if cancelled { 
      print("[DEBUG] Task cancelled before opening connection")
      return 
    }
    print("[DEBUG] Opening connection to \(ipAddress):\(port) (Timeout: 3s)")
    // ✅ Cấu hình socket timeout 3s để tránh bị treo 2-3 phút nếu mất mạng
    connection.setMaxTimeoutForOpen(3000)
    let opened = connection.open()
    if !opened {
      // ✅ Set flag on failure to clear buffer on next retry
      LevinciZebraPlugin.shouldClearBufferOnNextSuccess = true
      connection.close()
      finish(self.printFailure(
        code: "FAILED_TO_OPEN_CONNECTION",
        message: "Could not open connection to Zebra printer"))
      return
    }

    // ✅ Automatically clear buffer if we just reconnected or first time
    if LevinciZebraPlugin.shouldClearBufferOnNextSuccess {
      print("[DEBUG] Reconnected or first start. Sending ~JA to clear printer buffer.")
      var clearErr: NSError?
      connection.write("~JA".data(using: .utf8)!, error: &clearErr)

      if let err = clearErr {
        print("[DEBUG] Failed to clear buffer: \(err.localizedDescription)")
        LevinciZebraPlugin.shouldClearBufferOnNextSuccess = true // Retry next time
        connection.close()
        finish(self.printFailure(
          code: "FAILED_TO_CLEAR_BUFFER",
          message: err.localizedDescription))
        return
      }

      // ✅ Successfully cleared, reset flag
      LevinciZebraPlugin.shouldClearBufferOnNextSuccess = false

      // ✅ Delay 0.5s for printer processing
      print("[DEBUG] Waiting 0.5s after ~JA...")
      Thread.sleep(forTimeInterval: 0.5)
    }

    if cancelled { 
        print("[DEBUG] Task cancelled after potential clear, closing connection")
        connection.close()
        return 
    }

    do {
      guard let printer = try ZebraPrinterFactory.getInstance(connection) as? ZebraPrinter else {
        connection.close()
        finish(self.printFailure(
          code: "FAILED_TO_GET_PRINTER",
          message: "Unknown error"))
        return
      }

      _ = printer.getControlLanguage()

      if cancelled { 
          print("[DEBUG] Task cancelled before write, closing connection")
          connection.close()
          return 
      }

      let data = command.data(using: .utf8) ?? Data()
      print("[DEBUG] Sending command to printer...")
      connection.write(data, error: &error)

      if let err = error {
        connection.close()
        finish(self.printFailure(
          code: "FAILED_TO_SEND_COMMAND",
          message: err.localizedDescription))
        return
      }

      connection.close()
      finish(self.printSuccess())
    } catch {
      // ✅ Set flag on failure
      LevinciZebraPlugin.shouldClearBufferOnNextSuccess = true
      connection.close()
      finish(self.printFailure(
        code: "FAILED_TO_GET_PRINTER",
        message: error.localizedDescription))
    }
  }

  // ✅ Timeout timer is now managed within the queue block above
}

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    print(
      "[DEBUG] handle called with method: \(call.method), arguments: \(String(describing: call.arguments))"
    )
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
      break
    case "get_by_lan":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected arguments", details: nil))
        return
      }

      let hops = args["hops"] as? Int
      var error: NSError?

      let printers: [[String: Any]]

      if let hops = hops {
        printers =
          NetworkDiscovererWrapper.discover(withHops: NSNumber(value: hops), error: &error)
          as? [[String: Any]] ?? []
      } else {
        printers =
          NetworkDiscovererWrapper.localBroadcastWithError(&error) as? [[String: Any]] ?? []
      }

      if let err = error {
        print("Error: \(err.localizedDescription)")
        result(
          FlutterError(code: "DISCOVERY_ERROR", message: err.localizedDescription, details: nil))
      } else {
        print("Printers: \(printers)")
        result(printers)
      }

      break
    case "discover_by_lan":
      let printers = discoverPrintersByLan()
      print("[DEBUG] Result discover_by_lan: \(printers)")
      result(printers)
    case "discover_by_broadcast":
      let printers = discoverPrintersByBroadcast()
      print("[DEBUG] Result discover_by_broadcast: \(printers)")
      result(printers)
    case "discover_by_hops":
      guard let args = call.arguments as? [String: Any],
        let hops = args["hops"] as? Int
      else {
        result(
          FlutterError(code: "INVALID_ARGUMENTS", message: "Expected hops argument", details: nil))
        return
      }
      let printers = discoverPrintersByHops(hops: hops)
      print("[DEBUG] Result discover_by_hops: \(printers)")
      result(printers)
    case "send_command":
      guard let args = call.arguments as? [String: Any],
        let ipAddress = args["ipAddress"] as? String,
        let port = args["port"] as? Int,
        let command = args["command"] as? String
      else {
        result(self.printFailure(code: "INVALID_ARGUMENT", message: "Expected arguments"))
        return
      }
      sendCommand(ipAddress: ipAddress, port: port, command: command, result: result)
      break
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
