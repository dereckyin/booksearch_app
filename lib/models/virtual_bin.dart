/// 可分貨批號摘要（GET /virtual-bins/batches）
class VirtualBinBatchSummary {
  VirtualBinBatchSummary({
    required this.sdNo,
    this.statusFlg,
    this.exportFlg,
    this.pickFlg,
    this.cnno,
    this.spCnt = 0,
    this.ttlMustQty = 0,
    this.kitCnt = 0,
    this.mustQty = 0,
    this.gotQty = 0,
    this.batchCompleted = false,
    this.hasShortage = false,
    this.displayStatus = 'pending',
    this.crtTime,
  });

  final String sdNo;
  final String? statusFlg;
  final String? exportFlg;
  final String? pickFlg;
  final String? cnno;
  final int spCnt;
  final int ttlMustQty;
  final int kitCnt;
  final int mustQty;
  final int gotQty;
  final bool batchCompleted;
  final bool hasShortage;
  /// pending / in_progress / completed / shortage
  final String displayStatus;
  final String? crtTime;

  factory VirtualBinBatchSummary.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return VirtualBinBatchSummary(
      sdNo: '${json['sd_no'] ?? ''}',
      statusFlg: json['status_flg']?.toString(),
      exportFlg: json['export_flg']?.toString(),
      pickFlg: json['pick_flg']?.toString(),
      cnno: json['cnno']?.toString(),
      spCnt: asInt(json['sp_cnt']),
      ttlMustQty: asInt(json['ttl_must_qty']),
      kitCnt: asInt(json['kit_cnt']),
      mustQty: asInt(json['must_qty']),
      gotQty: asInt(json['got_qty']),
      batchCompleted: json['batch_completed'] == true,
      hasShortage: json['has_shortage'] == true,
      displayStatus: '${json['display_status'] ?? 'pending'}',
      crtTime: json['crt_time']?.toString(),
    );
  }
}

/// 格位色板一格（Y待完成／G已完成／N未開放）
class VirtualBinKitSlot {
  VirtualBinKitSlot({
    required this.slot,
    required this.kitNo,
    this.displayKit = '',
    this.runningFlg = 'N',
  });

  final int slot;
  final String kitNo;
  final String displayKit;
  /// Y=待完成（橘／黃）、G=已完成（綠）、N=未開放（灰）
  final String runningFlg;

  factory VirtualBinKitSlot.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return VirtualBinKitSlot(
      slot: asInt(json['slot']),
      kitNo: '${json['kit_no'] ?? ''}',
      displayKit: '${json['display_kit'] ?? json['kit_no'] ?? ''}',
      runningFlg: '${json['running_flg'] ?? 'N'}',
    );
  }
}

/// 單一虛擬櫃位進度
class VirtualBinProgress {
  VirtualBinProgress({
    required this.kitNo,
    this.displayKit = '',
    this.runningFlg = 'N',
    this.lineCnt = 0,
    this.mustQty = 0,
    this.gotQty = 0,
    this.remainQty = 0,
    this.binCompleted = false,
    this.ordNo = '',
    this.spNo = '',
    this.invNo = '',
    this.rcvNm = '',
  });

  final String kitNo;
  final String displayKit;
  final String runningFlg;
  final int lineCnt;
  final int mustQty;
  final int gotQty;
  final int remainQty;
  final bool binCompleted;
  final String ordNo;
  final String spNo;
  final String invNo;
  final String rcvNm;

  factory VirtualBinProgress.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return VirtualBinProgress(
      kitNo: '${json['kit_no'] ?? ''}',
      displayKit: '${json['display_kit'] ?? json['kit_no'] ?? ''}',
      runningFlg: '${json['running_flg'] ?? 'N'}',
      lineCnt: asInt(json['line_cnt']),
      mustQty: asInt(json['must_qty']),
      gotQty: asInt(json['got_qty']),
      remainQty: asInt(json['remain_qty']),
      binCompleted: json['bin_completed'] == true,
      ordNo: '${json['ord_no'] ?? ''}',
      spNo: '${json['sp_no'] ?? ''}',
      invNo: '${json['inv_no'] ?? ''}',
      rcvNm: '${json['rcv_nm'] ?? ''}',
    );
  }
}

/// 批號＋全部櫃位進度（GET /batches/{sd_no}）
class VirtualBinBatchDetail {
  VirtualBinBatchDetail({
    required this.sdNo,
    this.kitCnt = 0,
    this.mustQty = 0,
    this.gotQty = 0,
    this.remainQty = 0,
    this.difQty = 0,
    this.batchCompleted = false,
    this.hasShortage = false,
    this.bins = const [],
    this.kitBoard = const [],
  });

  final String sdNo;
  final int kitCnt;
  final int mustQty;
  final int gotQty;
  final int remainQty;
  final int difQty;
  final bool batchCompleted;
  final bool hasShortage;
  final List<VirtualBinProgress> bins;
  final List<VirtualBinKitSlot> kitBoard;

