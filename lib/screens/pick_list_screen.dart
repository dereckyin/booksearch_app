import 'package:flutter/material.dart';

import '../models/pick_list_item.dart';
import '../models/pick_list_main.dart';
import '../services/picklist_service.dart';

class PickListScreen extends StatefulWidget {
  const PickListScreen({
    super.key,
    this.service,
    this.onCountChanged,
    this.employeeId,
    this.onRequestEmployeeId,
  });

  final PickListService? service;
  final ValueChanged<int>? onCountChanged;
  final String? employeeId;
  final VoidCallback? onRequestEmployeeId;

  @override
  State<PickListScreen> createState() => _PickListScreenState();
}

class _PickListScreenState extends State<PickListScreen> {
  late final PickListService _service;
  Future<List<PickListMain>>? _futureMain;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _loadIfReady(widget.employeeId);
  }

  @override
  void didUpdateWidget(covariant PickListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.employeeId != oldWidget.employeeId) {
      _loadIfReady(widget.employeeId);
    }
  }

  void _loadIfReady(String? employeeId) {
    if (employeeId == null || employeeId.isEmpty) {
      setState(() => _futureMain = null);
      return;
    }
    final future = _service.fetchPickListMain(employeeId: employeeId);
    setState(() {
      _futureMain = future;
    });
    future.then((items) => widget.onCountChanged?.call(items.length)).catchError((_) {});
  }

  Future<void> _reload() async {
    _loadIfReady(widget.employeeId);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.employeeId == null || widget.employeeId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('撿貨單'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('請先輸入工號以載入撿貨單'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: widget.onRequestEmployeeId,
                child: const Text('輸入工號'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('撿貨單'),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<PickListMain>>(
        future: _futureMain,
        builder: (context, snapshot) {
          if (_futureMain == null) {
            return const SizedBox.shrink();
          }
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
          final mains = snapshot.data ?? [];
          if (mains.isEmpty) {
            return const Center(child: Text('目前沒有撿貨單'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: mains.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final main = mains[index];
                return _PickMainCard(
                  main: main,
                  onTap: () => _openItems(main),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openItems(PickListMain main) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PickListItemsScreen(
          main: main,
          employeeId: widget.employeeId!,
          service: _service,
        ),
      ),
    );
  }
}

class _PickMainCard extends StatelessWidget {
  const _PickMainCard({required this.main, this.onTap});

  final PickListMain main;
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
              width: 12,
              height: 120,
              child: Container(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '撿貨單號：${main.sdNo}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '狀態：${main.statusText ?? main.statusFlg ?? '-'} / 配送：${main.deliverText ?? main.deliver ?? '-'}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '件數：${main.ttlMustQty ?? '-'}，A頁：${main.aPageCnt ?? '-'}，B頁：${main.bPageCnt ?? '-'}',
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

class _PickCard extends StatelessWidget {
  const _PickCard({required this.item, this.onTap});

  final PickListItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = item.title.isNotEmpty
        ? item.title
        : (item.titleMain != null && item.titleMain!.isNotEmpty
            ? item.titleMain!
            : '未提供品名');
    final shelfLabel = (item.rkId != null && item.rkId!.isNotEmpty)
        ? '櫃號: ${item.rkId}'
        : (item.id.isNotEmpty ? '櫃號: ${item.id}' : '櫃號: -');
    final productLabel = (item.productId.isNotEmpty)
        ? '店內碼: ${item.productId}'
        : (item.orgProdId != null && item.orgProdId!.isNotEmpty
            ? '店內碼: ${item.orgProdId}'
            : null);
    final sdLabel = (item.sdNo != null && item.sdNo!.isNotEmpty)
        ? '撿貨單：${item.sdNo}'
        : null;
    final logcodeLabel = (item.logcode != null && item.logcode!.isNotEmpty)
        ? '物流條碼: ${item.logcode}'
        : null;
    final qtyLabel =
        item.mustQty != null ? '數量: ${item.mustQty}' : null;

    Future<void> _showPreview(ImageProvider provider) async {
      await showDialog(
        context: context,
        builder: (_) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withOpacity(0.9),
            alignment: Alignment.center,
            child: InteractiveViewer(
              child: Image(
                image: provider,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
    }

    Widget _image() {
      if (item.imageUrl.trim().isEmpty) {
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        );
      }
      final provider = NetworkImage(item.imageUrl);
      return GestureDetector(
        onTap: () => _showPreview(provider),
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image),
          ),
        ),
      );
    }

    Widget _mockShelf() {
      final overlay = item.overlayDataUrl;
      if (overlay == null || overlay.isEmpty) {
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image),
        );
      }
      try {
        final data = UriData.parse(overlay);
        final bytes = data.contentAsBytes();
        final provider = MemoryImage(bytes);
        return GestureDetector(
          onTap: () => _showPreview(provider),
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Icon(Icons.image),
            ),
          ),
        );
      } catch (_) {
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        );
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(width: 96, height: 120, child: _image()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (productLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      productLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (logcodeLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      logcodeLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (qtyLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      qtyLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 96, height: 120, child: _mockShelf()),
          ],
        ),
      ),
    );
  }
}

class PickListItemsScreen extends StatefulWidget {
  const PickListItemsScreen({
    super.key,
    required this.main,
    required this.employeeId,
    this.service,
  });

  final PickListMain main;
  final String employeeId;
  final PickListService? service;

  @override
  State<PickListItemsScreen> createState() => _PickListItemsScreenState();
}

class _PickListItemsScreenState extends State<PickListItemsScreen> {
  late final PickListService _service;
  late Future<List<PickListItem>> _future;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _load();
  }

  void _load() {
    setState(() {
      _future = _service.fetchItemsBySdNo(
        employeeId: widget.employeeId,
        sdNo: widget.main.sdNo,
        main: widget.main,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      widget.main.statusText ?? widget.main.statusFlg,
      widget.main.deliverText ?? widget.main.deliver,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' / ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('撿貨單 ${widget.main.sdNo}'),
            if (subtitleParts.isNotEmpty)
              Text(
                subtitleParts,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
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
                  ElevatedButton(
                    onPressed: _load,
                    child: const Text('重試'),
                  ),
                ],
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('此撿貨單目前沒有品項'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _grouped(items).length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = _grouped(items)[index];
              final shelf = entry.key;
              final shelfItems = entry.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '櫃號：$shelf',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ...shelfItems.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PickCard(item: item),
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<MapEntry<String, List<PickListItem>>> _grouped(
      List<PickListItem> items) {
    final map = <String, List<PickListItem>>{};
    for (final item in items) {
      final key = (item.rkId != null && item.rkId!.isNotEmpty)
          ? item.rkId!
          : (item.id.isNotEmpty ? item.id : '未提供櫃號');
      map.putIfAbsent(key, () => []).add(item);
    }
    return map.entries.toList();
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
