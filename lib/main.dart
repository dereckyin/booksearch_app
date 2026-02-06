import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/auth_user.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_storage.dart';
import 'services/picklist_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  await AuthStorage.ensureInitialized();

  runApp(const BookSearchApp());
}

class BookSearchApp extends StatelessWidget {
  const BookSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '讀冊揀貨單',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// 依 token 決定顯示登入頁或首頁（揀貨單手機端開發指南：401 時清除 token 導回登入）
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authStorage = AuthStorage();
  final _service = PickListService();
  String? _token;
  AuthUser? _user;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _loadStoredAuth();
  }

  Future<void> _loadStoredAuth() async {
    var token = await _authStorage.getToken();
    var user = await _authStorage.getUser();

    // 無有效 token 時，若有儲存的帳密則嘗試自動登入
    if (token == null || token.isEmpty) {
      final credentials = await _authStorage.getCredentials();
      if (credentials != null) {
        try {
          final response = await _service.login(
            phone: credentials.phone,
            password: credentials.password,
          );
          if (response.success && response.token.isNotEmpty) {
            await _authStorage.saveToken(response.token);
            await _authStorage.saveUser(response.user);
            token = response.token;
            user = response.user;
          }
        } catch (_) {
          // 自動登入失敗（例如密碼已改、網路錯誤），清除儲存帳密，稍後顯示登入頁
          await _authStorage.clear();
          token = null;
          user = null;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _token = token;
      _user = user;
      _checked = true;
    });
  }

  void _onLoginSuccess(String token, AuthUser user) {
    setState(() {
      _token = token;
      _user = user;
    });
  }

  Future<void> _onLogout() async {
    await _authStorage.clear();
    if (!mounted) return;
    setState(() {
      _token = null;
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_token == null || _token!.isEmpty) {
      _service.token = null;
      _service.onUnauthorized = null;
      return LoginScreen(
        service: _service,
        authStorage: _authStorage,
        onSuccess: _onLoginSuccess,
      );
    }
    _service.token = _token;
    _service.onUnauthorized = () async {
      await _onLogout();
    };
    return HomeShell(
      token: _token!,
      user: _user,
      pickListService: _service,
      onLogout: _onLogout,
    );
  }
}
