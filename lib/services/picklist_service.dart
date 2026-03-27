import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_user.dart';
import '../models/pick_list_main.dart';
import '../models/pick_list_item.dart';
import '../models/picker_info.dart';
import '../models/cannot_pick_report.dart';

/// Service for pick-list API（揀貨單手機端開發指南）.
/// 需登入的 API 請先設定 [token]；收到 401 時會呼叫 [onUnauthorized]。
class PickListService {
  PickListService({
    ApiConfig? config,
    http.Client? client,
    this.token,
    this.onUnauthorized,
  })  : _config = config ?? ApiConfig(),
        _client = client ?? http.Client();

  final ApiConfig _config;
  final http.Client _client;

  /// JWT，登入後設定；所有需認證的請求會帶 Authorization: Bearer [token]
  String? token;

  /// 收到 401 時呼叫（清除 token 並導回登入）
  void Function()? onUnauthorized;

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

  /// 登入：POST /api/v1/picking-lists/login
  Future<LoginResponse> login({
    required String phone,
    required String password,
  }) async {
    final uri = Uri.parse('${_config.uploadBase}/api/v1/picking-lists/login');
    final body = jsonEncode({'phone': phone, 'password': password});
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: body,
    );
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return LoginResponse.fromJson(json);
    }
    if (resp.statusCode == 401) {
      final json = jsonDecode(resp.body);
      final detail = json is Map ? (json['detail'] ?? resp.body) : resp.body;
      throw Exception(detail is String ? detail : detail.toString());
    }
    throw Exception('登入失敗 ${resp.statusCode}: ${resp.body}');
  }

  /// 與後端 `prior_open_days` 對齊：1 表示納入前一日起尚未結案（未撿／撿貨中），0 僅今日開放單。
  static const int kDefaultPriorOpenDays = 1;

  /// 揀貨主檔摘要（免 token）：GET /api/v1/picking-lists/main/summary
  Future<MainSummary> getSummary({int priorOpenDays = kDefaultPriorOpenDays}) async {
    final uri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/main/summary',
    ).replace(
      queryParameters: {
        'prior_open_days': '$priorOpenDays',
      },
    );
    final resp = await _client.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Summary API ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return MainSummary(
      totalSheets: (json['total_sheets'] is num)
          ? (json['total_sheets'] as num).toInt()
          : 0,
      totalEntries: (json['total_entries'] is num)
          ? (json['total_entries'] as num).toInt()
          : 0,
    );
  }

  /// 我今日已領／已完成（需 token）：GET /api/v1/picking-lists/my-today
  Future<MyTodayResponse> getMyToday() async {
    final uri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/my-today',
    );
    final resp = await _client.get(uri, headers: _headers());
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('My-today API ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = json['locked_list'];
    final lockedList = list is List
        ? list
            .whereType<Map<String, dynamic>>()
            .map((e) => LockedEntry(
                  sdNo: '${e['sd_no'] ?? e['sdNo'] ?? ''}',
                  lockedAt: e['locked_at'] is num
                      ? (e['locked_at'] as num).toInt()
                      : 0,
                ))
            .toList()
        : <LockedEntry>[];
    return MyTodayResponse(
      lockedCount: (json['locked_count'] is num)
          ? (json['locked_count'] as num).toInt()
          : 0,
      completedCount: (json['completed_count'] is num)
          ? (json['completed_count'] as num).toInt()
          : 0,
      lockedList: lockedList,
    );
  }

  /// 領取此單（鎖定）：POST /api/v1/picking-lists/lock
  Future<void> lock(String sdNo) async {
    final uri = Uri.parse('${_config.uploadBase}/api/v1/picking-lists/lock');
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode({'sd_no': sdNo}),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode == 200) return;
    if (resp.statusCode == 409) {
      final json = jsonDecode(resp.body);
      final detail = json is Map ? json['detail'] : resp.body;
      throw Exception(
        detail is String ? detail : '此單已被他人領取',
      );
    }
    throw Exception('Lock API ${resp.statusCode}: ${resp.body}');
  }

  /// 完成並釋放（解鎖）：POST /api/v1/picking-lists/unlock
  Future<void> unlock(String sdNo) async {
    final uri = Uri.parse('${_config.uploadBase}/api/v1/picking-lists/unlock');
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode({'sd_no': sdNo}),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode == 200) return;
    if (resp.statusCode == 403) {
      throw Exception('此單由他人揀選中，您無法釋放');
    }
    throw Exception('Unlock API ${resp.statusCode}: ${resp.body}');
  }

  /// 完成至待驗收（撿貨完並釋放）：POST /api/v1/picking-lists/finish-to-qc
  ///
  /// **後端開發規格**
  /// - 路徑：POST /api/v1/picking-lists/finish-to-qc
  /// - Header：Authorization: Bearer {token}、Content-Type: application/json
  /// - Body：{ "sd_no": "1234567890123(A)" }
  /// - 行為：
  ///   - 驗證此單存在
  ///   - 驗證呼叫者持有 lock（lock_status == locked_by_me），否則 403
  ///   - 將 pick_stage 設為 picked_done_pending_qc
  ///   - 釋放 lock（讓列表不再顯示為撿貨中）
  /// - 成功 (200)：{ "success": true, "sd_no": "...", "pick_stage": "picked_done_pending_qc" }
  /// - 失敗：401/403/404/409 依既有慣例回傳
  Future<void> finishToQc(String sdNo) async {
    final uri =
        Uri.parse('${_config.uploadBase}/api/v1/picking-lists/finish-to-qc');
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode({'sd_no': sdNo}),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    if (resp.statusCode == 403) {
      throw Exception('此單由他人揀選中，您無法完成');
    }
    throw Exception('Finish-to-qc API ${resp.statusCode}: ${resp.body}');
  }

  /// 揀不到回報：POST /api/v1/picking-lists/cannot-pick
  Future<void> reportCannotPick({
    required String sdNo,
    required String prodId,
    required String rkId,
    required String reason,
    String? remark,
  }) async {
    final uri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/cannot-pick',
    );
    final body = <String, dynamic>{
      'sd_no': sdNo,
      'prod_id': prodId,
      'rk_id': rkId,
      'reason': reason,
    };
    if (remark != null && remark.isNotEmpty) body['remark'] = remark;
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode(body),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception('揀不到回報失敗 ${resp.statusCode}: ${resp.body}');
  }

  /// 今日揀不到清單（集中頁簽用）：GET /api/v1/picking-lists/cannot-pick/today
  ///
  /// **後端開發規格**
  /// - 路徑：GET /api/v1/picking-lists/cannot-pick/today
  /// - Header：Authorization: Bearer {token}
  /// - Query（建議，可選）：
  ///   - date=YYYY-MM-DD（預設後端伺服器「今天」）
  ///   - scope=all|mine（本需求：all）
  /// - 行為：
  ///   - 回傳「今天」所有撿貨員的 cannot-pick 回報（需要權限控管請後端處理）
  /// - 成功 (200)：回傳 JSON Array，每筆至少包含：
  ///   - sd_no, prod_id, rk_id, reason, remark?, reported_at
  ///   - reported_by_name?, reported_by_phone?
  ///   - title?, image_url?（可選，若後端方便可一起帶）
  Future<List<CannotPickReport>> fetchCannotPickToday({
    bool all = true,
    String? date,
  }) async {
    final uri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/cannot-pick/today',
    ).replace(
      queryParameters: {
        'scope': all ? 'all' : 'mine',
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final resp = await _client.get(uri, headers: _headers());
    _checkUnauthorized(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Cannot-pick today API ${resp.statusCode}: ${resp.body}');
    }
    final body = jsonDecode(resp.body);
    if (body is! List) {
      throw Exception('Cannot-pick today unexpected response format');
    }
    return body
        .whereType<Map<String, dynamic>>()
        .map(CannotPickReport.fromJson)
        .toList();
  }

  /// 櫃位現場圖評分（feedback）：POST /api/v1/picking-lists/shelf-feedback
  ///
  /// **後端開發規格**
  /// - 路徑：POST /api/v1/picking-lists/shelf-feedback
  /// - Header：Authorization: Bearer {token}、Content-Type: application/json
  /// - Body：{ "sd_no": "1234567890123(A)", "prod_id": "xxx", "rk_id": "櫃號", "rank": 5 }
  ///   - sd_no：揀貨單號（含區別）
  ///   - prod_id：商品／品項 ID
  ///   - rk_id：櫃號
  ///   - rank：評分 1～5（整數，5 為最滿意）
  /// - 成功 (200)：{ "success": true } 或 { "success": true, "message": "..." }
  /// - 失敗：4xx/5xx 依既有慣例回傳
  Future<void> submitShelfFeedback({
    required String sdNo,
    required String prodId,
    required String rkId,
    required int rank,
  }) async {
    final uri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/shelf-feedback',
    );
    final body = <String, dynamic>{
      'sd_no': sdNo,
      'prod_id': prodId,
      'rk_id': rkId,
      'rank': rank.clamp(1, 5),
    };
    final resp = await _client.post(
      uri,
      headers: _headers(jsonBody: true),
      body: jsonEncode(body),
    );
    _checkUnauthorized(resp);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception('櫃位評分送出失敗 ${resp.statusCode}: ${resp.body}');
  }

  Future<List<PickerInfo>> fetchPickersToday() async {
    final uri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/pickers/today',
    );
    final resp = await _client.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Pickers API ${resp.statusCode}: ${resp.body}');
    }
    final body = jsonDecode(resp.body);
    if (body is! List) {
      throw Exception('Pickers API unexpected response format');
    }
    return body.map(PickerInfo.fromJson).toList();
  }

  /// 列表：GET /api/v1/picking-lists/main（建議帶 token 以取得 lock_status）
  Future<List<PickListMain>> fetchPickListMain({
    String? employeeId,
    int priorOpenDays = kDefaultPriorOpenDays,
  }) async {
    final qp = <String, String>{
      'prior_open_days': '$priorOpenDays',
    };
    if (employeeId != null && employeeId.isNotEmpty) {
      qp['employeeNo'] = employeeId;
    }
    final mainUri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/main',
    ).replace(queryParameters: qp);

    final mainResp = await _client.get(mainUri, headers: _headers());
    _checkUnauthorized(mainResp);
    if (mainResp.statusCode < 200 || mainResp.statusCode >= 300) {
      throw Exception('Main API ${mainResp.statusCode}: ${mainResp.body}');
    }

    final mainBody = jsonDecode(mainResp.body);
    final mainList = _asList(mainBody, 'Main API');

    final mainRecords = mainList
        .whereType<Map<String, dynamic>>()
        .map(PickListMain.fromJson)
        .where((m) => m.sdNo.isNotEmpty)
        .toList();

    return mainRecords;
  }

  /// 品項：GET /api/v1/picking-lists/items/test
  Future<List<PickListItem>> fetchItemsBySdNo({
    String? employeeId,
    required String sdNo,
    PickListMain? main,
  }) async {
    final params = <String, String>{'sd_no': sdNo};
    if (employeeId != null && employeeId.isNotEmpty) {
      params['employeeNo'] = employeeId;
    }
    final itemUri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/items/test',
    ).replace(queryParameters: params);

    final itemResp = await _client.get(itemUri, headers: _headers());
    _checkUnauthorized(itemResp);
    if (itemResp.statusCode < 200 || itemResp.statusCode >= 300) {
      throw Exception('Items $sdNo API ${itemResp.statusCode}: ${itemResp.body}');
    }

    final itemBody = jsonDecode(itemResp.body);
    final itemList = _asList(itemBody, 'Items $sdNo');

    final items = itemList.whereType<Map<String, dynamic>>().map(
      (e) => PickListItem.fromJson(
        {...e, 'sdNo': sdNo},
        main: main,
      ),
    );

    return items.toList();
  }

  List<dynamic> _asList(dynamic body, String context) {
    if (body is List) return body;
    if (body is Map<String, dynamic>) {
      const candidates = ['data', 'items', 'list', 'results', 'records', 'content'];
      for (final key in candidates) {
        final v = body[key];
        if (v is List) return v;
        if (v is Map && v['items'] is List) return v['items'] as List;
      }
      // fallback: first list value in map
      for (final v in body.values) {
        if (v is List) return v;
      }
      throw Exception('$context unexpected response format (keys: ${body.keys.join(', ')})');
    }
    throw Exception('$context unexpected response type: ${body.runtimeType}');
  }
}

/// 揀貨單總量摘要（GET /main/summary，與列表相同 prior_open_days）
class MainSummary {
  MainSummary({required this.totalSheets, required this.totalEntries});
  final int totalSheets;
  final int totalEntries;
}

/// 我今日已領／已完成（GET /my-today）
class MyTodayResponse {
  MyTodayResponse({
    required this.lockedCount,
    required this.completedCount,
    required this.lockedList,
  });
  final int lockedCount;
  final int completedCount;
  final List<LockedEntry> lockedList;
}

class LockedEntry {
  LockedEntry({required this.sdNo, required this.lockedAt});
  final String sdNo;
  final int lockedAt;
}

