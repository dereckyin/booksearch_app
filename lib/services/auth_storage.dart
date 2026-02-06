import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';

/// 儲存／讀取 JWT 與使用者資訊（揀貨單手機端開發指南：token 存本地，401 時清除）
class AuthStorage {
  AuthStorage({SharedPreferences? prefs})
      : _prefs = prefs ?? _pendingPrefs;

  static SharedPreferences? _pendingPrefs;

  static Future<void> ensureInitialized() async {
    _pendingPrefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _storage async {
    if (_prefs != null) return _prefs!;
    await ensureInitialized();
    _prefs = _pendingPrefs;
    if (_prefs == null) throw StateError('SharedPreferences not initialized');
    return _prefs!;
  }

  static const _keyToken = 'picking_lists_auth_token';
  static const _keyUserPhone = 'picking_lists_user_phone';
  static const _keyUserName = 'picking_lists_user_name';
  static const _keySavedPhone = 'picking_lists_saved_phone';
  static const _keySavedPassword = 'picking_lists_saved_password';

  Future<String?> getToken() async {
    final prefs = await _storage;
    return prefs.getString(_keyToken);
  }

  Future<void> saveToken(String token) async {
    final prefs = await _storage;
    await prefs.setString(_keyToken, token);
  }

  Future<AuthUser?> getUser() async {
    final prefs = await _storage;
    final phone = prefs.getString(_keyUserPhone);
    if (phone == null || phone.isEmpty) return null;
    return AuthUser(
      phone: phone,
      name: prefs.getString(_keyUserName),
    );
  }

  Future<void> saveUser(AuthUser user) async {
    final prefs = await _storage;
    await prefs.setString(_keyUserPhone, user.phone);
    if (user.name != null) {
      await prefs.setString(_keyUserName, user.name!);
    } else {
      await prefs.remove(_keyUserName);
    }
  }

  /// 登入成功後儲存 phone、password，供下次啟動自動登入
  Future<void> saveCredentials(String phone, String password) async {
    final prefs = await _storage;
    await prefs.setString(_keySavedPhone, phone);
    await prefs.setString(_keySavedPassword, password);
  }

  /// 讀取已儲存的登入資訊（登出時會清除）
  Future<({String phone, String password})?> getCredentials() async {
    final prefs = await _storage;
    final phone = prefs.getString(_keySavedPhone);
    final password = prefs.getString(_keySavedPassword);
    if (phone == null || phone.isEmpty || password == null || password.isEmpty) {
      return null;
    }
    return (phone: phone, password: password);
  }

  /// 登出或 401 時清除 token、使用者與儲存的帳密
  Future<void> clear() async {
    final prefs = await _storage;
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserPhone);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keySavedPhone);
    await prefs.remove(_keySavedPassword);
  }
}
