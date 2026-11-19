// 庫存查詢（對齊 MIS H111100R 精簡版）

int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _asStr(dynamic v) => v == null ? '' : '$v';

class StockLocationItem {
  const StockLocationItem({
    required this.rkId,
    required this.logcode,
    required this.qty,
    required this.prodNm,
  });

  final String rkId;
  final String logcode;
  final int qty;
  final String prodNm;

  factory StockLocationItem.fromJson(Map<String, dynamic> j) =>
      StockLocationItem(
        rkId: _asStr(j['rk_id']),
        logcode: _asStr(j['logcode']),
        qty: _asInt(j['qty']),
        prodNm: _asStr(j['prod_nm']),
      );
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
