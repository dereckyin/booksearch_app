class PickListMain {
  PickListMain({
    required this.sdNo,
    this.whId,
    this.statusFlg,
    this.companyId,
    this.deliver,
    this.cnno,
    this.spSingleFlg,
    this.ctFragileFlg,
    this.ctGmFlg,
    this.useAirbagFlg,
    this.repackageFlg,
    this.ttlMustQty,
    this.spCnt,
    this.ttlMustPQty,
    this.ttlMustEQty,
    this.pkAreaFlg,
    this.aPageCnt,
    this.bPageCnt,
    this.ttlPageCnt,
    this.crtTime,
    this.mdfTime,
    this.prtTime,
    this.finTime,
    this.delTime,
    this.prtCnt,
    this.spDspsFlg,
    this.spDspsTime,
    this.exportFlg,
    this.exportTime,
    this.qcFlg,
    this.selFlg,
  });

  final String sdNo;
  final String? whId;
  final String? statusFlg;
  final String? companyId;
  final String? deliver;
  final String? cnno;
  final String? spSingleFlg;
  final String? ctFragileFlg;
  final String? ctGmFlg;
  final String? useAirbagFlg;
  final String? repackageFlg;
  final num? ttlMustQty;
  final num? spCnt;
  final num? ttlMustPQty;
  final num? ttlMustEQty;
  final String? pkAreaFlg;
  final num? aPageCnt;
  final num? bPageCnt;
  final num? ttlPageCnt;
  final DateTime? crtTime;
  final DateTime? mdfTime;
  final DateTime? prtTime;
  final DateTime? finTime;
  final DateTime? delTime;
  final num? prtCnt;
  final String? spDspsFlg;
  final DateTime? spDspsTime;
  final String? exportFlg;
  final DateTime? exportTime;
  final String? qcFlg;
  final String? selFlg;

  // Value-to-label helpers (keep original Chinese descriptions)
  static const Map<String, String> statusLabels = {
    'N': '未完成',
    'Y': '已完成',
    'D': '已作廢',
  };
  static const Map<String, String> deliverLabels = {
    'A': '超商(台)',
    'B': '宅配(台)',
    'S': '海外(宅)',
    'L': '海外(盟)',
    'C': '讀冊',
    'G': '團購',
    'D': '下載',
  };
  static const Map<String, String> cnnoLabels = {
    'A': '合併超商',
    'F': '全家',
    'K': '台灣 OK',
    'L': '萊爾富',
    '7': '7-11',
    'H': '大榮',
    'P': '郵局',
    'N': '速配',
    'SF': '順豐',
    'PB': '掌櫃',
    'S': '海外(宅)',
    'C': '讀冊',
    'G': '團購',
    'D': '下載',
    'KHK': '香港 OK',
    'BHK': '香港櫃取',
    'CHK': '香港定點',
  };
  static const Map<String, String> spSingleLabels = {
    'A': '單品單本',
    'B': '單品多本',
    'C': '多品多本',
  };
  static const Map<String, String> boolLabels = {
    'N': '未含/不使用',
    'Y': '內含/可使用',
  };
  static const Map<String, String> useAirbagLabels = {
    'N': '不使用',
    'Y': '可使用',
  };
  static const Map<String, String> pkAreaLabels = {
    'AA': '僅A區',
    'AB': 'A、B區',
    'BB': '僅B區',
    'XX': '不分區',
  };

  String? get statusText => _label(statusFlg, statusLabels);
  String? get deliverText => _label(deliver, deliverLabels);
  String? get cnnoText => _label(cnno, cnnoLabels);
  String? get spSingleText => _label(spSingleFlg, spSingleLabels);
  String? get fragileText => _label(ctFragileFlg, boolLabels);
  String? get gmText => _label(ctGmFlg, boolLabels);
  String? get airbagText => _label(useAirbagFlg, useAirbagLabels);
  String? get repackageText => _label(repackageFlg, boolLabels);
  String? get pkAreaText => _label(pkAreaFlg, pkAreaLabels);

  factory PickListMain.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final text = value.toString();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    num? _parseNum(dynamic value) {
      if (value == null || value.toString().isEmpty) return null;
      return num.tryParse(value.toString());
    }

    final sdNo = '${json['sd_no'] ?? json['sdNo'] ?? json['sdno'] ?? json['id'] ?? ''}';
    return PickListMain(
      sdNo: sdNo,
      whId: _asString(json['wh_id']),
      statusFlg: _asString(json['status_flg']),
      companyId: _asString(json['company_id']),
      deliver: _asString(json['deliver']),
      cnno: _asString(json['cnno']),
      spSingleFlg: _asString(json['sp_single_flg']),
      ctFragileFlg: _asString(json['ct_fragile_flg']),
      ctGmFlg: _asString(json['ct_gm_flg']),
      useAirbagFlg: _asString(json['use_airbag_flg']),
      repackageFlg: _asString(json['repackage_flg']),
      ttlMustQty: _parseNum(json['ttl_must_qty']),
      spCnt: _parseNum(json['sp_cnt']),
      ttlMustPQty: _parseNum(json['ttl_must_p_qty']),
      ttlMustEQty: _parseNum(json['ttl_must_e_qty']),
      pkAreaFlg: _asString(json['pk_area_flg']),
      aPageCnt: _parseNum(json['a_page_cnt']),
      bPageCnt: _parseNum(json['b_page_cnt']),
      ttlPageCnt: _parseNum(json['ttl_page_cnt']),
      crtTime: _parseDate(json['crt_time']),
      mdfTime: _parseDate(json['mdf_time']),
      prtTime: _parseDate(json['prt_time']),
      finTime: _parseDate(json['fin_time']),
      delTime: _parseDate(json['del_time']),
      prtCnt: _parseNum(json['prt_cnt']),
      spDspsFlg: _asString(json['sp_dsps_flg']),
      spDspsTime: _parseDate(json['sp_dsps_time']),
      exportFlg: _asString(json['export_flg']),
      exportTime: _parseDate(json['export_time']),
      qcFlg: _asString(json['qc_flg']),
      selFlg: _asString(json['sel_flg']),
    );
  }
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

String? _label(String? code, Map<String, String> map) {
  if (code == null || code.isEmpty) return null;
  return map[code] ?? code;
}
