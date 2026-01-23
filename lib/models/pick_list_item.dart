import 'pick_list_main.dart';

class PickListItem {
  PickListItem({
    required this.id,
    required this.productId,
    required this.title,
    required this.imageUrl,
    this.titleMain,
    this.rkId,
    this.orgProdId,
    this.logcode,
    this.mustQty,
    this.overlayDataUrl,
    this.overlayUrl,
    this.seqNum,
    this.sdNo,
    this.main,
  });

  final String id;
  final String productId;
  final String title;
  final String imageUrl;
  final String? titleMain;
  final String? rkId;
  final String? orgProdId;
  final String? logcode;
  final num? mustQty;
  final String? overlayDataUrl;
  final String? overlayUrl;
  final String? seqNum;
  final String? sdNo;
  final PickListMain? main;

  factory PickListItem.fromJson(
    Map<String, dynamic> json, {
    PickListMain? main,
  }) {
    num? _parseNum(dynamic value) {
      if (value == null) return null;
      final text = value.toString();
      if (text.isEmpty) return null;
      return num.tryParse(text);
    }

    final sdNo = '${json['sdNo'] ?? json['sd_no'] ?? ''}';
    final rkId = '${json['rkId'] ?? json['rk_id'] ?? ''}';
    final orgProdId = '${json['orgProdId'] ?? json['org_prod_id'] ?? ''}';
    final titleMain = '${json['title_main'] ?? ''}';
    final logcode = '${json['logcode'] ?? json['log_code'] ?? ''}';
    final mustQty = _parseNum(json['must_qty'] ?? json['mustQty']);
    String overlayDataUrl = '${json['overlay_data_url'] ?? ''}'.trim();
    String overlayUrl = '${json['overlay_url'] ?? ''}'.trim();
    String seqNum = '${json['seq_num'] ?? json['seqno'] ?? json['seqNum'] ?? ''}'.trim();

    final imageMap = json['image'];
    if (imageMap is Map<String, dynamic>) {
      overlayUrl = '${imageMap['overlay_url'] ?? overlayUrl}'.trim();
      overlayDataUrl = '${imageMap['overlay_data_url'] ?? overlayDataUrl}'.trim();
      seqNum = '${imageMap['seq_num'] ?? imageMap['seqno'] ?? seqNum}'.trim();
    }

    final baseImage =
        '${json['imageUrl'] ?? json['image_url'] ?? ''}'.trim();
    final productId =
        '${json['productId'] ?? json['product_id'] ?? json['prod_id'] ?? orgProdId}';
    final imageUrl = baseImage.isNotEmpty
        ? baseImage
        : (orgProdId.isNotEmpty
            ? 'https://media.taaze.tw/showLargeImage.html?sc=$orgProdId&height=170&width=250'
            : '');

    return PickListItem(
      id: rkId.isNotEmpty ? rkId : '${json['id'] ?? json['code'] ?? sdNo}',
      productId: productId,
      title: titleMain.isNotEmpty
          ? titleMain
          : '${json['title'] ?? json['name'] ?? ''}',
      imageUrl: imageUrl,
      titleMain: titleMain.isNotEmpty ? titleMain : null,
      rkId: rkId.isNotEmpty ? rkId : null,
      orgProdId: orgProdId.isNotEmpty ? orgProdId : null,
      logcode: logcode.isNotEmpty ? logcode : null,
      mustQty: mustQty,
      overlayDataUrl: overlayDataUrl.isNotEmpty ? overlayDataUrl : null,
      overlayUrl: overlayUrl.isNotEmpty ? overlayUrl : null,
      seqNum: seqNum.isNotEmpty ? seqNum : null,
      sdNo: sdNo.isEmpty ? null : sdNo,
      main: main,
    );
  }
}

