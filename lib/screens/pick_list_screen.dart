import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/cannot_pick_report.dart';
import '../models/pick_list_item.dart';
import '../models/pick_list_main.dart';
import '../services/picklist_service.dart';

class PickListScreen extends StatefulWidget {
  const PickListScreen({
    super.key,
    this.service,
    this.onCountChanged,
    this.employeeId,
    this.showDateOnCards = false,
  });

  final PickListService? service;
  final ValueChanged<int>? onCountChanged;
  final String? employeeId;
  final bool showDateOnCards;

  @override
  State<PickListScreen> createState() => _PickListScreenState();
}

class _PickListScreenState extends State<PickListScreen>
    with SingleTickerProviderStateMixin {
  late final PickListService _service;
  Future<List<PickListMain>>? _futureMain;
  Future<_SummaryData>? _futureSummary;
  Future<List<CannotPickReport>>? _futureCannotPick;
  late final TabController _tabController;
  final Map<String, bool> _canFinishToQcBySdNo = {};
  static const int _tabDone = 3;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 0);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _futureMain = _service.fetchPickListMain();
      _futureSummary = _loadSummary();
      _futureCannotPick = _service.fetchCannotPickToday(all: true);
      _canFinishToQcBySdNo.clear();
    });
    _futureMain
        ?.then((items) {
          _refreshFinishEligibility(items);
          widget.onCountChanged?.call(
            items.where((m) => m.isUnfinishedForBadge).length,
          );
        })
        .catchError((_) {});
  }

  static String _progressKey(String sdNo) =>
      'pick_list_progress_${sdNo.replaceAll(RegExp(r'[^\w\-]'), '_')}';

  static String _itemKeyForItem(PickListItem item) =>
      '${item.id}-${item.seqNum ?? ''}-${item.productId}';

  Future<void> _refreshFinishEligibility(List<PickListMain> mains) async {
    final targets = mains
        .where((m) => m.normalizedLockStatus == 'locked_by_me' && !m.isPickedDoneStage)
        .toList();
    if (targets.isEmpty) return;
    for (final m in targets) {
      final canFinish = await _canFinishToQcForMain(m);
      if (!mounted) return;
      setState(() {
        _canFinishToQcBySdNo[m.sdNo] = canFinish;
      });
    }
  }

  Future<bool> _canFinishToQcForMain(PickListMain main) async {
    try {
      final items = await _service.fetchItemsBySdNo(
        employeeId: widget.employeeId?.isNotEmpty == true ? widget.employeeId : null,
        sdNo: main.sdNo,
        main: main,
      );
      if (items.isEmpty) return false;
      final validKeys = items.map(_itemKeyForItem).toSet();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_progressKey(main.sdNo));
      if (raw == null) return false;
      final map = jsonDecode(raw) as Map<String, dynamic>?;
      if (map == null) return false;
      final completed =
          (map['completed'] as List<dynamic>?)
              ?.whereType<String>()
              .where(validKeys.contains)
              .toSet() ??
          <String>{};
      final notFound =
          (map['notFound'] as List<dynamic>?)
              ?.whereType<String>()
              .where(validKeys.contains)
              .toSet() ??
          <String>{};
      return completed.length + notFound.length == validKeys.length;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirmFinishToQc(PickListMain main) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認完成至待驗收'),
        content: Text('確定將揀貨單 ${main.sdNo} 標記為完成至待驗收？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<_SummaryData> _loadSummary() async {
    try {
      final summary = await _service.getSummary();
      final myToday = await _service.getMyToday();
      return _SummaryData(summary: summary, myToday: myToday);
    } catch (_) {
      return _SummaryData(summary: null, myToday: null);
    }
  }

  Future<void> _reload() async {
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          labelStyle: Theme.of(context).textTheme.labelMedium,
          unselectedLabelStyle: Theme.of(context).textTheme.labelSmall,
          tabs: const [
            Tab(text: '未撿貨(A)'),
            Tab(text: '未撿貨(B)'),
            Tab(text: '撿貨中'),
            Tab(text: '撿貨完'),
            Tab(text: '找不到'),
          ],
        ),
        Expanded(
          child: FutureBuilder<List<PickListMain>>(
            future: _futureMain,
            builder: (context, snapshot) {
              if (_futureMain == null) {
                return const Center(child: CircularProgressIndicator());
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
                      ElevatedButton(
                        onPressed: _reload,
                        child: const Text('重試'),
                      ),
                    ],
                  ),
                );
              }
              final mains = snapshot.data ?? [];
              final grouped = _groupMainByStatus(mains);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FutureBuilder<_SummaryData>(
                    future: _futureSummary,
                    builder: (context, sumSnap) {
                      if (!sumSnap.hasData) return const SizedBox.shrink();
                      final d = sumSnap.data!;
                      return _TodaySummaryCard(
                        summary: d.summary,
                        myToday: d.myToday,
                        availableCount: grouped['未撿貨(A)']!.length +
                            grouped['未撿貨(B)']!.length,
                        pickingCount: grouped['撿貨中']!.length,
                        completedCount: grouped['撿貨完']!.length,
                        onRefresh: _reload,
                      );
                    },
                  ),
                  Expanded(
                    child: mains.isEmpty
                        ? const Center(child: Text('目前沒有揀貨單'))
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _MainList(
                                mains: grouped['未撿貨(A)']!,
                                emptyText: '目前沒有未撿貨(A)的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTap: _openItems,
                                onFinishToQc: _onFinishToQc,
                                onRelease: _onRelease,
                                onRefresh: _reload,
                              ),
                              _MainList(
                                mains: grouped['未撿貨(B)']!,
                                emptyText: '目前沒有未撿貨(B)的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTap: _openItems,
                                onFinishToQc: _onFinishToQc,
                                onRelease: _onRelease,
                                onRefresh: _reload,
                              ),
                              _MainList(
                                mains: grouped['撿貨中']!,
                                emptyText: '目前沒有撿貨中的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTap: _openItems,
                                onFinishToQc: _onFinishToQc,
                                onRelease: _onRelease,
                                onRefresh: _reload,
                              ),
                              _MainList(
                                mains: grouped['撿貨完']!,
                                emptyText: '目前沒有撿貨完成的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTap: _openItems,
                                onFinishToQc: _onFinishToQc,
                                onRelease: _onRelease,
                                onRefresh: _reload,
                              ),
                              _CannotPickTodayTab(
                                future: _futureCannotPick,
                                onRefresh: () async {
                                  setState(() {
                                    _futureCannotPick =
                                        _service.fetchCannotPickToday(all: true);
                                  });
                                  await _futureCannotPick;
                                },
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, List<PickListMain>> _groupMainByStatus(List<PickListMain> mains) {
    final Map<String, List<PickListMain>> result = {
      '未撿貨(A)': [],
      '未撿貨(B)': [],
      '撿貨中': [],
      '撿貨完': [],
    };
    for (final m in mains) {
      final key = m.flowTabLabel == '可分貨' ? '撿貨完' : m.flowTabLabel;
      if (key == '未撿貨') {
        result[_bucketUndoneArea(m)]!.add(m);
      } else {
        result[key]!.add(m);
      }
    }
    return result;
  }

  String _bucketUndoneArea(PickListMain m) {
    final area = (m.area ?? '').trim().toUpperCase();
    if (area == 'A') return '未撿貨(A)';
    if (area == 'B') return '未撿貨(B)';
    final sd = m.sdNo.toUpperCase();
    if (sd.contains('(A)')) return '未撿貨(A)';
    if (sd.contains('(B)')) return '未撿貨(B)';
    return '未撿貨(A)';
  }

  Future<void> _openItems(PickListMain main) async {
    final readOnly = main.isPickedDoneStage || main.isReadyToSortStage;
    if (!readOnly && main.normalizedLockStatus == 'locked_by_other') return;
    if (!readOnly && main.isAvailableToPick) {
      try {
        await _service.lock(main.sdNo);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('領單失敗: $e')));
        _reload();
        return;
      }
      if (!mounted) return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PickListItemsScreen(
              main: main,
              employeeId: widget.employeeId ?? '',
              service: _service,
              readOnly: readOnly,
              onFinishedToQcAndPop: () {
                _tabController.animateTo(_tabDone);
                _reload();
              },
            ),
          ),
        )
        .then((_) => _reload());
  }

  Future<void> _onFinishToQc(PickListMain main) async {
    try {
      final canFinish = await _canFinishToQcForMain(main);
      if (!canFinish) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先將所有項目標記為完成或找不到')),
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await _confirmFinishToQc(main);
      if (!confirmed) return;
      await _service.finishToQc(main.sdNo);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已完成至待驗收')));
      _tabController.animateTo(_tabDone);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('完成失敗: $e')));
      _reload();
    }
  }

  Future<void> _onRelease(PickListMain main) async {
    try {
      await _service.unlock(main.sdNo);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已釋放揀貨單')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('釋放失敗: $e')));
      _reload();
    }
  }
}

