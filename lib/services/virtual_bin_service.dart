import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/virtual_bin.dart';

/// 虛擬櫃位分貨 API（/api/v1/virtual-bins）
class VirtualBinService {
  VirtualBinService({
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

  String get _base => '${_config.uploadBase}/api/v1/virtual-bins';

  Map<String, String> _headers({bool jsonBody = false}) {
    final map = <String, String>{};
    if (jsonBody) map['Content-Type'] = 'application/json';
    if (token != null && token!.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  void _checkUnauthorized(http.Response resp) {
    if (resp.statusCode == 401) onUnauthorized?.call();
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

  /// GET /batches
  Future<List<VirtualBinBatchSummary>> fetchBatches({int limit = 100}) async {
    final uri = Uri.parse('$_base/batches').replace(
      queryParameters: {'limit': '$limit'},
    );
    final resp = await _client.get(uri, headers: _headers());
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_detailMessage(resp));
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => VirtualBinBatchSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET /batches/{sd_no}
  Future<VirtualBinBatchDetail> fetchBatch(String sdNo) async {
    final uri = Uri.parse('$_base/batches/${Uri.encodeComponent(sdNo)}');
    final resp = await _client.get(uri, headers: _headers());
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_detailMessage(resp));
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return VirtualBinBatchDetail.fromJson(json);
  }

  /// GET /batches/{sd_no}/bins/{kit_no}
  Future<VirtualBinDetail> fetchBin(String sdNo, String kitNo) async {
    final uri = Uri.parse(
      '$_base/batches/${Uri.encodeComponent(sdNo)}/bins/${Uri.encodeComponent(kitNo)}',
    );
    final resp = await _client.get(uri, headers: _headers());
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_detailMessage(resp));
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return VirtualBinDetail.fromJson(json);
  }

  /// POST /batches/{sd_no}/scan
  Future<VirtualBinScanResult> scan(String sdNo, String barcode) async {
    final uri = Uri.parse(
      '$_base/batches/${Uri.encodeComponent(sdNo)}/scan',
    );
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode({'barcode': barcode}),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['detail'] is Map) {
          final d = Map<String, dynamic>.from(decoded['detail'] as Map);
          throw VirtualBinScanException(
            message: '${d['message'] ?? _detailMessage(resp)}',
            barcode: '${d['barcode'] ?? barcode}',
            displayKit: '${d['display_kit'] ?? d['kit_no'] ?? '?'}',
          );
        }
      } catch (e) {
        if (e is VirtualBinScanException) rethrow;
      }
      throw Exception(_detailMessage(resp));
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return VirtualBinScanResult.fromJson(json);
  }

  /// POST /batches/{sd_no}/reset — 清除模擬進度
  Future<void> resetProgress(String sdNo) async {
    final uri = Uri.parse(
      '$_base/batches/${Uri.encodeComponent(sdNo)}/reset',
    );
    final resp = await _client.post(uri, headers: _headers());
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_detailMessage(resp));
    }
  }

  /// POST /batches/{sd_no}/shortage — 標記／取消缺書
  Future<void> setShortage(String sdNo, {required bool shortage}) async {
    final uri = Uri.parse(
      '$_base/batches/${Uri.encodeComponent(sdNo)}/shortage',
    );
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode({'shortage': shortage}),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_detailMessage(resp));
    }
  }
}
