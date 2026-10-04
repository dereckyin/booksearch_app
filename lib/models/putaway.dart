// 新品上架（對齊 MIS C121100M 進貨上架作業）

int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _asStr(dynamic v) => v == null ? '' : '$v';

/// 待上架新品驗收單（NEW_IQC_MAIN SU_FLG='W'）
class PutawayPendingIqc {
  const PutawayPendingIqc({
    required this.iqcNo,
    required this.supNm,
    required this.ttlIqcQty,
    required this.lineCnt,
    required this.iqcFinTime,
  });

  final String iqcNo;
  final String supNm;
  final int ttlIqcQty;
  final int lineCnt;
  final String iqcFinTime;

  factory PutawayPendingIqc.fromJson(Map<String, dynamic> j) => PutawayPendingIqc(
        iqcNo: _asStr(j['iqc_no']),
        supNm: _asStr(j['sup_nm']),
        ttlIqcQty: _asInt(j['ttl_iqc_qty']),
        lineCnt: _asInt(j['line_cnt']),
        iqcFinTime: _asStr(j['iqc_fin_time']),
      );
}

/// 上架單主檔（NEW_PUR_SU_MAIN）
class PutawaySuSummary {
  const PutawaySuSummary({
    required this.suNo,
    required this.statusFlg,
    required this.ttlMustQty,
    required this.ttlRealQty,
    required this.ttlDifQty,
    required this.crtUser,
    required this.crtTime,
    required this.finUser,
    required this.chkFlg,
    required this.iqcNoList,
    required this.rkIdList,
    required this.note,
  });

  final String suNo;
  final String statusFlg;
  final int ttlMustQty;
  final int ttlRealQty;
  final int ttlDifQty;
  final String crtUser;
  final String crtTime;
  final String finUser;
  final String chkFlg;
  final String iqcNoList;
  final String rkIdList;
  final String note;

  bool get isOpen => statusFlg == 'N';

  String get statusLabel {
    switch (statusFlg) {
      case 'N':
        return '上架中';
      case 'Y':
        return chkFlg == 'Y' ? '已審核入庫' : '待審核';
      case 'D':
        return '已作廢';
      default:
        return statusFlg;
    }
  }

  factory PutawaySuSummary.fromJson(Map<String, dynamic> j) => PutawaySuSummary(
        suNo: _asStr(j['su_no']),
        statusFlg: _asStr(j['status_flg']),
        ttlMustQty: _asInt(j['ttl_must_qty']),
        ttlRealQty: _asInt(j['ttl_real_qty']),
        ttlDifQty: _asInt(j['ttl_dif_qty']),
        crtUser: _asStr(j['crt_user']),
        crtTime: _asStr(j['crt_time']),
        finUser: _asStr(j['fin_user']),
        chkFlg: _asStr(j['chk_flg']),
        iqcNoList: _asStr(j['iqc_no_list']),
        rkIdList: _asStr(j['rk_id_list']),
        note: _asStr(j['note']),
      );
}

/// 應上架彙總（NEW_PUR_SU_SUM）
class PutawaySumLine {
  const PutawaySumLine({
    required this.pitem,
    required this.prodId,
    required this.logcode,
    required this.prodNm,
    required this.orgFlg,
    required this.fragileFlg,
    required this.iqcNo,
    required this.mustQty,
    required this.realQty,
  });

  final int pitem;
  final String prodId;
  final String logcode;
  final String prodNm;
  final String orgFlg;
  final String fragileFlg;
  final String iqcNo;
  final int mustQty;
  final int realQty;

  int get difQty => realQty - mustQty;
  int get remainQty => mustQty - realQty > 0 ? mustQty - realQty : 0;

  factory PutawaySumLine.fromJson(Map<String, dynamic> j) => PutawaySumLine(
        pitem: _asInt(j['pitem']),
        prodId: _asStr(j['prod_id']),
        logcode: _asStr(j['logcode']),
        prodNm: _asStr(j['prod_nm']),
        orgFlg: _asStr(j['org_flg']),
        fragileFlg: _asStr(j['fragile_flg']),
        iqcNo: _asStr(j['iqc_no']),
        mustQty: _asInt(j['must_qty']),
        realQty: _asInt(j['real_qty']),
      );
}