class _SummaryData {
  _SummaryData({this.summary, this.myToday});
  final MainSummary? summary;
  final MyTodayResponse? myToday;
}

class _CannotPickTodayTab extends StatelessWidget {
  const _CannotPickTodayTab({
    required this.future,
    required this.onRefresh,
  });

  final Future<List<CannotPickReport>>? future;
  final Future<void> Function() onRefresh;

  String _fmt(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '-';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CannotPickReport>>(
      future: future,
      builder: (context, snapshot) {
        if (future == null || snapshot.connectionState == ConnectionState.waiting) {
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
                ElevatedButton(onPressed: onRefresh, child: const Text('重試')),
              ],
            ),
          );
        }

        final items = (snapshot.data ?? []).toList()
          ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 48),
                    Center(child: Text('今天沒有找不到回報')),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final r = items[index];
                    final who = (r.reportedByName != null &&
                            r.reportedByName!.isNotEmpty)
                        ? r.reportedByName!
                        : (r.reportedByPhone ?? '-');
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title?.isNotEmpty == true
                                  ? r.title!
                                  : '店內碼：${r.prodId}',
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _chip(context, '揀貨單', r.sdNo),
                                _chip(context, '櫃號', r.rkId),
                                _chip(context, '原因', r.reason),
                                _chip(context, '回報者', who),
                              ],
                            ),
                            if (r.remark != null && r.remark!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '備註：${r.remark}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              _fmt(r.reportedAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label：$value',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    this.summary,
    this.myToday,
    this.availableCount,
    this.pickingCount,
    this.completedCount,
    this.onRefresh,
  });

  final MainSummary? summary;
  final MyTodayResponse? myToday;
  /// 依新規則分組的數量（未撿貨、撿貨中、撿貨完），有值時優先顯示
  final int? availableCount;
  final int? pickingCount;
  final int? completedCount;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final useGrouped =
        availableCount != null || pickingCount != null || completedCount != null;
    if (summary == null && myToday == null && !useGrouped) {
      return const SizedBox.shrink();
    }
    final parts = <String>[];
    if (summary != null) {
      parts.add('今日 ${summary!.totalSheets} 批（${summary!.totalEntries} 筆）');
    }
    if (useGrouped) {
      parts.add('未撿貨 ${availableCount ?? 0}');
      parts.add('撿貨中 ${pickingCount ?? 0}');
      parts.add('撿貨完 ${completedCount ?? 0}');
    } else if (myToday != null) {
      parts.add('撿貨中 ${myToday!.lockedCount}');
      parts.add('撿貨完 ${myToday!.completedCount}');
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
      child: Row(
        children: [
          Icon(
            Icons.today,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '重新整理',
              onPressed: onRefresh,
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }
}

class _MainList extends StatelessWidget {
  const _MainList({
    required this.mains,
    required this.emptyText,
    required this.service,
    required this.showDateOnCards,
    required this.canFinishToQcBySdNo,
    required this.onTap,
    required this.onFinishToQc,
    required this.onRelease,
    required this.onRefresh,
  });

  final List<PickListMain> mains;
  final String emptyText;
  final PickListService service;
  final bool showDateOnCards;
  final Map<String, bool> canFinishToQcBySdNo;
  final Future<void> Function(PickListMain) onTap;
  final Future<void> Function(PickListMain) onFinishToQc;
  final Future<void> Function(PickListMain) onRelease;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: mains.isEmpty ? 1 : mains.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (mains.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  emptyText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          final main = mains[index];
          return _PickMainCard(
            main: main,
            showDate: showDateOnCards,
            canFinishToQc: canFinishToQcBySdNo[main.sdNo] ?? false,
            onTap: () => onTap(main),
            onFinishToQc: () => onFinishToQc(main),
            onRelease: () => onRelease(main),
          );
        },
      ),
    );
  }
}

