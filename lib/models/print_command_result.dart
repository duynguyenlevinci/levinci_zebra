class PrintCommandErrorCode {
  PrintCommandErrorCode._();

  /// Thiếu tham số bắt buộc (ipAddress, port, command, deviceAddress).
  static const invalidArgument = 'INVALID_ARGUMENT';

  /// Không thể tạo kết nối tới máy in.
  static const failedToCreateConnection = 'FAILED_TO_CREATE_CONNECTION';

  /// Không thể mở kết nối tới máy in.
  static const failedToOpenConnection = 'FAILED_TO_OPEN_CONNECTION';

  /// Không thể xóa buffer máy in (~JA).
  static const failedToClearBuffer = 'FAILED_TO_CLEAR_BUFFER';

  /// Không lấy được instance máy in từ SDK.
  static const failedToGetPrinter = 'FAILED_TO_GET_PRINTER';

  /// Ghi lệnh in thất bại.
  static const failedToSendCommand = 'FAILED_TO_SEND_COMMAND';

  /// Lỗi kết nối / ghi dữ liệu (Android TCP/USB).
  static const connectionError = 'CONNECTION_ERROR';

  /// Không có quyền truy cập USB device (Android).
  static const permissionDenied = 'PERMISSION_DENIED';

  /// Không tìm thấy máy in USB (Android).
  static const printerNotFound = 'PRINTER_NOT_FOUND';

  /// Lỗi discovery USB (Android).
  static const discoveryError = 'DISCOVERY_ERROR';

  /// Hết thời gian chờ (iOS send / Android USB discovery).
  static const timeout = 'TIMEOUT';

  /// Lỗi không xác định.
  static const unexpectedError = 'UNEXPECTED_ERROR';
}

class PrintCommandResult {
  final bool success;
  final String? errorCode;
  final String? errorMessage;

  const PrintCommandResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });

  factory PrintCommandResult.success() {
    return const PrintCommandResult(success: true);
  }

  factory PrintCommandResult.failure({
    required String errorCode,
    required String errorMessage,
  }) {
    return PrintCommandResult(
      success: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  factory PrintCommandResult.fromMap(Map<String, dynamic> map) {
    return PrintCommandResult(
      success: map['success'] == true,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'success': success,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  @override
  String toString() {
    if (success) return 'PrintCommandResult(success: true)';
    return 'PrintCommandResult(success: false, errorCode: $errorCode, errorMessage: $errorMessage)';
  }
}
