import 'dart:async';

import '../models/pick_list_item.dart';

/// Mock service to fetch pick-list items.
/// Later replace with real backend call.
class PickListService {
  Future<List<PickListItem>> fetchPickList() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return [
      PickListItem(
        id: 'B001',
        title: '深入淺出 Flutter',
        imageUrl:
            'https://picsum.photos/seed/flutter/400/600', // placeholder
      ),
      PickListItem(
        id: 'B002',
        title: '演算法圖鑑',
        imageUrl: 'https://picsum.photos/seed/algorithms/400/600',
      ),
      PickListItem(
        id: 'B003',
        title: '資料密集型應用系統設計',
        imageUrl: 'https://picsum.photos/seed/ddia/400/600',
      ),
    ];
  }
}

