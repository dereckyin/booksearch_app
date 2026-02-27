class CannotPickReport {
  CannotPickReport({
    required this.sdNo,
    required this.prodId,
    required this.rkId,
    required this.reason,
    this.remark,
    required this.reportedAt,
    this.reportedByName,
    this.reportedByPhone,
    this.title,
    this.imageUrl,
  });

  final String sdNo;
  final String prodId;
  final String rkId;
  final String reason;
  final String? remark;
  final DateTime reportedAt;
  final String? reportedByName;
  final String? reportedByPhone;
  final String? title;
  final String? imageUrl;

  factory CannotPickReport.fromJson(Map<String, dynamic> json) {
    final sdNo = '${json['sd_no'] ?? json['sdNo'] ?? ''}'.trim();
    final prodId = '${json['prod_id'] ?? json['prodId'] ?? ''}'.trim();
    final rkId = '${json['rk_id'] ?? json['rkId'] ?? ''}'.trim();
    final reason = '${json['reason'] ?? ''}'.trim();
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

    return CannotPickReport(
      sdNo: sdNo,
      prodId: prodId,
      rkId: rkId,
      reason: reason,
      remark: remarkRaw.isEmpty ? null : remarkRaw,
      reportedAt: reportedAt,
      reportedByName: byName.isEmpty ? null : byName,
      reportedByPhone: byPhone.isEmpty ? null : byPhone,
      title: title.isEmpty ? null : title,
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
    );
  }
}

