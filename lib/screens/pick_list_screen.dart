import 'package:flutter/material.dart';

import '../models/pick_list_item.dart';
import '../services/picklist_service.dart';

class PickListScreen extends StatefulWidget {
  const PickListScreen({super.key, this.service, this.onCountChanged});

  final PickListService? service;
  final ValueChanged<int>? onCountChanged;

  @override
  State<PickListScreen> createState() => _PickListScreenState();
}

class _PickListScreenState extends State<PickListScreen> {
  late final PickListService _service;
  late Future<List<PickListItem>> _future;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _future = _service.fetchPickList();
    _future
        .then((items) => widget.onCountChanged?.call(items.length))
        .catchError((_) {});
  }

  Future<void> _reload() async {
    setState(() {
      _future = _service.fetchPickList();
    });
    try {
      final items = await _future;
      widget.onCountChanged?.call(items.length);
    } catch (_) {
      // keep previous count on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('檢貨單'),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<PickListItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('載入失敗'),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}'),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _reload, child: const Text('重試')),
                ],
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('目前沒有檢貨項目'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _PickCard(
                  item: item,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PickItemPreviewScreen(item: item),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.item, this.onTap});

  final PickListItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 120,
              child: Image.network(
                item.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '櫃號: ${item.id}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PickItemPreviewScreen extends StatelessWidget {
  const PickItemPreviewScreen({super.key, required this.item});

  final PickListItem item;
  static const _mockLocalImages = [
    'temp_images/1293467_0_annotated_gemini_pro.jpg',
    'temp_images/1293468_0_annotated_gemini_pro.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
      ),
      body: PageView.builder(
        itemCount: _mockLocalImages.length,
        itemBuilder: (context, index) {
          final path = _mockLocalImages[index];
          return InteractiveViewer(
            child: Center(
              child: Image.asset(
                path,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
