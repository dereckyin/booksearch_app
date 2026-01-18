import 'pick_list_main.dart';

class PickListItem {
  PickListItem({
    required this.id,
    required this.productId,
    required this.title,
    required this.imageUrl,
    this.sdNo,
    this.main,
  });

  final String id;
  final String productId;
  final String title;
  final String imageUrl;
  final String? sdNo;
  final PickListMain? main;

  factory PickListItem.fromJson(
    Map<String, dynamic> json, {
    PickListMain? main,
  }) {
    final sdNo = '${json['sdNo'] ?? json['sd_no'] ?? ''}';
    return PickListItem(
      id: '${json['id'] ?? json['code'] ?? sdNo}',
      productId: '${json['productId'] ?? json['product_id'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? json['image_url'] ?? ''}',
      sdNo: sdNo.isEmpty ? null : sdNo,
      main: main,
    );
  }
}

