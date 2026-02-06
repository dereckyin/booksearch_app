/// 登入成功後回傳的使用者資訊（揀貨單手機端開發指南 §2.1）
class AuthUser {
  AuthUser({required this.phone, this.name});

  final String phone;
  final String? name;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      phone: '${json['phone'] ?? ''}',
      name: json['name'] != null ? '${json['name']}' : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'phone': phone,
        if (name != null) 'name': name,
      };

  String get displayName => (name != null && name!.isNotEmpty) ? name! : phone;
}

/// 登入 API 成功回應（POST /api/v1/picking-lists/login）
class LoginResponse {
  LoginResponse({
    required this.success,
    required this.token,
    required this.user,
  });

  final bool success;
  final String token;
  final AuthUser user;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      success: json['success'] == true,
      token: '${json['token'] ?? ''}',
      user: AuthUser.fromJson(
        json['user'] is Map<String, dynamic>
            ? json['user'] as Map<String, dynamic>
            : {},
      ),
    );
  }
}
