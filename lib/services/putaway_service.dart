import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/putaway.dart';

/// 新品上架 API（/api/v1/putaway）
class PutawayService {
  PutawayService({
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

  String get _base => '${_config.uploadBase}/api/v1/putaway';

  Map<String, String> _headers({bool jsonBody = false}) {
    final map = <String, String>{};
    if (jsonBody) map['Content-Type'] = 'application/json';
    if (token != null && token!.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  Map<String, dynamic>? _detailMap(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['detail'] is Map) {
        return Map<String, dynamic>.from(decoded['detail'] as Map);
      }
    } catch (_) {}
    return null;
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

  Map<String, dynamic> _ok(http.Response resp) {
    if (resp.statusCode == 401) onUnauthorized?.call();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PutawayApiException(_detailMessage(resp), statusCode: resp.statusCode);
    }
    final decoded = jsonDecode(resp.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  Uri _su(String suNo, [String action = '']) => Uri.parse(
        '$_base/su/${Uri.encodeComponent(suNo)}${action.isEmpty ? '' : '/$action'}',
      );

  Future<http.Response> _post(Uri uri, [Map<String, dynamic>? body]) => _client.post(
        uri,
        headers: _headers(jsonBody: true),
        body: jsonEncode(body ?? const {}),
      );

  /// GET /pending-iqc
  Future<List<PutawayPendingIqc>> fetchPendingIqc() async {
    final resp = await _client.get(Uri.parse('$_base/pending-iqc'), headers: _headers());
    if (resp.statusCode == 401) onUnauthorized?.call();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PutawayApiException(_detailMessage(resp), statusCode: resp.statusCode);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => PutawayPendingIqc.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET /su?status=N|Y|D&days=
  Future<List<PutawaySuSummary>> fetchSuList({String status = 'N', int days = 1}) async {
    final uri = Uri.parse('$_base/su').replace(
      queryParameters: {'status': status, 'days': '$days'},
    );
    final resp = await _client.get(uri, headers: _headers());
    if (resp.statusCode == 401) onUnauthorized?.call();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PutawayApiException(_detailMessage(resp), statusCode: resp.statusCode);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => PutawaySuSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// POST /su — 選驗收單建立上架單
  Future<PutawaySuDetail> createSu(List<String> iqcNos) async {
    final resp = await _post(Uri.parse('$_base/su'), {'iqc_nos': iqcNos});
    return PutawaySuDetail.fromJson(_ok(resp));
  }

  /// GET /su/{su_no}
  Future<PutawaySuDetail> fetchSu(String suNo) async {
    final resp = await _client.get(_su(suNo), headers: _headers());
    return PutawaySuDetail.fromJson(_ok(resp));
  }

  /// POST /su/{su_no}/rack — 驗證儲位，回傳該儲位已上架量
  Future<int> checkRack(String suNo, String rkId) async {
    final resp = await _post(_su(suNo, 'rack'), {'rk_id': rkId});
    final j = _ok(resp);
    final v = j['real_qty'];
    return v is num ? v.toInt() : 0;
  }

  /// POST /su/{su_no}/scan
  Future<PutawayScanResult> scan(String suNo, String rkId, String barcode) async {
    final resp = await _post(_su(suNo, 'scan'), {'rk_id': rkId, 'barcode': barcode});
    return PutawayScanResult.fromJson(_ok(resp));
  }

  /// POST /su/{su_no}/adjust — 修改某儲位某條碼上架量（0 = 刪除）
  Future<void> adjust(String suNo, String rkId, String logcode, int qty) async {
    final resp = await _post(
      _su(suNo, 'adjust'),
      {'rk_id': rkId, 'logcode': logcode, 'qty': qty},
    );
    _ok(resp);
  }

  /// POST /su/{su_no}/finish — 完成上架（STATUS_FLG='Y'、CHK_FLG='W'）
  /// 被擋或需確認時丟 [PutawayFinishException]。
  Future<String> finish(String suNo, {bool force = false}) async {
    final resp = await _post(_su(suNo, 'finish'), {'force': force});
    if (resp.statusCode == 409) {
      final d = _detailMap(resp);
      if (d != null && (d['blocked'] == true || d['need_confirm'] == true)) {
        throw PutawayFinishException.fromDetail(d);
      }
    }
    final j = _ok(resp);
    return '${j['message'] ?? '已完成上架'}';
  }

  /// POST /su/{su_no}/revoke — 作廢並釋放驗收單
  Future<String> revoke(String suNo) async {
    final resp = await _post(_su(suNo, 'revoke'));
    final j = _ok(resp);
    return '${j['message'] ?? '已作廢'}';
  }
}

class PutawayApiException implements Exception {
  PutawayApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
