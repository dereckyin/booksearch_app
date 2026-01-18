class ApiConfig {
  ApiConfig();

  static const String _env =
      String.fromEnvironment('APP_ENV', defaultValue: 'testing');

  bool get isTesting => _env.toLowerCase() == 'testing';
  bool get isProduction => !isTesting;

  /// Upload API base URL differs by environment.
  String get uploadBase =>
      isTesting ? 'http://192.168.0.229:8000' : 'https://apiport.taaze.tw';

  String get uploadPhotoUrl => '$uploadBase/api/v1/upload/photo';
}
