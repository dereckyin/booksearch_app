// 庫存查詢（對齊 MIS H111100R 精簡版）

int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _asStr(dynamic v) => v == null ? '' : '$v'.trim();

class StockLocationItem {
  const StockLocationItem({
    required this.rkId,
    required this.logcode,
    required this.qty,
    required this.prodNm,
    this.prodId = '',
    this.orgProdId = '',
    this.orgFlg = '',
    this.eancode = '',
    this.coverProdId = '',
  });

  final String rkId;
  final String logcode;
  final int qty;
  final String prodNm;
  final String prodId;
  final String orgProdId;
  final String orgFlg;
  final String eancode;
  final String coverProdId;

  /// 二手書用母店內碼；後端會回 cover_prod_id
  String get coverId {
    if (coverProdId.isNotEmpty) return coverProdId;
    // 二手（C）只用 org_prod_id，不用自身 prod_id（常是暫無圖片）
    if (orgFlg.toUpperCase() == 'C') {
      return orgProdId;
    }
    if (orgProdId.isNotEmpty) return orgProdId;
    return prodId;
  }

  String? get coverUrl {
    final id = coverId;
    if (id.isEmpty) return null;
    return 'https://media.taaze.tw/showLargeImage.html?sc=$id&height=170&width=250';
  }

  factory StockLocationItem.fromJson(Map<String, dynamic> j) =>
      StockLocationItem(
        rkId: _asStr(j['rk_id']),
        logcode: _asStr(j['logcode']),
        qty: _asInt(j['qty']),
        prodNm: _asStr(j['prod_nm']),
        prodId: _asStr(j['prod_id']),
        orgProdId: _asStr(j['org_prod_id']),
        orgFlg: _asStr(j['org_flg']),
        eancode: _asStr(j['eancode']),
        coverProdId: _asStr(j['cover_prod_id']),
      );
}

/// 同一儲位的庫存列（列表以儲位為主）
class StockLocationGroup {
  StockLocationGroup({
    required this.rkId,
    required this.items,
  });

  final String rkId;
  final List<StockLocationItem> items;

  int get totalQty => items.fold<int>(0, (s, e) => s + e.qty);

  int get lineCount => items.length;

  String get title {
    final names = items
        .map((e) => e.prodNm)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return '（無商品名稱）';
    if (names.length == 1) return names.first;
    return '${names.first} 等 ${names.length} 種';
  }

  String? get coverUrl {
    // 同組優先有 coverId 的；二手會是母店內碼
    for (final e in items) {
      final u = e.coverUrl;
      if (u != null) return u;
    }
    return null;
  }

  static List<StockLocationGroup> groupByRack(List<StockLocationItem> items) {
    final map = <String, List<StockLocationItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.rkId, () => []).add(item);
    }
    final keys = map.keys.toList()..sort();
    return [
      for (final k in keys)
        StockLocationGroup(rkId: k, items: List.unmodifiable(map[k]!)),
    ];
  }
}

class StockQueryResult {
  const StockQueryResult({
    required this.items,
    required this.truncated,
  });

  final List<StockLocationItem> items;
  final bool truncated;

  factory StockQueryResult.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => StockLocationItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <StockLocationItem>[];
    return StockQueryResult(
      items: list,
      truncated: j['truncated'] == true,
    );
  }
}
