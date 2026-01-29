import 'package:flutter/material.dart';

import '../models/pick_list_item.dart';
import '../models/pick_list_main.dart';
import '../services/picklist_service.dart';
import '../config/api_config.dart';

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
              const Text('請先輸入電話號碼以載入撿貨單'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: widget.onRequestEmployeeId,
                child: const Text('輸入電話號碼'),
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
  const _PickCard({required this.item, this.onTap, this.completed = false});

  final PickListItem item;
  final VoidCallback? onTap;
  final bool completed;

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
    final seqLabel =
        (item.seqNum != null && item.seqNum!.isNotEmpty) ? '左至右第: ${item.seqNum}' : null;

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
      final url = item.imageUrl.startsWith('http')
          ? item.imageUrl
          : Uri.parse(ApiConfig().uploadBase).resolve(item.imageUrl).toString();
      return GestureDetector(
        onTap: () => _showPreview(NetworkImage(url)),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image),
          ),
        ),
      );
    }

    Widget _mockShelf() {
      ImageProvider? provider;
      String? urlString;
      if (item.overlayUrl != null && item.overlayUrl!.isNotEmpty) {
        final base = ApiConfig().uploadBase;
        final overlay = item.overlayUrl!;
        final uri = overlay.startsWith('http')
            ? Uri.parse(overlay)
            : Uri.parse(base).resolve(overlay); // 確保加上 API host
        urlString = uri.toString();
        provider = NetworkImage(urlString);
      } else if (item.overlayDataUrl != null &&
          item.overlayDataUrl!.isNotEmpty) {
        try {
          final data = UriData.parse(item.overlayDataUrl!);
          provider = MemoryImage(data.contentAsBytes());
        } catch (_) {}
      }

      if (provider == null) {
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image),
        );
      }

      return GestureDetector(
        onTap: () => _showPreview(provider!),
        child: provider is NetworkImage
            ? Image.network(
                urlString!,
                fit: BoxFit.cover,
                key: urlString != null ? ValueKey(urlString) : null,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image_not_supported),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          '載入失敗',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Image(
                image: provider!,
                fit: BoxFit.cover,
                key: urlString != null ? ValueKey(urlString) : null,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
      );
    }

    final cardColor = completed
        ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
        : null;
    final borderColor = completed
        ? Theme.of(context).colorScheme.primary
        : Colors.transparent;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: completed ? 2 : 0),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  shelfLabel,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
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
                        if (seqLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            seqLabel,
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
            ],
          ),
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
  List<PickListItem> _items = [];
  Set<String> _completed = {};
  int _currentVisibleIndex = 0;
  bool _showCompleted = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchItemsBySdNo(
        employeeId: widget.employeeId,
        sdNo: widget.main.sdNo,
        main: widget.main,
      );
      if (!mounted) return;
      setState(() {
        _items = data;
        _currentVisibleIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final totalDone = _completed.length;
    final totalUndone = _items.length - totalDone;
    final filtered = _filteredIndexes();

    Widget content;
    if (_error != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('載入失敗'),
          const SizedBox(height: 8),
          Text(_error!),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _load, child: const Text('重試')),
        ],
      );
    } else if (_items.isEmpty) {
      content = const Center(child: Text('此撿貨單目前沒有品項'));
    } else if (filtered.isEmpty) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('目前沒有符合條件的品項'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => setState(() {
              _showCompleted = false;
              _currentVisibleIndex = 0;
            }),
            child: const Text('顯示未撿貨'),
          ),
        ],
      );
    } else {
      final item = _items[filtered[_currentVisibleIndex]];
      final isCompleted = _completed.contains(_itemKey(item));
      content = Column(
        children: [
          _PickCard(
            item: item,
            onTap: () {},
            completed: isCompleted,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FilledButton.tonal(
                onPressed: _currentVisibleIndex > 0 ? () => _go(-1) : null,
                child: const Text('上一項'),
              ),
              FilledButton(
                onPressed: () => _markComplete(item),
                child: Text(isCompleted ? '已完成' : '標記完成'),
              ),
              FilledButton.tonal(
                onPressed: _currentVisibleIndex < filtered.length - 1
                    ? () => _go(1)
                    : null,
                child: const Text('下一項'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '項目 ${_currentVisibleIndex + 1}/${filtered.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('未撿貨 ($totalUndone)'),
                      icon: const Icon(Icons.list_alt),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('已撿貨 ($totalDone)'),
                      icon: const Icon(Icons.check_circle),
                    ),
                  ],
                  selected: {_showCompleted},
                  onSelectionChanged: (sel) {
                    final value = sel.first;
                    setState(() {
                      _showCompleted = value;
                      _currentVisibleIndex = 0;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(child: content),
          ),
        ],
      ),
    );
  }

  void _go(int delta) {
    final filtered = _filteredIndexes();
    final next = (_currentVisibleIndex + delta).clamp(0, filtered.length - 1);
    if (next != _currentVisibleIndex) {
      setState(() => _currentVisibleIndex = next);
    }
  }

  void _markComplete(PickListItem item) {
    final key = _itemKey(item);
    setState(() {
      if (_completed.contains(key)) {
        _completed.remove(key);
      } else {
        _completed.add(key);
      }
      final filtered = _filteredIndexes();
      if (_currentVisibleIndex >= filtered.length) {
        _currentVisibleIndex = filtered.isEmpty ? 0 : filtered.length - 1;
      }
    });
  }

  String _itemKey(PickListItem item) =>
      '${item.id}-${item.seqNum ?? ''}-${item.productId}';

  List<int> _filteredIndexes() {
    final result = <int>[];
    for (var i = 0; i < _items.length; i++) {
      final key = _itemKey(_items[i]);
      final isDone = _completed.contains(key);
      if (_showCompleted ? isDone : !isDone) {
        result.add(i);
      }
    }
    return result;
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