class _PickMainCard extends StatelessWidget {
  const _PickMainCard({
    required this.main,
    this.showDate = false,
    this.canFinishToQc = false,
    this.onTap,
    this.onFinishToQc,
    this.onRelease,
  });

  final PickListMain main;
  final bool showDate;
  final bool canFinishToQc;
  final VoidCallback? onTap;
  final VoidCallback? onFinishToQc;
  final VoidCallback? onRelease;
  String _dateText(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = main.lockStatus;
    final isAvailable = main.isAvailableToPick;
    final isLockedByMe = main.normalizedLockStatus == 'locked_by_me';
    final isLockedByOther = main.normalizedLockStatus == 'locked_by_other';
    final isDone = main.isPickedDoneStage;
    final isReadOnlyFlow = main.isPickedDoneStage || main.isReadyToSortStage;
    final canTap = isReadOnlyFlow || (isAvailable || isLockedByMe);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canTap ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '揀貨單號：${main.sdNo}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (status != null && status.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isLockedByOther
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.errorContainer.withAlpha(153)
                                  : Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withAlpha(204),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              main.lockStatusDisplay,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '流程：${main.flowTabLabel}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '通路：${main.channelDisplayText ?? '-'} / ${main.mallDisplayText ?? '商城（-）'}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '件數：${main.ttlMustQty ?? '-'}',
                    ),
                    if (showDate && main.crtTime != null) ...[
                      const SizedBox(height: 4),
                      Text('建立時間：${_dateText(main.crtTime!)}'),
                    ],
                    if (!isDone && isLockedByMe) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (onFinishToQc != null)
                            TextButton.icon(
                              onPressed: canFinishToQc ? onFinishToQc : null,
                              icon: const Icon(Icons.lock_open, size: 18),
                              label: const Text('完成至待驗收'),
                            ),
                          if (onRelease != null)
                            TextButton.icon(
                              onPressed: onRelease,
                              icon: const Icon(Icons.lock_outline, size: 18),
                              label: const Text('釋放'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 五顆星評分，預設五星；無現場圖時 disabled（灰色、不可點）
class _ShelfRatingStars extends StatelessWidget {
  const _ShelfRatingStars({
    required this.rating,
    this.enabled = true,
    this.onChanged,
  });

  final int rating;
  final bool enabled;
  final void Function(int)? onChanged;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (Theme.of(context).colorScheme.primary)
        : Theme.of(context).colorScheme.onSurface.withAlpha(89);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final value = index + 1;
        return IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(
            value <= rating ? Icons.star : Icons.star_border,
            color: color,
          ),
          onPressed: enabled && onChanged != null
              ? () => onChanged!(value)
              : null,
        );
      }),
    );
  }
}

