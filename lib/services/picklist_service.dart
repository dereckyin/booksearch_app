import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/pick_list_main.dart';
import '../models/pick_list_item.dart';
import '../models/picker_info.dart';

/// Service to fetch pick-list items from backend API.
class PickListService {
  PickListService({
    ApiConfig? config,
    http.Client? client,
  })  : _config = config ?? ApiConfig(),
        _client = client ?? http.Client();

  final ApiConfig _config;
  final http.Client _client;

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

  Future<List<PickListMain>> fetchPickListMain({
    required String employeeId,
  }) async {
    final mainUri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/main',
    ).replace(
      queryParameters: {
        'employeeNo': employeeId,
      },
    );

    final mainResp = await _client.get(mainUri);
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

  Future<List<PickListItem>> fetchItemsBySdNo({
    required String employeeId,
    required String sdNo,
    PickListMain? main,
  }) async {
    final itemUri = Uri.parse(
      '${_config.uploadBase}/api/v1/picking-lists/items/test',
    ).replace(
      queryParameters: {
        'employeeNo': employeeId,
        'sd_no': sdNo,
      },
    );

    final itemResp = await _client.get(itemUri);
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

