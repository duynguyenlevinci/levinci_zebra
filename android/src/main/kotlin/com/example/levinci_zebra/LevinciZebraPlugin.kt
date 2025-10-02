package com.example.levinci_zebra

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.annotation.RequiresApi

import com.zebra.sdk.printer.discovery.DiscoveredPrinter
import com.zebra.sdk.printer.discovery.DiscoveryException
import com.zebra.sdk.printer.discovery.DiscoveryHandler
import com.zebra.sdk.printer.discovery.NetworkDiscoverer
import com.zebra.sdk.printer.discovery.UsbDiscoverer
import com.zebra.sdk.printer.discovery.DiscoveredPrinterUsb
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/** LevinciZebraPlugin */
class LevinciZebraPlugin : FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel: MethodChannel
  private lateinit var applicationContext: Context

  private lateinit var usbManager: UsbManager
  private var pendingUsbResult: Result? = null

  companion object {
    private const val ACTION_USB_PERMISSION = "com.example.levinci_zebra.USB_PERMISSION"
  }

  private val usbReceiver = object : BroadcastReceiver() {
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    override fun onReceive(context: Context, intent: Intent) {
      when (intent.action) {
        ACTION_USB_PERMISSION -> {
          synchronized(this) {
            val device: UsbDevice? =
              intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)

            // Bỏ qua việc kiểm tra permissionGranted vì luôn trả về false
            // Thay vào đó gọi lại discovery trực tiếp
            if (device != null) {
              val savedResult = pendingUsbResult

              if (savedResult != null) {
                // Clear pending variables trước khi gọi lại
                pendingUsbResult = null

                // Gọi performUsbDiscoveryDirect trực tiếp thay vì tạo mock call
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                  performUsbDiscoveryDirect(savedResult)
                }
              } else {
              }
            } else {
              // Không có device
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                pendingUsbResult?.error("NO_DEVICE", "Không tìm thấy USB device", null)
                pendingUsbResult = null
              }
            }
          }
        }
      }
    }
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "levinci_zebra")
    channel.setMethodCallHandler(this)
    applicationContext = flutterPluginBinding.applicationContext

    usbManager = applicationContext.getSystemService(Context.USB_SERVICE) as UsbManager

    // Đăng ký broadcast receiver
    val filter = IntentFilter(ACTION_USB_PERMISSION)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      applicationContext.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("UnspecifiedRegisterReceiverFlag")
      applicationContext.registerReceiver(usbReceiver, filter)
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${Build.VERSION.RELEASE}")
      }

      "get_by_lan", "discover_by_lan", "discover_by_broadcast", "discover_by_hops" -> {
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
          val printers = mutableListOf<Map<String, Any>>()
          val handler = object : DiscoveryHandler {
            override fun foundPrinter(printer: DiscoveredPrinter) {
              val info = mutableMapOf<String, Any>()
              println("Found printer: ${printer.address} ${printer.discoveryDataMap}")

              val port = printer.discoveryDataMap["PORT_NUMBER"]
              if (port != null) {
                info["port"] = port.toInt()
              }
              info["dnsName"] = printer.discoveryDataMap["DNS_NAME"] ?: "Unknown"
              info["address"] = printer.address
              printers.add(info)
            }

            override fun discoveryFinished() {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(printers)
              }
            }

            override fun discoveryError(message: String) {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.error("DISCOVERY_ERROR", message, null)
              }
            }
          }
          try {
            when (call.method) {
              "get_by_lan" -> NetworkDiscoverer.findPrinters(handler)
              "discover_by_lan" -> NetworkDiscoverer.localBroadcast(handler)
              "discover_by_broadcast" -> NetworkDiscoverer.directedBroadcast(
                handler,
                "255.255.255.255"
              )

              "discover_by_hops" -> {
                val hops = call.argument<Int>("hops") ?: 1
                NetworkDiscoverer.multicast(handler, hops)
              }
            }
          } catch (e: DiscoveryException) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("DISCOVERY_EXCEPTION", e.message, null)
            }
          }
        }
      }

      "discover_by_usb" -> {
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
          try {
            // Kiểm tra xem có USB devices không
            val usbDevices = usbManager.deviceList
            if (usbDevices.isEmpty()) {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(emptyList<Map<String, Any>>())
              }
              return@execute
            }

            // Tìm Zebra printer devices (thường có vendor ID là 2655)
            val zebraDevices = usbDevices.values.filter { device ->
              device.vendorId == 2655 || // Zebra vendor ID
                      device.deviceClass == 7    // Printer class
            }

            if (zebraDevices.isEmpty()) {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(emptyList<Map<String, Any>>())
              }
              return@execute
            }

            // Kiểm tra và request permission cho tất cả devices
            val devicesNeedingPermission = zebraDevices.filter { device ->
              !usbManager.hasPermission(device)
            }

            if (devicesNeedingPermission.isNotEmpty()) {
              // Cần request permission
              pendingUsbResult = result

              // Request permission cho device đầu tiên
              val device = devicesNeedingPermission.first()
              val permissionIntent = PendingIntent.getBroadcast(
                applicationContext,
                0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
              )
              usbManager.requestPermission(device, permissionIntent)
            } else {
              // Đã có permission cho tất cả devices, thực hiện discovery ngay
              performUsbDiscoveryDirect(result)
            }
          } catch (e: Exception) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("DISCOVERY_EXCEPTION", "Lỗi khi discover USB: ${e.message}", null)
            }
          }
        }
      }

      "send_command" -> {
        val ipAddress = call.argument<String>("ipAddress")
        val port = call.argument<Int>("port") ?: 9100
        val command = call.argument<String>("command")

        if (ipAddress == null || command == null) {
          result.error("INVALID_ARGUMENT", "IP address and command are required", null)
          return
        }

        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
          try {
            val connection = com.zebra.sdk.comm.TcpConnection(ipAddress, port)
            try {
              connection.open()
              connection.write(command.toByteArray())
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(null)
              }
            } catch (e: Exception) {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.error("CONNECTION_ERROR", "Error writing to printer: ${e.message}", null)
              }
            } finally {
              try {
                connection.close()
              } catch (e: Exception) {
                // Ignore close errors
              }
            }
          } catch (e: Exception) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("CONNECTION_ERROR", "Error connecting to printer: ${e.message}", null)
            }
          }
        }
      }

      "send_command_usb" -> {
        val deviceAddress = call.argument<String>("deviceAddress")
        println("deviceAddress: $deviceAddress")
        val command = call.argument<String>("command")

        if (deviceAddress == null || command == null) {
          result.error(
            "INVALID_ARGUMENT",
            "Thiếu thông tin: deviceAddress và command là bắt buộc",
            null
          )
          return
        }

        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
          var connection: com.zebra.sdk.comm.Connection? = null
          try {
            // Kiểm tra USB device permission trước
            val usbDevices = usbManager.deviceList
            println("USB devices found: ${usbDevices.size}")

            val targetDevice = usbDevices.values.find { device ->
              device.deviceName == deviceAddress ||
                      "${device.vendorId}:${device.productId}" == deviceAddress
            }

            if (targetDevice != null && !usbManager.hasPermission(targetDevice)) {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.error("PERMISSION_DENIED", "Không có quyền truy cập USB device", null)
              }
              return@execute
            }

            // Tạo connection trực tiếp thay vì discovery để tránh duplicate connections
            if (targetDevice != null) {
              println("Creating direct USB connection for device: ${targetDevice.deviceName}")

              try {
                // Tạo connection trực tiếp từ USB device với UsbManager
                connection = com.zebra.sdk.comm.UsbConnection(usbManager, targetDevice)
                connection.open()

                // Kiểm tra connection status
                if (!connection.isConnected) {
                  throw Exception("Không thể kết nối với máy in USB")
                }

                println("USB connection established successfully")
                connection.write(command.toByteArray())

                // Đợi một chút để đảm bảo command được gửi
                Thread.sleep(200)

                android.os.Handler(android.os.Looper.getMainLooper()).post {
                  result.success("Command sent successfully")
                }
                return@execute

              } catch (ex: Exception) {
                println("Direct USB connection failed: ${ex.message}")
                // Fallback to discovery method nếu direct connection fail
              }
            }

            // Fallback: Sử dụng discovery method với timeout ngắn hơn
            println("Fallback to discovery method for device: $deviceAddress")
            val usbPrinters = mutableListOf<DiscoveredPrinterUsb>()
            var discoveryCompleted = false
            val DISCOVERY_TIMEOUT = 5000L // 5 giây thay vì 10 giây

            val discoveryHandler = object : DiscoveryHandler {
              override fun foundPrinter(printer: DiscoveredPrinter) {
                if (printer is DiscoveredPrinterUsb) {
                  println("Found USB printer: ${printer.address}")
                  if (printer.address == deviceAddress) {
                    synchronized(usbPrinters) {
                      if (usbPrinters.isEmpty()) { // Chỉ thêm printer đầu tiên để tránh duplicate
                        usbPrinters.add(printer)
                        println("Added printer to list: ${printer.address}")
                      }
                    }
                  }
                }
              }

              override fun discoveryFinished() {
                synchronized(this) {
                  if (discoveryCompleted) return
                  discoveryCompleted = true
                }
                println("Discovery finished. Found ${usbPrinters.size} matching printers")

                if (usbPrinters.isEmpty()) {
                  android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error(
                      "PRINTER_NOT_FOUND",
                      "Không tìm thấy máy in với địa chỉ $deviceAddress",
                      null
                    )
                  }
                  return
                }

                val printer = usbPrinters.first()
                var discoveryConnection: com.zebra.sdk.comm.Connection? = null

                try {
                  println("Creating connection from discovered printer")
                  discoveryConnection = printer.getConnection()
                  discoveryConnection.open()

                  if (!discoveryConnection.isConnected) {
                    throw Exception("Không thể kết nối với máy in")
                  }

                  discoveryConnection.write(command.toByteArray())
                  Thread.sleep(200)

                  android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.success("Command sent via discovery")
                  }
                } catch (e: Exception) {
                  android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error("CONNECTION_ERROR", "Lỗi khi gửi lệnh: ${e.message}", null)
                  }
                } finally {
                  try {
                    discoveryConnection?.close()
                    println("Discovery connection closed")
                  } catch (e: Exception) {
                    println("Warning: Error closing discovery connection: ${e.message}")
                  }
                }
              }

              override fun discoveryError(message: String) {
                synchronized(this) {
                  if (discoveryCompleted) return
                  discoveryCompleted = true
                }
                println("Discovery error: $message")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                  result.error("DISCOVERY_ERROR", message, null)
                }
              }
            }

            // Start discovery
            UsbDiscoverer.findPrinters(applicationContext, discoveryHandler)

            // Wait for discovery với timeout ngắn hơn
            val checkInterval = 100L
            var elapsedTime = 0L

            while (!discoveryCompleted && elapsedTime < DISCOVERY_TIMEOUT) {
              Thread.sleep(checkInterval)
              elapsedTime += checkInterval
            }

            // Handle timeout
            synchronized(discoveryHandler) {
              if (!discoveryCompleted) {
                discoveryCompleted = true
                println("Discovery timeout after ${DISCOVERY_TIMEOUT}ms")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                  result.error("TIMEOUT", "Timeout khi tìm kiếm máy in USB", null)
                }
              }
            }

          } catch (e: Exception) {
            println("Unexpected error in send_command_usb: ${e.message}")
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("UNEXPECTED_ERROR", "Lỗi không xác định: ${e.message}", null)
            }
          } finally {
            // Đảm bảo đóng connection
            try {
              connection?.close()
              println("Main connection closed in finally block")
            } catch (e: Exception) {
              println("Warning: Error closing main connection: ${e.message}")
            }
          }
        }
      }

      else -> {
        result.notImplemented()
      }
    }
  }

  private fun performUsbDiscoveryDirect(result: Result) {
    val executor = Executors.newSingleThreadExecutor()
    executor.execute {
      val printers = mutableListOf<Map<String, Any>>()
      val handler = object : DiscoveryHandler {
        override fun foundPrinter(printer: DiscoveredPrinter) {
          if (printer is DiscoveredPrinterUsb) {
            val info = mutableMapOf<String, Any>()
            val device = printer.device

            info["address"] = printer.address
            info["vendorId"] = device.vendorId
            info["productId"] = device.productId
            info["deviceName"] = device.deviceName
            info["serialNumber"] = device.serialNumber ?: ""
            info["manufacturerName"] = device.manufacturerName ?: ""
            info["deviceId"] = device.deviceId
            info["deviceClass"] = device.deviceClass
            info["deviceProtocol"] = device.deviceProtocol
            info["deviceSubclass"] = device.deviceSubclass
            info["interfaceCount"] = device.interfaceCount
            info["dnsName"] = device.manufacturerName ?: device.deviceName

            printers.add(info)
          }
        }

        override fun discoveryFinished() {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.success(printers)
          }
        }

        override fun discoveryError(message: String) {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.error("DISCOVERY_ERROR", message, null)
          }
        }
      }

      try {
        UsbDiscoverer.findPrinters(applicationContext, handler)
      } catch (e: Exception) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
          result.error("DISCOVERY_EXCEPTION", e.message, null)
        }
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    // Hủy đăng ký broadcast receiver
    try {
      applicationContext.unregisterReceiver(usbReceiver)
    } catch (e: Exception) {
      // Ignore errors when unregistering
    }
  }
}
