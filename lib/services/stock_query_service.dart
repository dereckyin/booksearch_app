import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/stock_query.dart';

/// 庫存查詢 API（/api/v1/stock）
class StockQueryService {
  StockQueryService({
    ApiConfig? config,
    http.Client? client,
    this.token,
    this.onUnauthorized,
  })  : _config = config ?? ApiConfig(),
        _client = client ?? http.Client();

  final ApiConfig _config;
  final http.Client _client;

  /// JWT，與揀貨單登入共用
  String? token;

  void Function()? onUnauthorized;

  String get _base => '${_config.uploadBase}/api/v1/stock';

  Map<String, String> _headers() {
    final map = <String, String>{};
    if (token != null && token!.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  String _detailMessage(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is Map) {
          final msg = detail['message'];
          if (msg != null) return msg.toString();
          return detail.toString();
        }
        if (detail != null) return detail.toString();
      }
    } catch (_) {}
    return resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
  }

  /// GET /locations
  Future<StockQueryResult> queryLocations({
    String? rkRowFrom,
    String? rkRowTo,
    String? rkIdFrom,
    String? rkIdTo,
    String? logcode,
  }) async {
    final q = <String, String>{};
    void put(String key, String? v) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) q[key] = t;
    }

    put('rk_row_from', rkRowFrom);
    put('rk_row_to', rkRowTo);
    put('rk_id_from', rkIdFrom);
    put('rk_id_to', rkIdTo);
    put('logcode', logcode);

    final uri = Uri.parse('$_base/locations').replace(queryParameters: q);
    final resp = await _client.get(uri, headers: _headers());
    if (resp.statusCode == 401) onUnauthorized?.call();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StockQueryApiException(
        _detailMessage(resp),
        statusCode: resp.statusCode,
      );
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      return const StockQueryResult(items: [], truncated: false);
    }
    return StockQueryResult.fromJson(Map<String, dynamic>.from(decoded));
  }
}

class StockQueryApiException implements Exception {
  StockQueryApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