/// 本張揀貨單所有櫃號的時間軸，標示目前進行到哪一櫃；會隨目前櫃號捲動以保持同步
class _ShelfTimeline extends StatefulWidget {
  const _ShelfTimeline({required this.labels, required this.currentIndex});

  final List<String> labels;
  final int currentIndex;

  @override
  State<_ShelfTimeline> createState() => _ShelfTimelineState();
}

class _ShelfTimelineState extends State<_ShelfTimeline> {
  final GlobalKey _currentKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _ShelfTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _scrollToCurrent();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  void _scrollToCurrent() {
    final ctx = _currentKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.labels.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surfaceContainerHighest;
    final currentIndex = widget.currentIndex.clamp(0, widget.labels.length - 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.labels.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            Container(
              key: i == currentIndex ? _currentKey : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: i == currentIndex ? primary : surface,
                borderRadius: BorderRadius.circular(8),
                border: i == currentIndex
                    ? Border.all(color: primary, width: 2)
                    : null,
              ),
              child: Text(
                widget.labels[i],
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: i == currentIndex
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: i == currentIndex
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.item,
    this.onTap,
    this.completed = false,
    this.notFound = false,
    this.hasShelfImage = false,
    this.shelfRating = 5,
    this.onShelfRatingChanged,
    this.allShelfLabels,
    this.currentShelfIndex,
  });

  final PickListItem item;
  final VoidCallback? onTap;
  final bool completed;
  final bool notFound;
  final bool hasShelfImage;
  final int shelfRating;
  final void Function(int)? onShelfRatingChanged;
  final List<String>? allShelfLabels;
  final int? currentShelfIndex;

  @override
  Widget build(BuildContext context) {
    final title = item.title.isNotEmpty
        ? item.title
        : (item.titleMain != null && item.titleMain!.isNotEmpty
              ? item.titleMain!
              : '未提供品名');
    final shelfLabel = (item.rkId != null && item.rkId!.isNotEmpty)
        ? item.rkId!
        : (item.id.isNotEmpty ? item.id : '-');
    final productLabel = (item.productId.isNotEmpty)
        ? '店內碼: ${item.productId}'
        : (item.orgProdId != null && item.orgProdId!.isNotEmpty
              ? '店內碼: ${item.orgProdId}'
              : null);
    final logcodeLabel = (item.logcode != null && item.logcode!.isNotEmpty)
        ? '物流條碼: ${item.logcode}'
        : null;
    final qtyLabel = item.mustQty != null ? '數量: ${item.mustQty}' : null;
    final seqLabel = (item.seqNum != null && item.seqNum!.isNotEmpty)
        ? '左至右第: ${item.seqNum}'
        : null;

    Future<void> showPreview(ImageProvider provider) async {
      await showDialog<void>(
        context: context,
        builder: (context) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withAlpha(230),
            alignment: Alignment.center,
            child: InteractiveViewer(
              child: Image(image: provider, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    }

    Widget buildImage() {
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
        onTap: () => showPreview(NetworkImage(url)),
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

    Widget buildShelfMock() {
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

      final shelfProvider = provider;
      if (shelfProvider == null) {
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image),
        );
      }

      return GestureDetector(
        onTap: () => showPreview(shelfProvider),
        child: shelfProvider is NetworkImage
            ? Image.network(
                shelfProvider.url,
                fit: BoxFit.cover,
                key: ValueKey(shelfProvider.url),
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
                image: shelfProvider,
                fit: BoxFit.cover,
                // Data-url based image has no stable URL; omit key.
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    Color? cardColor;
    Color borderColor = Colors.transparent;
    if (completed) {
      cardColor = colors.primary.withAlpha(20);
      borderColor = colors.primary;
    } else if (notFound) {
      cardColor = colors.errorContainer.withAlpha(153);
      borderColor = colors.error;
    }

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
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(31),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        shelfLabel,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ShelfRatingStars(
                    rating: shelfRating,
                    enabled: hasShelfImage,
                    onChanged: onShelfRatingChanged,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 櫃位現場圖置於上方，橫向鋪滿
              AspectRatio(aspectRatio: 16 / 9, child: buildShelfMock()),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(width: 120, height: 150, child: buildImage()),
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
                          const SizedBox(height: 4),
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
                          item.mustQty != null && item.mustQty! > 1
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.errorContainer.withAlpha(204),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error.withAlpha(153),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    qtyLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                        ),
                                  ),
                                )
                              : Text(
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
                ],
              ),
              if (allShelfLabels != null &&
                  currentShelfIndex != null &&
                  allShelfLabels!.isNotEmpty)
                _ShelfTimeline(
                  labels: allShelfLabels!,
                  currentIndex: currentShelfIndex!.clamp(
                    0,
                    allShelfLabels!.length - 1,
                  ),
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
    this.readOnly = false,
    this.onFinishedToQcAndPop,
  });

  final PickListMain main;
  final String employeeId;
  final PickListService? service;
  final bool readOnly;

  /// 完成至待驗收（finish-to-qc）後呼叫，例如刷新列表並切換 tab
  final VoidCallback? onFinishedToQcAndPop;

  @override
  State<PickListItemsScreen> createState() => _PickListItemsScreenState();
}

class _PickListItemsScreenState extends State<PickListItemsScreen> {
  late final PickListService _service;
  List<PickListItem> _items = [];
  Set<String> _completed = {};
  Set<String> _notFound = {};
  final Map<String, int> _shelfRatings = {}; // itemKey -> 1..5，預設 5
  int _currentVisibleIndex = 0;
  bool _showCompleted = false;
  bool _loading = true;
  String? _error;
  late final PageController _pageController;
  bool get _isReadOnly => widget.readOnly;
  bool get _canFinishToQc {
    if (_isReadOnly) return false;
    if (_loading || _items.isEmpty) return false;
    return _completed.length + _notFound.length == _items.length;
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _pageController = PageController();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static String _progressKey(String sdNo) =>
      'pick_list_progress_${sdNo.replaceAll(RegExp(r'[^\w\-]'), '_')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchItemsBySdNo(
        employeeId: widget.employeeId.isNotEmpty ? widget.employeeId : null,
        sdNo: widget.main.sdNo,
        main: widget.main,
      );
      if (!mounted) return;
      final itemKeys = data.map((e) => _itemKeyForItem(e)).toSet();
      final (completed, notFound) = _isReadOnly
          ? (<String>{}, <String>{})
          : await _restoreProgress(widget.main.sdNo, itemKeys);
      if (!mounted) return;
      setState(() {
        _items = data;
        _currentVisibleIndex = 0;
        _loading = false;
        _completed = completed;
        _notFound = notFound;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static String _itemKeyForItem(PickListItem item) =>
      '${item.id}-${item.seqNum ?? ''}-${item.productId}';

  Future<(Set<String>, Set<String>)> _restoreProgress(
    String sdNo,
    Set<String> validKeys,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_progressKey(sdNo));
      if (json == null) return (<String>{}, <String>{});
      final map = jsonDecode(json) as Map<String, dynamic>?;
      if (map == null) return (<String>{}, <String>{});
      final completed =
          (map['completed'] as List<dynamic>?)
              ?.whereType<String>()
              .where(validKeys.contains)
              .toSet() ??
          <String>{};
      final notFound =
          (map['notFound'] as List<dynamic>?)
              ?.whereType<String>()
              .where(validKeys.contains)
              .toSet() ??
          <String>{};
      return (completed, notFound);
    } catch (_) {
      return (<String>{}, <String>{});
    }
  }

  Future<void> _persistProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _progressKey(widget.main.sdNo),
        jsonEncode({
          'completed': _completed.toList(),
          'notFound': _notFound.toList(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_progressKey(widget.main.sdNo));
    } catch (_) {}
  }

  Future<void> _finishAndLeave() async {
    if (_isReadOnly) return;
    if (!_canFinishToQc) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先將所有項目標記為完成或找不到')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認完成至待驗收'),
        content: Text('確定將揀貨單 ${widget.main.sdNo} 標記為完成至待驗收？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.finishToQc(widget.main.sdNo);
      if (!mounted) return;
      await _clearProgress();
      if (!mounted) return;
      widget.onFinishedToQcAndPop?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('完成失敗: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '揀貨單 ${widget.main.sdNo}',
          style: Theme.of(context).textTheme.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
        actions: [
          if (!_isReadOnly)
            TextButton.icon(
              onPressed: _canFinishToQc ? _finishAndLeave : null,
              icon: const Icon(Icons.lock_open, size: 20),
              label: const Text('完成至待驗收'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final totalDone = _completed.length;
    final totalNotFound = _notFound.length;
    final totalUndone = _items.length - totalDone;
    final filtered = _isReadOnly
        ? List<int>.generate(_items.length, (i) => i)
        : _filteredIndexes();

    bool isItemView = false;
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
      isItemView = true;
      final item = _items[filtered[_currentVisibleIndex]];
      final itemKey = _itemKey(item);
      final isCompleted = _completed.contains(itemKey);
      final isNotFound = _notFound.contains(itemKey);
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -150) _go(1);
          if (v > 150) _go(-1);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: filtered.length,
                onPageChanged: (index) {
                  setState(() => _currentVisibleIndex = index);
                },
                itemBuilder: (context, index) {
                  final pageItem = _items[filtered[index]];
                  final key = _itemKey(pageItem);
                  final completed = _completed.contains(key);
                  final notFound = _notFound.contains(key);
                  final itemKey = _itemKey(pageItem);
                  final hasShelfImage =
                      (pageItem.overlayUrl != null &&
                          pageItem.overlayUrl!.isNotEmpty) ||
                      (pageItem.overlayDataUrl != null &&
                          pageItem.overlayDataUrl!.isNotEmpty);
                  final shelfLabels = [
                    for (var i = 0; i < filtered.length; i++)
                      (() {
                        final it = _items[filtered[i]];
                        final rk = it.rkId?.trim();
                        return (rk != null && rk.isNotEmpty) ? rk : it.id;
                      })(),
                  ];
                  return SizedBox.expand(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _PickCard(
                        item: pageItem,
                        onTap: () {},
                        completed: completed,
                        notFound: notFound,
                        hasShelfImage: hasShelfImage,
                        shelfRating: _shelfRatings[itemKey] ?? 5,
                        onShelfRatingChanged: !_isReadOnly && hasShelfImage
                            ? (v) => _onShelfRatingChanged(pageItem, v)
                            : null,
                        allShelfLabels: shelfLabels,
                        currentShelfIndex: index,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentVisibleIndex > 0 ? () => _go(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一項',
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isReadOnly ? null : () => _markComplete(item),
                  child: Text(isCompleted ? '已完成' : '完成'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _isReadOnly ? null : () => _markNotFound(item),
                  style: FilledButton.styleFrom(
                    backgroundColor: isNotFound
                        ? Theme.of(context).colorScheme.errorContainer
                        : null,
                  ),
                  child: Text(isNotFound ? '已標記' : '找不到'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _currentVisibleIndex < filtered.length - 1
                      ? () => _go(1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一項',
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _isReadOnly
                    ? Text(
                        '唯讀檢視',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : SegmentedButton<bool>(
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
                          if (_pageController.hasClients) {
                            _pageController.jumpToPage(0);
                          }
                        },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isReadOnly ? '總品項：${_items.length}' : '找不到：$totalNotFound',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (isItemView && filtered.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '項目 ${_currentVisibleIndex + 1} / ${filtered.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isItemView
                ? content
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(child: content),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _go(int delta) {
    final filtered = _filteredIndexes();
    final next = (_currentVisibleIndex + delta).clamp(0, filtered.length - 1);
    if (next != _currentVisibleIndex) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _markComplete(PickListItem item) {
    if (_isReadOnly) return;
    final key = _itemKey(item);
    setState(() {
      if (_completed.contains(key)) {
        _completed.remove(key);
      } else {
        _completed.add(key);
        _notFound.remove(key);
      }
      final filtered = _filteredIndexes();
      if (_currentVisibleIndex >= filtered.length) {
        _currentVisibleIndex = filtered.isEmpty ? 0 : filtered.length - 1;
      }
    });
    _persistProgress();
  }

  Future<void> _onShelfRatingChanged(PickListItem item, int rank) async {
    if (_isReadOnly) return;
    final key = _itemKey(item);
    setState(() => _shelfRatings[key] = rank);
    try {
      await _service.submitShelfFeedback(
        sdNo: widget.main.sdNo,
        prodId: item.productId,
        rkId: item.rkId ?? item.id,
        rank: rank,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('評分送出失敗: $e')));
    }
  }

  Future<void> _markNotFound(PickListItem item) async {
    if (_isReadOnly) return;
    final key = _itemKey(item);
    if (_notFound.contains(key)) {
      setState(() {
        _notFound.remove(key);
        _completed.remove(key);
      });
      _persistProgress();
      return;
    }
    final reason = await _showCannotPickDialog();
    if (reason == null || !mounted) return;
    try {
      await _service.reportCannotPick(
        sdNo: widget.main.sdNo,
        prodId: item.productId,
        rkId: item.rkId ?? item.id,
        reason: reason.reason,
        remark: reason.remark,
      );
      if (!mounted) return;
      setState(() {
        _notFound.add(key);
        _completed.remove(key);
      });
      _persistProgress();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已紀錄揀不到／異常')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('回報失敗: $e')));
    }
  }

  static const _cannotPickReasons = ['缺貨', '損壞', '找不到', '其他'];

  Future<({String reason, String? remark})?> _showCannotPickDialog() async {
    String selected = _cannotPickReasons.first;
    final remarkController = TextEditingController();
    final result = await showDialog<({String reason, String? remark})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('揀不到回報'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('原因'),
                    const SizedBox(height: 8),
                    ..._cannotPickReasons.map(
                      (r) => RadioListTile<String>(
                        value: r,
                        title: Text(r),
                        // ignore: deprecated_member_use
                        groupValue: selected,
                        // ignore: deprecated_member_use
                        onChanged: (v) =>
                            setState(() => selected = v ?? selected),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarkController,
                      decoration: const InputDecoration(
                        labelText: '備註（選填）',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final remark = remarkController.text.trim();
                    Navigator.of(context).pop((
                      reason: selected,
                      remark: remark.isEmpty ? null : remark,
                    ));
                  },
                  child: const Text('送出'),
                ),
              ],
            );
          },
        );
      },
    );
    remarkController.dispose();
    return result;
  }

  String _itemKey(PickListItem item) => _itemKeyForItem(item);

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
      appBar: AppBar(title: Text(item.title)),
      body: PageView.builder(
        itemCount: _mockLocalImages.length,
        itemBuilder: (context, index) {
          final path = _mockLocalImages[index];
          return InteractiveViewer(
            child: Center(child: Image.asset(path, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
