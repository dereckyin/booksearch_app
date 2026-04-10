class CannotPickReport {
  CannotPickReport({
    required this.id,
    required this.sdNo,
    required this.prodId,
    required this.rkId,
    required this.reason,
    this.logcode,
    this.qty,
    this.remark,
    required this.reportedAt,
    this.reportedByName,
    this.reportedByPhone,
    this.title,
    this.imageUrl,
    this.handlingResult,
    this.correctLogcode,
    this.abnormalResult,
    this.abnormalRemark,
    this.abnormalUpdatedAt,
    this.abnormalUpdatedBy,
  });

  final int id;
  final String sdNo;
  final String prodId;
  final String rkId;
  final String reason;
  final String? logcode;
  final num? qty;
  final String? remark;
  final DateTime reportedAt;
  final String? reportedByName;
  final String? reportedByPhone;
  final String? title;
  final String? imageUrl;
  final String? handlingResult;
  final String? correctLogcode;
  final String? abnormalResult;
  final String? abnormalRemark;
  final DateTime? abnormalUpdatedAt;
  final String? abnormalUpdatedBy;

  factory CannotPickReport.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      return int.tryParse(value.toString()) ?? fallback;
    }

    final sdNo = '${json['sd_no'] ?? json['sdNo'] ?? ''}'.trim();
    final prodId = '${json['prod_id'] ?? json['prodId'] ?? ''}'.trim();
    final rkId = '${json['rk_id'] ?? json['rkId'] ?? ''}'.trim();
    final reason = '${json['reason'] ?? ''}'.trim();
    final logcodeRaw = '${json['logcode'] ?? json['log_code'] ?? ''}'.trim();
    num? parseNum(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      return num.tryParse(text);
    }
    final qty = parseNum(
      json['must_qty'] ??
          json['qty'] ??
          json['quantity'] ??
          json['ttl_must_qty'],
    );
    final remarkRaw = '${json['remark'] ?? ''}'.trim();
    final reportedAtRaw = json['reported_at'] ?? json['reportedAt'];
    final reportedAt = DateTime.tryParse('${reportedAtRaw ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final byName = '${json['reported_by_name'] ?? json['reportedByName'] ?? ''}'
        .trim();
    final byPhone =
        '${json['reported_by_phone'] ?? json['reportedByPhone'] ?? ''}'.trim();

    final title = '${json['title'] ?? ''}'.trim();
    final imageUrl = '${json['image_url'] ?? json['imageUrl'] ?? ''}'.trim();
    final handlingResultRaw =
        '${json['handling_result'] ?? json['handlingResult'] ?? ''}'.trim();
    final correctLogcodeRaw =
        '${json['correct_logcode'] ?? json['correctLogcode'] ?? ''}'.trim();
    final abnormalResultRaw =
        '${json['abnormal_result'] ?? json['abnormalResult'] ?? ''}'.trim();
    final abnormalRemarkRaw =
        '${json['abnormal_remark'] ?? json['abnormalRemark'] ?? ''}'.trim();
    final abnormalUpdatedAtRaw =
        json['abnormal_updated_at'] ?? json['abnormalUpdatedAt'];
    final abnormalUpdatedAt = DateTime.tryParse('${abnormalUpdatedAtRaw ?? ''}');
    final abnormalUpdatedByRaw =
        '${json['abnormal_updated_by'] ?? json['abnormalUpdatedBy'] ?? ''}'
            .trim();

    return CannotPickReport(
      id: parseInt(json['id']),
      sdNo: sdNo,
      prodId: prodId,
      rkId: rkId,
      reason: reason,
      logcode: logcodeRaw.isEmpty ? null : logcodeRaw,
      qty: qty,
      remark: remarkRaw.isEmpty ? null : remarkRaw,
      reportedAt: reportedAt,
      reportedByName: byName.isEmpty ? null : byName,
      reportedByPhone: byPhone.isEmpty ? null : byPhone,
      title: title.isEmpty ? null : title,
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      handlingResult: handlingResultRaw.isEmpty ? null : handlingResultRaw,
      correctLogcode: correctLogcodeRaw.isEmpty ? null : correctLogcodeRaw,
      abnormalResult: abnormalResultRaw.isEmpty ? null : abnormalResultRaw,
      abnormalRemark: abnormalRemarkRaw.isEmpty ? null : abnormalRemarkRaw,
      abnormalUpdatedAt: abnormalUpdatedAt,
      abnormalUpdatedBy:
          abnormalUpdatedByRaw.isEmpty ? null : abnormalUpdatedByRaw,
    );
  }
}