  factory VirtualBinBatchDetail.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final list = json['bins'];
    final bins = list is List
        ? list
            .whereType<Map>()
            .map((e) => VirtualBinProgress.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <VirtualBinProgress>[];
    final board = json['kit_board'];
    final kitBoard = board is List
        ? board
            .whereType<Map>()
            .map((e) => VirtualBinKitSlot.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <VirtualBinKitSlot>[];
    return VirtualBinBatchDetail(
      sdNo: '${json['sd_no'] ?? ''}',
      kitCnt: asInt(json['kit_cnt']),
      mustQty: asInt(json['must_qty']),
      gotQty: asInt(json['got_qty']),
      remainQty: asInt(json['remain_qty']),
      difQty: asInt(json['dif_qty']),
      batchCompleted: json['batch_completed'] == true,
      hasShortage: json['has_shortage'] == true,
      bins: bins,
      kitBoard: kitBoard,
    );
  }
}

/// 櫃內明細列
class VirtualBinLine {
  VirtualBinLine({
    required this.kitNo,
    required this.invNo,
    required this.barNo,
    this.spNo = '',
    this.proNo = '',
    this.prodNm = '',
    this.spQty = 0,
    this.scannedQty = 0,
    this.remain = 0,
    this.scanProdFlag = 'Y',
  });

  final String kitNo;
  final String invNo;
  final String barNo;
  final String spNo;
  final String proNo;
  final String prodNm;
  final int spQty;
  final int scannedQty;
  final int remain;
  final String scanProdFlag;

  bool get mustScan => scanProdFlag.toUpperCase() == 'Y';

  factory VirtualBinLine.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return VirtualBinLine(
      kitNo: '${json['kit_no'] ?? ''}',
      invNo: '${json['inv_no'] ?? ''}',
      barNo: '${json['bar_no'] ?? ''}',
      spNo: '${json['sp_no'] ?? ''}',
      proNo: '${json['pro_no'] ?? ''}',
      prodNm: '${json['prod_nm'] ?? ''}',
      spQty: asInt(json['sp_qty']),
      scannedQty: asInt(json['scanned_qty']),
      remain: asInt(json['remain']),
      scanProdFlag: '${json['scan_prod_flag'] ?? 'Y'}',
    );
  }
}

/// 單一櫃位完整明細（GET .../bins/{kit_no}）
class VirtualBinDetail {
  VirtualBinDetail({
    required this.sdNo,
    required this.kitNo,
    this.displayKit = '',
    this.mustQty = 0,
    this.gotQty = 0,
    this.remainQty = 0,
    this.binCompleted = false,
    this.ordNo = '',
    this.spNo = '',
    this.lines = const [],
    this.missing = const [],
  });

  final String sdNo;
  final String kitNo;
  final String displayKit;
  final int mustQty;
  final int gotQty;
  final int remainQty;
  final bool binCompleted;
  final String ordNo;
  final String spNo;
  final List<VirtualBinLine> lines;
  final List<VirtualBinLine> missing;

  factory VirtualBinDetail.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<VirtualBinLine> parseLines(dynamic list) {
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => VirtualBinLine.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return VirtualBinDetail(
      sdNo: '${json['sd_no'] ?? ''}',
      kitNo: '${json['kit_no'] ?? ''}',
      displayKit: '${json['display_kit'] ?? json['kit_no'] ?? ''}',
      mustQty: asInt(json['must_qty']),
      gotQty: asInt(json['got_qty']),
      remainQty: asInt(json['remain_qty']),
      binCompleted: json['bin_completed'] == true,
      ordNo: '${json['ord_no'] ?? ''}',
      spNo: '${json['sp_no'] ?? ''}',
      lines: parseLines(json['lines']),
      missing: parseLines(json['missing']),
    );
  }
}

/// 掃碼回應（POST .../scan）
class VirtualBinScanResult {
  VirtualBinScanResult({
    required this.sdNo,
    required this.kitNo,
    this.displayKit = '',
    this.invNo = '',
    this.ordNo = '',
    this.spNo = '',
    this.barNo = '',
    this.prodNm = '',
    this.spQty = 0,
    this.scannedQty = 0,
    this.remain = 0,
    this.binCompleted = false,
    this.batchCompleted = false,
    this.hasShortage = false,
    this.message = '',
    this.kitBoard = const [],
  });

  final String sdNo;
  final String kitNo;
  final String displayKit;
  final String invNo;
  final String ordNo;
  final String spNo;
  final String barNo;
  final String prodNm;
  final int spQty;
  final int scannedQty;
  final int remain;
  final bool binCompleted;
  final bool batchCompleted;
  final bool hasShortage;
  final String message;
  final List<VirtualBinKitSlot> kitBoard;

  factory VirtualBinScanResult.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final board = json['kit_board'];
    final kitBoard = board is List
        ? board
            .whereType<Map>()
            .map((e) => VirtualBinKitSlot.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <VirtualBinKitSlot>[];
    return VirtualBinScanResult(
      sdNo: '${json['sd_no'] ?? ''}',
      kitNo: '${json['kit_no'] ?? ''}',
      displayKit: '${json['display_kit'] ?? json['kit_no'] ?? ''}',
      invNo: '${json['inv_no'] ?? ''}',
      ordNo: '${json['ord_no'] ?? ''}',
      spNo: '${json['sp_no'] ?? ''}',
      barNo: '${json['bar_no'] ?? ''}',
      prodNm: '${json['prod_nm'] ?? ''}',
      spQty: asInt(json['sp_qty']),
      scannedQty: asInt(json['scanned_qty']),
      remain: asInt(json['remain']),
      binCompleted: json['bin_completed'] == true,
      batchCompleted: json['batch_completed'] == true,
      hasShortage: json['has_shortage'] == true,
      message: '${json['message'] ?? ''}',
      kitBoard: kitBoard,
    );
  }
}

/// 掃碼失敗（對齊 E123「未發現相符合之待分貨商品」）
class VirtualBinScanException implements Exception {
  VirtualBinScanException({
    required this.message,
    this.barcode = '',
    this.displayKit = '?',
  });

  final String message;
  final String barcode;
  final String displayKit;

  @override
  String toString() => message;
}
