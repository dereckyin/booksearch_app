/// lock_status 由 GET /main 帶 token 時回傳（揀貨單手機端開發指南 §4.1）
/// available / locked_by_me / locked_by_other
enum PickFlowTabStatus {
  unpicked,
  picking,
  pickedDone,
  readyToSort,
}

class PickListMain {
  PickListMain({
    required this.sdNo,
    this.whId,
    this.statusFlg,
    this.pickStage,
    this.lockStatus,
    this.area,
    this.lockedByPhone,
    this.lockedByName,
    this.finishedBy,
    this.finishedByName,
    this.finishedAt,
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
  /// Server-side stage for grouping tabs (e.g. picked_done_pending_qc).
  final String? pickStage;
  final String? lockStatus;
  final String? area;
  final String? lockedByPhone;
  final String? lockedByName;
  final String? finishedBy;
  final String? finishedByName;
  final DateTime? finishedAt;
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
  static const Map<String, String> channelCategoryLabels = {
    '7': '超商',
    'F': '超商',
    'L': '超商',
    'K': '超商',
    'SPE': '蝦皮',
    'SPH': '蝦皮',
    'H': '宅配',
    'CAT': '宅配',
    'P': '宅配',
    'S': '宅配',
    'KHK': '宅配',
    'BHK': '宅配',
    'CHK': '宅配',
  };
  static const Map<String, String> channelLabels = {
    '7': '7-11',
    'F': '全家',
    'L': '萊爾富',
    'K': 'OK',
    'SPE': '店到店',
    'SPH': '隔日到貨',
    'H': '大榮',
    'CAT': '黑貓',
    'P': '郵局',
    'S': '海外',
    'KHK': '香港OK',
    'BHK': '香港OK',
    'CHK': '香港OK',
  };
  static const Map<String, String> mallCompanyLabels = {
    'TAZ': '讀冊',
    'RTN': '露天',
    'FRI': '遠傳',
    'IRD': '灰熊',
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
  String? get channelCategoryText => _labelUpper(cnno, channelCategoryLabels);
  String? get channelText => _labelUpper(cnno, channelLabels);
  String? get channelDisplayText {
    final category = channelCategoryText;
    final channel = channelText ?? _normalizeCode(cnno);
    if (category == null && channel == null) return null;
    if (category != null && channel != null) return '$category（$channel）';
    return category ?? channel;
  }
  String? get mallText => _labelUpper(companyId, mallCompanyLabels);
  String? get mallDisplayText {
    final mall = mallText ?? _normalizeCode(companyId);
    if (mall == null) return null;
    return '商城（$mall）';
  }
  String get normalizedLockStatus => (lockStatus ?? '').trim().toLowerCase();
  String get normalizedPickStage => (pickStage ?? '').trim().toLowerCase();
  String get normalizedStatusFlg => (statusFlg ?? '').trim().toUpperCase();
  bool get isOrderDone => normalizedStatusFlg == 'Y';
  bool get isPickedDoneStage =>
      normalizedPickStage == 'picked_done_pending_qc' ||
      normalizedPickStage == 'qc_done';
  bool get isReadyToSortStage => normalizedPickStage == 'qc_done';
  bool get isPickingStage => normalizedPickStage == 'picking';
  bool get isNotStartedStage => normalizedPickStage == 'not_started';
  bool get isPicking =>
      normalizedLockStatus == 'locked_by_me' ||
      normalizedLockStatus == 'locked_by_other';
  bool get isAvailableToPick => normalizedLockStatus == 'available';
  String? get pickerDisplayName {
    final finishedName = finishedByName?.trim();
    if (finishedName != null && finishedName.isNotEmpty) return finishedName;
    final finishedAccount = finishedBy?.trim();
    if (finishedAccount != null && finishedAccount.isNotEmpty) {
      return finishedAccount;
    }
    final name = lockedByName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phone = lockedByPhone?.trim();
    if (phone != null && phone.isNotEmpty) return phone;
    return null;
  }
  PickFlowTabStatus get flowTabStatus {
    if (isReadyToSortStage) return PickFlowTabStatus.readyToSort;
    if (isPickedDoneStage) return PickFlowTabStatus.pickedDone;
    if (isPickingStage) return PickFlowTabStatus.picking;
    if (isNotStartedStage) return PickFlowTabStatus.unpicked;
    if (isPicking) return PickFlowTabStatus.picking;
    return PickFlowTabStatus.unpicked;
  }
  String get flowTabLabel {
    switch (flowTabStatus) {
      case PickFlowTabStatus.unpicked:
        return '未撿貨';
      case PickFlowTabStatus.picking:
        return '撿貨中';
      case PickFlowTabStatus.pickedDone:
        return '撿貨完';
      case PickFlowTabStatus.readyToSort:
        return '可分貨';
    }
  }
  bool get isUnfinishedForBadge =>
      flowTabStatus == PickFlowTabStatus.unpicked ||
      flowTabStatus == PickFlowTabStatus.picking;
  String get orderStatusDisplay => statusText ?? statusFlg ?? '-';
  String get lockStatusDisplay {
    if (flowTabStatus == PickFlowTabStatus.pickedDone ||
        flowTabStatus == PickFlowTabStatus.readyToSort) {
      final picker = pickerDisplayName;
      return picker == null ? '已撿貨完成' : '$picker 已撿貨完成';
    }
    switch (normalizedLockStatus) {
      case 'available':
        return '可領取';
      case 'locked_by_me':
        return '我撿貨中';
      case 'locked_by_other':
        final picker = pickerDisplayName;
        return picker == null ? '他人撿貨中' : '$picker 撿貨中';
      default:
        return lockStatus?.isNotEmpty == true ? lockStatus! : '';
    }
  }
  String? get spSingleText => _label(spSingleFlg, spSingleLabels);
  String? get fragileText => _label(ctFragileFlg, boolLabels);
  String? get gmText => _label(ctGmFlg, boolLabels);
  String? get airbagText => _label(useAirbagFlg, useAirbagLabels);
  String? get repackageText => _label(repackageFlg, boolLabels);
  String? get pkAreaText => _label(pkAreaFlg, pkAreaLabels);

  factory PickListMain.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final text = value.toString();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    num? parseNum(dynamic value) {
      if (value == null || value.toString().isEmpty) return null;
      return num.tryParse(value.toString());
    }

    final sdNo = '${json['sd_no'] ?? json['sdNo'] ?? json['sdno'] ?? json['id'] ?? ''}';
    return PickListMain(
      sdNo: sdNo,
      whId: _asString(json['wh_id']),
      statusFlg: _asString(json['status_flg']),
      pickStage: _asString(json['pick_stage'] ?? json['pickStage']),
      lockStatus: _asString(json['lock_status'] ?? json['lockStatus']),
      area: _asString(json['area']),
      lockedByPhone: _asString(json['locked_by_phone']),
      lockedByName: _asString(json['locked_by_name']),
      finishedBy: _asString(json['finished_by'] ?? json['finishedBy']),
      finishedByName: _asString(
        json['finished_by_name'] ?? json['finishedByName'],
      ),
      finishedAt: parseDate(json['finished_at'] ?? json['finishedAt']),
      companyId: _asString(json['company_id']),
      deliver: _asString(json['deliver']),
      cnno: _asString(json['cnno']),
      spSingleFlg: _asString(json['sp_single_flg']),
      ctFragileFlg: _asString(json['ct_fragile_flg']),
      ctGmFlg: _asString(json['ct_gm_flg']),
      useAirbagFlg: _asString(json['use_airbag_flg']),
      repackageFlg: _asString(json['repackage_flg']),
      ttlMustQty: parseNum(json['ttl_must_qty']),
      spCnt: parseNum(json['sp_cnt']),
      ttlMustPQty: parseNum(json['ttl_must_p_qty']),
      ttlMustEQty: parseNum(json['ttl_must_e_qty']),
      pkAreaFlg: _asString(json['pk_area_flg']),
      aPageCnt: parseNum(json['a_page_cnt']),
      bPageCnt: parseNum(json['b_page_cnt']),
      ttlPageCnt: parseNum(json['ttl_page_cnt']),
      crtTime: parseDate(json['crt_time']),
      mdfTime: parseDate(json['mdf_time']),
      prtTime: parseDate(json['prt_time']),
      finTime: parseDate(json['fin_time']),
      delTime: parseDate(json['del_time']),
      prtCnt: parseNum(json['prt_cnt']),
      spDspsFlg: _asString(json['sp_dsps_flg']),
      spDspsTime: parseDate(json['sp_dsps_time']),
      exportFlg: _asString(json['export_flg']),
      exportTime: parseDate(json['export_time']),
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

String? _labelUpper(String? code, Map<String, String> map) {
  final normalized = _normalizeCode(code);
  if (normalized == null) return null;
  return map[normalized] ?? normalized;
}

String? _normalizeCode(String? code) {
  if (code == null) return null;
  final normalized = code.trim().toUpperCase();
  return normalized.isEmpty ? null : normalized;
}
