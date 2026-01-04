import 'dart:async';

import '../models/pick_list_item.dart';

/// Mock service to fetch pick-list items.
/// Later replace with real backend call.
class PickListService {
  Future<List<PickListItem>> fetchPickList() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return [
      PickListItem(
        id: 'B21',
        productId: '61100020974',
        title: '2026《餘生是你 晚點沒關係》語錄日曆 暖杏微光【黃山料】',
        imageUrl:
            'https://media.taaze.tw/showThumbnail.html?sc=61100020974&height=400&width=310', // placeholder
      ),
      PickListItem(
        id: 'B22',
        productId: '11101080438',
        title: '台灣有事，世界有事：處在大國衝突第一線，台灣人必須理解的國際關係與戰略思維',
        imageUrl:
            'https://media.taaze.tw/showThumbnail.html?sc=11101080438&height=400&width=310',
      ),
      PickListItem(
        id: 'B23',
        productId: '11101080281',
        title: '我們只是沒有名片，從來沒有休息過！：她們不只是誰的妻子、誰的母親，探訪這些韓國大姊們真正的「工作」故事。',
        imageUrl:
            'https://media.taaze.tw/showThumbnail.html?sc=11101080281&height=400&width=310',
      ),
    ];
  }
}
