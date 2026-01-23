import 'dart:io';

class ApiConfig {
  ApiConfig();

  static const String _env =
      String.fromEnvironment('APP_ENV', defaultValue: 'testing');

  bool get isTesting => _env.toLowerCase() == 'production';
  bool get isProduction => !isTesting;

  /// Upload API base URL differs by environment.
  String get uploadBase {
    if (isProduction) return 'https://apiport.taaze.tw';
    // Emulator要打到本機，改用10.0.2.2
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://192.168.0.229:8000';
  }

  String get uploadPhotoUrl => '$uploadBase/api/v1/upload/photo';
}