/// 儲位上架明細（NEW_PUR_SU_DETAIL）
class PutawayDetailLine {
  const PutawayDetailLine({
    required this.rkId,
    required this.prodId,
    required this.logcode,
    required this.prodNm,
    required this.realQty,
  });

  final String rkId;
  final String prodId;
  final String logcode;
  final String prodNm;
  final int realQty;

  factory PutawayDetailLine.fromJson(Map<String, dynamic> j) => PutawayDetailLine(
        rkId: _asStr(j['rk_id']),
        prodId: _asStr(j['prod_id']),
        logcode: _asStr(j['logcode']),
        prodNm: _asStr(j['prod_nm']),
        realQty: _asInt(j['real_qty']),
      );
}

class PutawaySuDetail {
  const PutawaySuDetail({
    required this.main,
    required this.editable,
    required this.iqcNos,
    required this.sums,
    required this.details,
  });

  final PutawaySuSummary main;
  final bool editable;
  final List<String> iqcNos;
  final List<PutawaySumLine> sums;
  final List<PutawayDetailLine> details;

  factory PutawaySuDetail.fromJson(Map<String, dynamic> j) => PutawaySuDetail(
        main: PutawaySuSummary.fromJson(j),
        editable: j['editable'] == true,
        iqcNos: (j['iqc_nos'] as List? ?? const []).map((e) => '$e').toList(),
        sums: (j['sums'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PutawaySumLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        details: (j['details'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PutawayDetailLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class PutawayScanResult {
  const PutawayScanResult({
    required this.rkId,
    required this.logcode,
    required this.prodNm,
    required this.rackQty,
    required this.mustQty,
    required this.realQty,
    required this.over,
    required this.message,
  });

  final String rkId;
  final String logcode;
  final String prodNm;
  final int rackQty;
  final int mustQty;
  final int realQty;
  final bool over;
  final String message;

  factory PutawayScanResult.fromJson(Map<String, dynamic> j) => PutawayScanResult(
        rkId: _asStr(j['rk_id']),
        logcode: _asStr(j['logcode']),
        prodNm: _asStr(j['prod_nm']),
        rackQty: _asInt(j['rack_qty']),
        mustQty: _asInt(j['must_qty']),
        realQty: _asInt(j['real_qty']),
        over: j['over'] == true,
        message: _asStr(j['message']),
      );
}

class PutawayClash {
  const PutawayClash({
    required this.clashFlg,
    required this.rkId,
    required this.prodNm,
    required this.logcode,
    required this.clashLogcode,
    required this.clashProdNm,
  });

  final String clashFlg;
  final String rkId;
  final String prodNm;
  final String logcode;
  final String clashLogcode;
  final String clashProdNm;

  factory PutawayClash.fromJson(Map<String, dynamic> j) => PutawayClash(
        clashFlg: _asStr(j['clash_flg']),
        rkId: _asStr(j['rk_id']),
        prodNm: _asStr(j['prod_nm']),
        logcode: _asStr(j['logcode']),
        clashLogcode: _asStr(j['clash_logcode']),
        clashProdNm: _asStr(j['clash_prod_nm']),
      );
}

/// 完成上架被擋（blocked）或需確認（need_confirm）
class PutawayFinishException implements Exception {
  PutawayFinishException({
    required this.message,
    required this.blocked,
    required this.needConfirm,
    this.blockers = const [],
    this.warnings = const [],
    this.clashes = const [],
  });

  final String message;
  final bool blocked;
  final bool needConfirm;
  final List<String> blockers;
  final List<String> warnings;
  final List<PutawayClash> clashes;

  factory PutawayFinishException.fromDetail(Map<String, dynamic> d) =>
      PutawayFinishException(
        message: _asStr(d['message']),
        blocked: d['blocked'] == true,
        needConfirm: d['need_confirm'] == true,
        blockers: (d['blockers'] as List? ?? const []).map((e) => '$e').toList(),
        warnings: (d['warnings'] as List? ?? const []).map((e) => '$e').toList(),
        clashes: (d['clashes'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PutawayClash.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  @override
  String toString() => message;
}
