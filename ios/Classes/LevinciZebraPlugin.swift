import Flutter
import UIKit

public class LevinciZebraPlugin: NSObject, FlutterPlugin {
  // Serial queue để in tuần tự (1 lệnh 1 lần)
private let zebraPrintQueue = DispatchQueue(label: "com.yourapp.zebra.print.queue")

// Lock cho trạng thái reconnect
private let stateLock = NSLock()

// true = lần trước mất kết nối / lỗi => lần tới connect OK thì clear (~JA) 1 lần
private var needClearOnNextConnect = true

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

  func markDisconnected() {
    stateLock.lock()
    needClearOnNextConnect = true
    stateLock.unlock()
  }

  func shouldClearNow() -> Bool {
    stateLock.lock(); defer { stateLock.unlock() }
    return needClearOnNextConnect
  }

  func markConnectedAndCleared() {
    stateLock.lock()
    needClearOnNextConnect = false
    stateLock.unlock()
  }

  zebraPrintQueue.async {
    if cancelled { return }

    guard let connection = TcpPrinterConnection(address: ipAddress, andWithPort: port) else {
      finish(FlutterError(code: "FAILED_TO_CREATE_CONNECTION",
                         message: "Could not create connection to Zebra printer",
                         details: nil))
      return
    }

    var error: NSError?

    let opened = connection.open()
    if !opened {
      connection.close()
      markDisconnected()
      finish(FlutterError(code: "FAILED_TO_OPEN_CONNECTION",
                         message: "Could not open connection to Zebra printer",
                         details: nil))
      return
    }

    // ✅ reconnect => clear buffer 1 lần
    if shouldClearNow() {
      var clearErr: NSError?
      connection.write("~JA".data(using: .utf8)!, error: &clearErr) // Cancel All / clear buffer :contentReference[oaicite:2]{index=2}

      if let err = clearErr {
        connection.close()
        markDisconnected()
        finish(FlutterError(code: "FAILED_TO_CLEAR_BUFFER",
                           message: err.localizedDescription,
                           details: nil))
        return
      }

      // ✅ delay nhẹ để printer xử lý clear trước khi nhận job mới (driver cũng hay có delay) :contentReference[oaicite:3]{index=3}
      Thread.sleep(forTimeInterval: 0.1)

      // clear OK => từ giờ coi như connected
      markConnectedAndCleared()
    }

    do {
      guard let printer = try ZebraPrinterFactory.getInstance(connection) as? ZebraPrinter else {
        connection.close()
        markDisconnected()
        finish(FlutterError(code: "FAILED_TO_GET_PRINTER",
                           message: "Unknown error",
                           details: nil))
        return
      }

      _ = printer.getControlLanguage()

      let data = command.data(using: .utf8) ?? Data()
      connection.write(data, error: &error)

      if let err = error {
        connection.close()
        markDisconnected()
        finish(FlutterError(code: "FAILED_TO_SEND_COMMAND",
                           message: err.localizedDescription,
                           details: nil))
        return
      }

      connection.close()
      finish(true)
    } catch {
      connection.close()
      markDisconnected()
      finish(FlutterError(code: "FAILED_TO_GET_PRINTER",
                         message: error.localizedDescription,
                         details: nil))
    }
  }

  zebraPrintQueue.asyncAfter(deadline: .now() + timeoutSeconds) {
    lock.lock()
    let alreadyFinished = didFinish
    if !alreadyFinished { cancelled = true }
    lock.unlock()

    guard !alreadyFinished else { return }

    markDisconnected()
    finish(FlutterError(code: "TIMEOUT",
                       message: "Send command timed out after \(Int(timeoutSeconds))s",
                       details: nil))
  }
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
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected arguments", details: nil))
        return
      }
      sendCommand(ipAddress: ipAddress, port: port, command: command, result: result)
      break
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
