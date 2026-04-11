import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/cannot_pick_report.dart';
import '../models/pick_list_item.dart';
import '../models/pick_list_main.dart';
import '../services/picklist_service.dart';
import '../utils/pick_list_merge.dart';

/// 合併卡／明細：將 `（一）` 等序號後綴以紅字顯示。
TextSpan _textSpanWithRedMergeOrdinal(String text, TextStyle? style) {
  final (pre, suf) = splitMergeOrdinalSuffix(text);
  if (suf == null) return TextSpan(text: text, style: style);
  return TextSpan(
    style: style,
    children: [
      TextSpan(text: pre),
      TextSpan(
        text: suf,
        style: const TextStyle(color: Colors.red),
      ),
    ],
  );
}

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
  Future<List<CannotPickReport>>? _futureCannotPickAbnormal;
  late final TabController _tabController;
  final Map<String, bool> _canFinishToQcBySdNo = {};
  static const int _tabDone = 3;
  bool _selectionMode = false;
  final Set<String> _selectedSdNos = {};
  int? _mergeSelectTabIndex;
  /// 本機紀錄的合併領單組（用於 [撿貨中] 摺成單張卡片）
  List<List<String>> _cachedMergeGroups = [];
  /// 曾「合併完成至待驗收」的單號組（用於 [撿貨完] 摺成與撿貨中相同版面）
  List<List<String>> _cachedCompletedMergeGroups = [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PickListService();
    _tabController = TabController(length: 6, vsync: this, initialIndex: 0);
    _tabController.addListener(_onPickTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onPickTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onPickTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      if (_selectionMode &&
          _mergeSelectTabIndex != null &&
          _tabController.index != _mergeSelectTabIndex) {
        _selectionMode = false;
        _selectedSdNos.clear();
        _mergeSelectTabIndex = null;
      }
    });
  }

  bool _mergeSelectable(PickListMain m) {
    final readOnly = m.isPickedDoneStage || m.isReadyToSortStage;
    if (readOnly) return false;
    if (m.normalizedLockStatus == 'locked_by_other') return false;
    return m.isAvailableToPick || m.normalizedLockStatus == 'locked_by_me';
  }

  void _toggleSelect(PickListMain m) {
    if (!_mergeSelectable(m)) return;
    setState(() {
      if (_selectedSdNos.contains(m.sdNo)) {
        _selectedSdNos.remove(m.sdNo);
      } else {
        _selectedSdNos.add(m.sdNo);
      }
    });
  }

  Future<void> _openMergedItems() async {
    if (_selectedSdNos.length < 2) return;
    final all = await _service.fetchPickListMain(
      priorOpenDays: PickListService.kDefaultPriorOpenDays,
    );
    if (!mounted) return;
    // Set 已保證同一 sd_no 只會勾選一次；若 API 重複回傳同一單號，這裡再依 sd_no 去重
    final pickedBySd = <String, PickListMain>{};
    for (final m in all) {
      if (_selectedSdNos.contains(m.sdNo)) {
        pickedBySd.putIfAbsent(m.sdNo, () => m);
      }
    }
    var picked = pickedBySd.values.toList();
    if (picked.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('選取單據已變更，請重新選擇')),
        );
        setState(() {
          _selectionMode = false;
          _selectedSdNos.clear();
          _mergeSelectTabIndex = null;
        });
      }
      _reload();
      return;
    }
    // 合併明細（一）（二）依主檔 ttl 多到少（見 buildMergePlan）；與合併卡 [mergeCardMainsOrdered] 一致
    picked = mergeCardMainsOrdered(picked);
    // 重新拉清單後若有人已領走其中一單，不可再進合併（否則會略過 lock 仍開明細）
    final blocked = picked
        .where((m) => m.normalizedLockStatus == 'locked_by_other')
        .toList();
    if (blocked.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              blocked.length == 1
                  ? '單據 ${blocked.first.sdNo} 已被他人領取，請重新選擇'
                  : '選取範圍內有 ${blocked.length} 張單據已被他人領取，請重新選擇',
            ),
          ),
        );
        setState(() {
          _selectionMode = false;
          _selectedSdNos.clear();
          _mergeSelectTabIndex = null;
        });
      }
      _reload();
      return;
    }
    final locked = <String>[];
    try {
      for (final m in picked) {
        if (m.isAvailableToPick) {
          await _service.lock(m.sdNo);
          locked.add(m.sdNo);
        }
      }
    } catch (e) {
      for (final sd in locked.reversed) {
        try {
          await _service.unlock(sd);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('領單失敗: $e')),
        );
      }
      _reload();
      return;
    }
    if (!mounted) return;
    await addPickingMergeGroup(picked.map((m) => m.sdNo).toList());
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedSdNos.clear();
      _mergeSelectTabIndex = null;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PickListItemsScreen(
          main: picked.first,
          mergeMains: picked,
          employeeId: widget.employeeId ?? '',
          service: _service,
          readOnly: false,
          onFinishedToQcAndPop: () {
            _tabController.animateTo(_tabDone);
            _reload();
          },
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<List<CannotPickReport>> _loadCannotPickAbnormalForTab() async {
    final abnormal = await _service.fetchCannotPickAbnormal(all: true).catchError(
      (_) => <CannotPickReport>[],
    );
    // 兼容：有些案件會直接以找不到原因或第一層處理結果進到分貨異常，
    // 後端若尚未納入 /cannot-pick/abnormal，前端仍要能在「分貨異常」看到。
    final today = await _service.fetchCannotPickToday(all: true).catchError(
      (_) => <CannotPickReport>[],
    );
    final todayExtra = today.where(_shouldRouteToAbnormal).toList();

    final byId = <int, CannotPickReport>{};
    for (final r in [...abnormal, ...todayExtra]) {
      byId[r.id] = r;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    return merged;
  }

  void _load() {
    final fut = _service.fetchPickListMain(
      priorOpenDays: PickListService.kDefaultPriorOpenDays,
    );
    setState(() {
      _futureMain = fut;
      _futureSummary = _loadSummary();
      _futureCannotPick = _service.fetchCannotPickToday(all: true);
      _futureCannotPickAbnormal = _loadCannotPickAbnormalForTab();
      _canFinishToQcBySdNo.clear();
    });
    fut
        .then((items) {
          if (!mounted) return;
          widget.onCountChanged?.call(
            items.where((m) => m.isUnfinishedForBadge).length,
          );
        })
        .catchError((_) {});
    _afterMainLoaded(fut);
  }

  Future<void> _afterMainLoaded(Future<List<PickListMain>> fut) async {
    final items = await fut;
    if (!mounted) return;
    final g = await loadPickingMergeGroups();
    final cg = await loadCompletedMergeGroups();
    if (!mounted) return;
    setState(() {
      _cachedMergeGroups = g;
      _cachedCompletedMergeGroups = cg;
    });
    await _refreshFinishEligibilityWithGroups(items);
  }

  static String _progressKey(String sdNo) =>
      'pick_list_progress_${sdNo.replaceAll(RegExp(r'[^\w\-]'), '_')}';

  static String _itemKeyForItem(PickListItem item) =>
      '${item.id}-${item.seqNum ?? ''}-${item.productId}';

  Future<void> _refreshFinishEligibilityWithGroups(List<PickListMain> mains) async {
    final picking = mains
        .where(
          (m) =>
              m.normalizedLockStatus == 'locked_by_me' && !m.isPickedDoneStage,
        )
        .toList();
    final rows = collapsePickingRowsByMergeGroups(picking, _cachedMergeGroups);
    final next = <String, bool>{};
    for (final row in rows) {
      if (row.length >= 2) {
        final can = await _canFinishToQcForMergeRow(row);
        if (!mounted) return;
        next[mergeFinishEligibilityKey(row.map((m) => m.sdNo))] = can;
      } else {
        final m = row.single;
        final can = await _canFinishToQcForMain(m);
        if (!mounted) return;
        next[m.sdNo] = can;
      }
    }
    if (!mounted) return;
    setState(() {
      _canFinishToQcBySdNo
        ..clear()
        ..addAll(next);
    });
  }

  Future<bool> _canFinishToQcForMergeRow(List<PickListMain> mains) async {
    try {
      final emp =
          widget.employeeId?.isNotEmpty == true ? widget.employeeId : null;
      final bundles = <({PickListMain main, List<PickListItem> items})>[];
      for (final m in mains) {
        final items = await _service.fetchItemsBySdNo(
          employeeId: emp,
          sdNo: m.sdNo,
          main: m,
        );
        bundles.add((main: m, items: items));
      }
      final plan = buildMergePlan(bundles);
      final merged = plan.mergedItems;
      if (merged.isEmpty) return false;
      final validKeys =
          merged.map((e) => itemKeyForPick(e, merge: true)).toSet();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        mergeProgressKey(mains.map((m) => m.sdNo)),
      );
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

  Future<bool> _confirmFinishToQcMerge(List<PickListMain> mains) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認完成至待驗收'),
        content: SingleChildScrollView(
          child: Text(
            '確定將以下 ${mains.length} 張合併揀貨單標記為完成至待驗收？\n\n'
            '${mains.map((m) => m.sdNo).join('\n')}',
          ),
        ),
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
      final summary = await _service.getSummary(
        priorOpenDays: PickListService.kDefaultPriorOpenDays,
      );
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
            Tab(text: '分貨異常'),
          ],
        ),
        // 多選合併僅在未撿貨(A)/(B)；撿貨中／撿貨完不開放新建合併
        if (_tabController.index < 2)
          Material(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withAlpha(140),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        if (_selectionMode) {
                          _selectionMode = false;
                          _selectedSdNos.clear();
                          _mergeSelectTabIndex = null;
                        } else {
                          _selectionMode = true;
                          _mergeSelectTabIndex = _tabController.index;
                          _selectedSdNos.clear();
                        }
                      });
                    },
                    icon: Icon(
                      _selectionMode ? Icons.close : Icons.library_add_check_outlined,
                    ),
                    label: Text(_selectionMode ? '取消多選' : '多選合併'),
                  ),
                  if (_selectionMode) ...[
                    Expanded(
                      child: Text(
                        '已選 ${_selectedSdNos.length}（至少 2 張）',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    FilledButton(
                      onPressed:
                          _selectedSdNos.length >= 2 ? _openMergedItems : null,
                      child: const Text('合併撿貨'),
                    ),
                  ],
                ],
              ),
            ),
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
                        pickingCount: collapsePickingRowsByMergeGroups(
                          grouped['撿貨中']!,
                          _cachedMergeGroups,
                        ).length,
                        completedCount: collapseDoneTabRowsByMergeGroups(
                          grouped['撿貨完']!,
                          _cachedCompletedMergeGroups,
                        ).length,
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
                                rows: _unpickedRowsForMergeSelect(
                                  grouped['未撿貨(A)']!,
                                  0,
                                ),
                                emptyText: '目前沒有未撿貨(A)的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTapRow: _openItemsRow,
                                onFinishToQcRow: _onFinishToQcRow,
                                onReleaseRow: _onReleaseRow,
                                onRefresh: _reload,
                                selectionMode: _selectionMode &&
                                    _mergeSelectTabIndex == 0,
                                selectedSdNos: _selectedSdNos,
                                mergeSelectable: _mergeSelectable,
                                onToggleSelect: _toggleSelect,
                              ),
                              _MainList(
                                rows: _unpickedRowsForMergeSelect(
                                  grouped['未撿貨(B)']!,
                                  1,
                                ),
                                emptyText: '目前沒有未撿貨(B)的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTapRow: _openItemsRow,
                                onFinishToQcRow: _onFinishToQcRow,
                                onReleaseRow: _onReleaseRow,
                                onRefresh: _reload,
                                selectionMode: _selectionMode &&
                                    _mergeSelectTabIndex == 1,
                                selectedSdNos: _selectedSdNos,
                                mergeSelectable: _mergeSelectable,
                                onToggleSelect: _toggleSelect,
                              ),
                              _MainList(
                                rows: collapsePickingRowsByMergeGroups(
                                  grouped['撿貨中']!,
                                  _cachedMergeGroups,
                                ),
                                emptyText: '目前沒有撿貨中的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTapRow: _openItemsRow,
                                onFinishToQcRow: _onFinishToQcRow,
                                onReleaseRow: _onReleaseRow,
                                onRefresh: _reload,
                                selectionMode: false,
                                selectedSdNos: _selectedSdNos,
                                mergeSelectable: _mergeSelectable,
                                onToggleSelect: _toggleSelect,
                              ),
                              _MainList(
                                rows: collapseDoneTabRowsByMergeGroups(
                                  grouped['撿貨完']!,
                                  _cachedCompletedMergeGroups,
                                ),
                                emptyText: '目前沒有撿貨完成的揀貨單',
                                service: _service,
                                showDateOnCards: widget.showDateOnCards,
                                canFinishToQcBySdNo: _canFinishToQcBySdNo,
                                onTapRow: _openItemsRow,
                                onFinishToQcRow: _onFinishToQcRow,
                                onReleaseRow: _onReleaseRow,
                                onRefresh: _reload,
                                selectionMode: false,
                                selectedSdNos: _selectedSdNos,
                                mergeSelectable: _mergeSelectable,
                                onToggleSelect: _toggleSelect,
                              ),
                              _CannotPickTodayTab(
                                future: _futureCannotPick,
                                service: _service,
                                mainBySdNo: {
                                  for (final m in mains) m.sdNo: m,
                                },
                                onRefresh: () async {
                                  setState(() {
                                    _futureCannotPick =
                                        _service.fetchCannotPickToday(all: true);
                                  });
                                  await _futureCannotPick;
                                },
                              ),
                              _CannotPickAbnormalTab(
                                future: _futureCannotPickAbnormal,
                                service: _service,
                                mainBySdNo: {
                                  for (final m in mains) m.sdNo: m,
                                },
                                onRefresh: () async {
                                  setState(() {
                                    _futureCannotPickAbnormal =
                                        _loadCannotPickAbnormalForTab();
                                  });
                                  await _futureCannotPickAbnormal;
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

  /// 多選合併時依通路+件數少優先排序，方便勾選；取消多選則維持 [_groupMainByStatus] 原順序。
  List<List<PickListMain>> _unpickedRowsForMergeSelect(
    List<PickListMain> mains,
    int areaTabIndex,
  ) {
    if (!_selectionMode || _mergeSelectTabIndex != areaTabIndex) {
      return mains.map((m) => <PickListMain>[m]).toList();
    }
    final sorted = sortMergeMainsForPickOrder(List<PickListMain>.of(mains));
    return sorted.map((m) => <PickListMain>[m]).toList();
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

  Future<void> _openItemsRow(List<PickListMain> row) async {
    if (row.isEmpty) return;
    if (row.length >= 2) {
      final mergeReadOnly =
          row.every((m) => m.isPickedDoneStage || m.isReadyToSortStage);
      if (mergeReadOnly) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PickListItemsScreen(
              main: row.first,
              mergeMains: row,
              employeeId: widget.employeeId ?? '',
              service: _service,
              readOnly: true,
              onFinishedToQcAndPop: () {
                _tabController.animateTo(_tabDone);
                _reload();
              },
            ),
          ),
        );
        if (mounted) _reload();
        return;
      }
      if (row.any((m) => m.normalizedLockStatus == 'locked_by_other')) {
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PickListItemsScreen(
            main: row.first,
            mergeMains: row,
            employeeId: widget.employeeId ?? '',
            service: _service,
            readOnly: false,
            onFinishedToQcAndPop: () {
              _tabController.animateTo(_tabDone);
              _reload();
            },
          ),
        ),
      );
      if (mounted) _reload();
      return;
    }
    final main = row.first;
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
          MaterialPageRoute<void>(
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

  Future<void> _onFinishToQcRow(List<PickListMain> row) async {
    if (row.isEmpty) return;
    if (row.length >= 2) {
      try {
        final canFinish = await _canFinishToQcForMergeRow(row);
        if (!canFinish) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('請先將所有項目標記為完成或找不到')),
          );
          return;
        }
        if (!mounted) return;
        final confirmed = await _confirmFinishToQcMerge(row);
        if (!confirmed) return;
        for (final m in row) {
          await _service.finishToQc(m.sdNo);
        }
        await addCompletedMergeGroup(row.map((m) => m.sdNo).toList());
        await removePickingMergeGroup(row.map((m) => m.sdNo).toList());
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
      return;
    }
    try {
      final main = row.first;
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

  Future<void> _onReleaseRow(List<PickListMain> row) async {
    if (row.isEmpty) return;
    if (row.length >= 2) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('釋放合併揀貨'),
          content: SingleChildScrollView(
            child: Text(
              '確定釋放以下 ${row.length} 張？\n\n'
              '${row.map((m) => m.sdNo).join('\n')}',
            ),
          ),
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
        for (final m in row) {
          await _service.unlock(m.sdNo);
        }
        await removePickingMergeGroup(row.map((m) => m.sdNo).toList());
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
      return;
    }
    try {
      await _service.unlock(row.first.sdNo);
      await removePickingMergeGroupsTouchingSdNo(row.first.sdNo);
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

const List<String> _abnormalRoutingResults = [
  '缺書',
  '人為錯誤揀錯書',
  '人為錯誤誤按完成',
];
const Set<String> _abnormalRoutingResultSet = {..._abnormalRoutingResults};
const Set<String> _directToAbnormalReasons = _abnormalRoutingResultSet;

bool _shouldRouteToAbnormal(CannotPickReport report) {
  final reason = report.reason.trim();
  final handlingResult = report.handlingResult?.trim() ?? '';
  return _directToAbnormalReasons.contains(reason) ||
      _directToAbnormalReasons.contains(handlingResult);
}

class _SummaryData {
  _SummaryData({this.summary, this.myToday});
  final MainSummary? summary;
  final MyTodayResponse? myToday;
}

class _CannotPickTodayTab extends StatelessWidget {
  const _CannotPickTodayTab({
    required this.future,
    required this.service,
    required this.mainBySdNo,
    required this.onRefresh,
  });

  final Future<List<CannotPickReport>>? future;
  final PickListService service;
  final Map<String, PickListMain> mainBySdNo;
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

        final items =
            (snapshot.data ?? [])
                .where((r) => !_shouldRouteToAbnormal(r))
                .toList();
        final grouped = <String, List<CannotPickReport>>{};
        for (final r in items) {
          grouped.putIfAbsent(r.sdNo, () => <CannotPickReport>[]).add(r);
        }
        final groups = grouped.entries.map((entry) {
          final reports = entry.value.toList()
            ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
          return _CannotPickOrderGroup(
            sdNo: entry.key,
            main: mainBySdNo[entry.key],
            reports: reports,
          );
        }).toList()
          ..sort((a, b) => b.latestReportedAt.compareTo(a.latestReportedAt));

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: groups.isEmpty
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
                  itemCount: groups.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final g = groups[index];
                    final main = g.main;
                    final channel = main?.channelDisplayText ?? '-';
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          final movedToAbnormal =
                              await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => _CannotPickOrderDetailScreen(
                                    group: g,
                                    service: service,
                                  ),
                                ),
                              );
                          if (movedToAbnormal == true) {
                            await onRefresh();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已移至分貨異常分頁'),
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '揀貨單號：${g.sdNo}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text('流程：找不到'),
                              const SizedBox(height: 4),
                              Text('通路：$channel'),
                              const SizedBox(height: 4),
                              Text('件數：${g.reports.length}'),
                              const SizedBox(height: 8),
                              Text(
                                '最近回報：${_fmt(g.latestReportedAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

}

class _CannotPickOrderGroup {
  _CannotPickOrderGroup({
    required this.sdNo,
    required this.reports,
    this.main,
  });

  final String sdNo;
  final PickListMain? main;
  final List<CannotPickReport> reports;

  DateTime get latestReportedAt =>
      reports.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : reports.first.reportedAt;
}

const List<String> _handlingResults = ['有書', ..._abnormalRoutingResults];
const Set<String> _handlingNeedsCorrectLogcode = _abnormalRoutingResultSet;
const List<String> _abnormalResults = ['書在儲位上', '上架錯誤', '遺失', '損壞無庫存', '其他'];

class _CannotPickOrderDetailScreen extends StatefulWidget {
  const _CannotPickOrderDetailScreen({
    required this.group,
    required this.service,
  });

  final _CannotPickOrderGroup group;
  final PickListService service;

  @override
  State<_CannotPickOrderDetailScreen> createState() =>
      _CannotPickOrderDetailScreenState();
}

class _CannotPickOrderDetailScreenState extends State<_CannotPickOrderDetailScreen> {
  late List<CannotPickReport> _reports;
  final Map<int, String?> _handlingById = {};
  final Map<int, TextEditingController> _correctLogcodeControllers = {};
  final Set<int> _saving = {};

  @override
  void initState() {
    super.initState();
    _reports = List<CannotPickReport>.from(widget.group.reports);
    for (final r in _reports) {
      _handlingById[r.id] = r.handlingResult;
      _correctLogcodeControllers[r.id] = TextEditingController(
        text: r.correctLogcode ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _correctLogcodeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '-';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String? _resolveImageUrl(CannotPickReport report) {
    final raw = report.imageUrl?.trim() ?? '';
    if (raw.isNotEmpty) {
      return raw.startsWith('http')
          ? raw
          : Uri.parse(ApiConfig().uploadBase).resolve(raw).toString();
    }
    if (report.prodId.isNotEmpty) {
      return 'https://media.taaze.tw/showLargeImage.html?sc=${report.prodId}&height=170&width=250';
    }
    return null;
  }

  Future<void> _saveHandling(CannotPickReport report) async {
    final handling = _handlingById[report.id];
    if (handling == null || handling.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先選擇處理結果')));
      return;
    }
    final correctLogcode =
        (_correctLogcodeControllers[report.id]?.text ?? '').trim();
    if (_handlingNeedsCorrectLogcode.contains(handling) &&
        correctLogcode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('此處理結果需輸入正確書籍物流條碼')));
      return;
    }
    setState(() => _saving.add(report.id));
    try {
      await widget.service.updateCannotPickHandling(
        id: report.id,
        handlingResult: handling,
        correctLogcode: correctLogcode.isEmpty ? null : correctLogcode,
      );
      if (!mounted) return;
      setState(() {
        final idx = _reports.indexWhere((e) => e.id == report.id);
        if (idx >= 0) {
          final prev = _reports[idx];
          _reports[idx] = CannotPickReport(
            id: prev.id,
            sdNo: prev.sdNo,
            prodId: prev.prodId,
            rkId: prev.rkId,
            reason: prev.reason,
            logcode: prev.logcode,
            qty: prev.qty,
            remark: prev.remark,
            reportedAt: prev.reportedAt,
            reportedByName: prev.reportedByName,
            reportedByPhone: prev.reportedByPhone,
            title: prev.title,
            imageUrl: prev.imageUrl,
            handlingResult: handling,
            correctLogcode: correctLogcode.isEmpty ? null : correctLogcode,
            abnormalResult: prev.abnormalResult,
            abnormalRemark: prev.abnormalRemark,
            abnormalUpdatedAt: prev.abnormalUpdatedAt,
            abnormalUpdatedBy: prev.abnormalUpdatedBy,
          );
        }
      });
      if (_abnormalRoutingResultSet.contains(handling)) {
        Navigator.of(context).pop(true);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已更新處理結果')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新失敗: $e')));
    } finally {
      if (mounted) setState(() => _saving.remove(report.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('找不到明細 ${widget.group.sdNo}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final r = _reports[index];
          final selectedHandling = _handlingById[r.id];
          final requiresCorrect =
              selectedHandling != null &&
              _handlingNeedsCorrectLogcode.contains(selectedHandling);
          final who = (r.reportedByName != null && r.reportedByName!.isNotEmpty)
              ? r.reportedByName!
              : (r.reportedByPhone ?? '-');
          final imageUrl = _resolveImageUrl(r);
          final qtyText = r.qty == null ? '-' : '${r.qty}';
          final saving = _saving.contains(r.id);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        height: 112,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: imageUrl == null
                              ? Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported),
                                )
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child:
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title?.isNotEmpty == true ? r.title! : '（無書名）',
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text('店內碼：${r.prodId}'),
                            if (r.logcode != null && r.logcode!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('物流條碼：${r.logcode}'),
                            ],
                            const SizedBox(height: 4),
                            Text('數量：$qtyText'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _chip(context, '櫃號', r.rkId),
                      _chip(context, '揀不到原因', r.reason),
                      _chip(context, '回報者', who),
                    ],
                  ),
                  if (r.remark != null && r.remark!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('備註：${r.remark}'),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedHandling,
                    decoration: const InputDecoration(
                      labelText: '處理結果',
                      border: OutlineInputBorder(),
                    ),
                    items: _handlingResults
                        .map(
                          (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) {
                            setState(() {
                              _handlingById[r.id] = value;
                            });
                          },
                  ),
                  if (requiresCorrect) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _correctLogcodeControllers[r.id],
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: '正確書籍物流條碼',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: saving ? null : () => _saveHandling(r),
                        child: Text(saving ? '儲存中...' : '儲存處理結果'),
                      ),
                      if (r.handlingResult != null && r.handlingResult!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            '目前：${r.handlingResult}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
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

class _CannotPickAbnormalTab extends StatelessWidget {
  const _CannotPickAbnormalTab({
    required this.future,
    required this.service,
    required this.mainBySdNo,
    required this.onRefresh,
  });

  final Future<List<CannotPickReport>>? future;
  final PickListService service;
  final Map<String, PickListMain> mainBySdNo;
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
        final items = snapshot.data ?? [];
        final grouped = <String, List<CannotPickReport>>{};
        for (final r in items) {
          grouped.putIfAbsent(r.sdNo, () => <CannotPickReport>[]).add(r);
        }
        final groups = grouped.entries.map((entry) {
          final reports = entry.value.toList()
            ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
          return _CannotPickOrderGroup(
            sdNo: entry.key,
            main: mainBySdNo[entry.key],
            reports: reports,
          );
        }).toList()
          ..sort((a, b) => b.latestReportedAt.compareTo(a.latestReportedAt));
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: groups.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 48),
                    Center(child: Text('目前沒有分貨異常案件')),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: groups.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final g = groups[index];
                    final main = g.main;
                    final channel = main?.channelDisplayText ?? '-';
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _CannotPickAbnormalDetailScreen(
                                group: g,
                                service: service,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '揀貨單號：${g.sdNo}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text('流程：分貨異常'),
                              const SizedBox(height: 4),
                              Text('通路：$channel'),
                              const SizedBox(height: 4),
                              Text('件數：${g.reports.length}'),
                              const SizedBox(height: 8),
                              Text(
                                '最近回報：${_fmt(g.latestReportedAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _CannotPickAbnormalDetailScreen extends StatefulWidget {
  const _CannotPickAbnormalDetailScreen({
    required this.group,
    required this.service,
  });

  final _CannotPickOrderGroup group;
  final PickListService service;

  @override
  State<_CannotPickAbnormalDetailScreen> createState() =>
      _CannotPickAbnormalDetailScreenState();
}

class _CannotPickAbnormalDetailScreenState extends State<_CannotPickAbnormalDetailScreen> {
  late List<CannotPickReport> _reports;
  final Map<int, String?> _abnormalById = {};
  final Map<int, TextEditingController> _abnormalRemarkControllers = {};
  final Set<int> _saving = {};

  @override
  void initState() {
    super.initState();
    _reports = List<CannotPickReport>.from(widget.group.reports);
    for (final r in _reports) {
      _abnormalById[r.id] = r.abnormalResult;
      _abnormalRemarkControllers[r.id] = TextEditingController(
        text: r.abnormalRemark ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _abnormalRemarkControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '-';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String? _resolveImageUrl(CannotPickReport report) {
    final raw = report.imageUrl?.trim() ?? '';
    if (raw.isNotEmpty) {
      return raw.startsWith('http')
          ? raw
          : Uri.parse(ApiConfig().uploadBase).resolve(raw).toString();
    }
    if (report.prodId.isNotEmpty) {
      return 'https://media.taaze.tw/showLargeImage.html?sc=${report.prodId}&height=170&width=250';
    }
    return null;
  }

  Future<void> _saveAbnormal(CannotPickReport report) async {
    final abnormalResult = _abnormalById[report.id];
    if (abnormalResult == null || abnormalResult.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先選擇處理結果')));
      return;
    }
    final abnormalRemark =
        (_abnormalRemarkControllers[report.id]?.text ?? '').trim();
    if (abnormalResult == '其他' && abnormalRemark.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('選擇其他時需填寫原因')));
      return;
    }
    setState(() => _saving.add(report.id));
    try {
      await widget.service.updateCannotPickAbnormalResult(
        id: report.id,
        abnormalResult: abnormalResult,
        abnormalRemark: abnormalRemark.isEmpty ? null : abnormalRemark,
      );
      if (!mounted) return;
      setState(() {
        final idx = _reports.indexWhere((e) => e.id == report.id);
        if (idx >= 0) {
          final prev = _reports[idx];
          _reports[idx] = CannotPickReport(
            id: prev.id,
            sdNo: prev.sdNo,
            prodId: prev.prodId,
            rkId: prev.rkId,
            reason: prev.reason,
            logcode: prev.logcode,
            qty: prev.qty,
            remark: prev.remark,
            reportedAt: prev.reportedAt,
            reportedByName: prev.reportedByName,
            reportedByPhone: prev.reportedByPhone,
            title: prev.title,
            imageUrl: prev.imageUrl,
            handlingResult: prev.handlingResult,
            correctLogcode: prev.correctLogcode,
            abnormalResult: abnormalResult,
            abnormalRemark: abnormalRemark.isEmpty ? null : abnormalRemark,
            abnormalUpdatedAt: DateTime.now(),
            abnormalUpdatedBy: prev.abnormalUpdatedBy,
          );
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已更新分貨異常結果')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新失敗: $e')));
    } finally {
      if (mounted) setState(() => _saving.remove(report.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('分貨異常 ${widget.group.sdNo}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final r = _reports[index];
          final saving = _saving.contains(r.id);
          final abnormalResult = _abnormalById[r.id];
          final needsRemark = abnormalResult == '其他';
          final imageUrl = _resolveImageUrl(r);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 96,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: imageUrl == null
                              ? Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported),
                                )
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child:
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title?.isNotEmpty == true ? r.title! : '（無書名）',
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text('店內碼：${r.prodId}'),
                            if (r.logcode != null && r.logcode!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('物流條碼：${r.logcode}'),
                            ],
                            if (r.correctLogcode != null &&
                                r.correctLogcode!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('正確物流條碼：${r.correctLogcode}'),
                            ],
                            const SizedBox(height: 2),
                            Text('第一層處理：${r.handlingResult ?? '-'}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: abnormalResult,
                    decoration: const InputDecoration(
                      labelText: '分貨異常處理結果',
                      border: OutlineInputBorder(),
                    ),
                    items: _abnormalResults
                        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) {
                            setState(() => _abnormalById[r.id] = value);
                          },
                  ),
                  if (needsRemark) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _abnormalRemarkControllers[r.id],
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: '其他原因',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: saving ? null : () => _saveAbnormal(r),
                        child: Text(saving ? '儲存中...' : '儲存分貨異常結果'),
                      ),
                      if (r.abnormalResult != null && r.abnormalResult!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            '目前：${r.abnormalResult}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                  if (r.abnormalRemark != null && r.abnormalRemark!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('目前備註：${r.abnormalRemark}'),
                  ],
                  const SizedBox(height: 6),
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
    required this.rows,
    required this.emptyText,
    required this.service,
    required this.showDateOnCards,
    required this.canFinishToQcBySdNo,
    required this.onTapRow,
    required this.onFinishToQcRow,
    required this.onReleaseRow,
    required this.onRefresh,
    this.selectionMode = false,
    required this.selectedSdNos,
    required this.mergeSelectable,
    required this.onToggleSelect,
  });

  /// 每列一張單，或合併多張（[撿貨中]／[撿貨完] 可能為本機摺疊之多張一列）
  final List<List<PickListMain>> rows;
  final String emptyText;
  final PickListService service;
  final bool showDateOnCards;
  final Map<String, bool> canFinishToQcBySdNo;
  final Future<void> Function(List<PickListMain> row) onTapRow;
  final Future<void> Function(List<PickListMain> row) onFinishToQcRow;
  final Future<void> Function(List<PickListMain> row) onReleaseRow;
  final Future<void> Function() onRefresh;
  final bool selectionMode;
  final Set<String> selectedSdNos;
  final bool Function(PickListMain) mergeSelectable;
  final void Function(PickListMain) onToggleSelect;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.isEmpty ? 1 : rows.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (rows.isEmpty) {
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
          final row = rows[index];
          final main = row.first;
          final finishKey = row.length >= 2
              ? mergeFinishEligibilityKey(row.map((m) => m.sdNo))
              : main.sdNo;
          final canFinish = canFinishToQcBySdNo[finishKey] ?? false;
          return _PickMainCard(
            row: row,
            showDate: showDateOnCards,
            canFinishToQc: canFinish,
            onTap: () => onTapRow(row),
            onFinishToQc: () => onFinishToQcRow(row),
            onRelease: () => onReleaseRow(row),
            selectionMode: selectionMode,
            selected: row.length == 1 && selectedSdNos.contains(main.sdNo),
            mergeSelectable: row.length == 1 && mergeSelectable(main),
            onToggleSelect: () => onToggleSelect(main),
          );
        },
      ),
    );
  }
}

class _PickMainCard extends StatelessWidget {
  const _PickMainCard({
    required this.row,
    this.showDate = false,
    this.canFinishToQc = false,
    this.onTap,
    this.onFinishToQc,
    this.onRelease,
    this.selectionMode = false,
    this.selected = false,
    this.mergeSelectable = false,
    this.onToggleSelect,
  });

  /// 一列一張，或合併多張
  final List<PickListMain> row;
  final bool showDate;
  final bool canFinishToQc;
  final VoidCallback? onTap;
  final VoidCallback? onFinishToQc;
  final VoidCallback? onRelease;
  final bool selectionMode;
  final bool selected;
  final bool mergeSelectable;
  final VoidCallback? onToggleSelect;

  PickListMain get main => row.first;

  String _dateText(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isMerged = row.length >= 2;
    final status = main.lockStatus;
    final isAvailable = !isMerged && main.isAvailableToPick;
    final isLockedByMe = isMerged
        ? row.every((m) => m.normalizedLockStatus == 'locked_by_me')
        : main.normalizedLockStatus == 'locked_by_me';
    final isLockedByOther = !isMerged && main.normalizedLockStatus == 'locked_by_other';
    final isDone = !isMerged && main.isPickedDoneStage;
    final isReadOnlyFlow =
        !isMerged && (main.isPickedDoneStage || main.isReadyToSortStage);
    final mergedReadOnlyBrowse = isMerged &&
        row.every((m) => m.isPickedDoneStage || m.isReadyToSortStage);
    final canTap = isMerged
        ? (isLockedByMe || mergedReadOnlyBrowse)
        : (isReadOnlyFlow || (isAvailable || isLockedByMe));

    final sdNoTitle = isMerged
        ? '合併揀貨（${row.length} 張）'
        : '揀貨單號：${main.sdNo}';
    final mergedOrdered =
        isMerged ? mergeCardMainsOrdered(row) : const <PickListMain>[];

    num? ttlSum;
    if (isMerged) {
      num s = 0;
      var hasAny = false;
      for (final m in row) {
        final q = m.ttlMustQty;
        if (q != null) {
          s += q;
          hasAny = true;
        }
      }
      ttlSum = hasAny ? s : null;
    }

    final primaryBar = SizedBox(
      width: 12,
      height: isMerged ? null : 120,
      child: Container(color: Theme.of(context).colorScheme.primary),
    );

    final innerRow = Row(
      crossAxisAlignment:
          isMerged ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        if (selectionMode) ...[
          Checkbox(
            value: selected,
            onChanged: mergeSelectable
                ? (_) => onToggleSelect?.call()
                : null,
          ),
          const SizedBox(width: 4),
        ],
        primaryBar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sdNoTitle,
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
              if (isMerged) ...[
                const SizedBox(height: 6),
                Text(
                  '揀貨單號：',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                for (var i = 0; i < mergedOrdered.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(text: mergedOrdered[i].sdNo),
                          TextSpan(
                            text: '（${chineseOrdinal(i + 1)}）',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '流程：',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                for (var i = 0; i < mergedOrdered.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: '（${chineseOrdinal(i + 1)}）',
                            style: const TextStyle(color: Colors.red),
                          ),
                          TextSpan(
                            text: ': ${mergedOrdered[i].flowTabLabel} '
                                '(${mergedOrdered[i].flowAreaDisplayText ?? '—'})',
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '通路：',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                for (var i = 0; i < mergedOrdered.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: '（${chineseOrdinal(i + 1)}）',
                            style: const TextStyle(color: Colors.red),
                          ),
                          TextSpan(
                            text: ': '
                                '${mergedOrdered[i].channelDisplayText ?? '-'} / '
                                '${mergedOrdered[i].mallDisplayText ?? '商城（-）'}',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (!isMerged) ...[
                const SizedBox(height: 4),
                Text(
                  '流程：${main.flowTabLabel}${main.flowAreaDisplayText != null ? ' (${main.flowAreaDisplayText})' : ''}',
                ),
                const SizedBox(height: 4),
                Text(
                  '通路：${main.channelDisplayText ?? '-'} / ${main.mallDisplayText ?? '商城（-）'}',
                ),
              ],
              const SizedBox(height: 4),
              Text(
                isMerged
                    ? '合計件數：${ttlSum ?? '-'}'
                    : '件數：${main.ttlMustQty ?? '-'}',
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
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode
            ? (mergeSelectable ? onToggleSelect : null)
            : (canTap ? onTap : null),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: isMerged ? IntrinsicHeight(child: innerRow) : innerRow,
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
    this.sourceOrderLabel,
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
  /// 合併檢視：顯示來源單號與中文後綴，例如 FC…（一）
  final String? sourceOrderLabel;

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
                        if (sourceOrderLabel != null &&
                            sourceOrderLabel!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final labelStyle = Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                    fontWeight: FontWeight.w600,
                                  );
                              final (pre, suf) = splitMergeOrdinalSuffix(
                                sourceOrderLabel!,
                              );
                              return Text.rich(
                                TextSpan(
                                  style: labelStyle,
                                  children: [
                                    const TextSpan(text: '揀貨單：'),
                                    TextSpan(text: pre),
                                    if (suf != null)
                                      TextSpan(
                                        text: suf,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
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
    this.mergeMains,
    required this.employeeId,
    this.service,
    this.readOnly = false,
    this.onFinishedToQcAndPop,
  });

  final PickListMain main;
  /// 長度 ≥2 時為合併檢視（品項依櫃號合併排序，並顯示中文後綴）。
  final List<PickListMain>? mergeMains;
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
  bool get _isMerge =>
      widget.mergeMains != null && widget.mergeMains!.length >= 2;
  /// 合併模式：揀貨單號 → `（一）`
  Map<String, String> _mergeSdNoToSuffix = {};
  /// 合併 AppBar：品項數多到少之標題列
  List<String> _mergeOrderedTitles = [];
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

  static String _progressKeySingle(String sdNo) =>
      'pick_list_progress_${sdNo.replaceAll(RegExp(r'[^\w\-]'), '_')}';

  String _progressStorageKey() {
    if (_isMerge) {
      return mergeProgressKey(widget.mergeMains!.map((m) => m.sdNo));
    }
    return _progressKeySingle(widget.main.sdNo);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final emp =
          widget.employeeId.isNotEmpty ? widget.employeeId : null;
      late final List<PickListItem> data;
      late final Map<String, String> mergeSuffixes;
      late final List<String> mergeOrderedTitles;
      if (_isMerge) {
        final mains = widget.mergeMains!;
        final lists = await Future.wait(
          mains.map(
            (m) => _service.fetchItemsBySdNo(
              employeeId: emp,
              sdNo: m.sdNo,
              main: m,
            ),
          ),
        );
        final bundles = [
          for (var i = 0; i < mains.length; i++)
            (main: mains[i], items: lists[i]),
        ];
        final plan = buildMergePlan(bundles);
        data = plan.mergedItems;
        mergeSuffixes = plan.sdNoToSuffix;
        mergeOrderedTitles = plan.orderedTitlesForAppBar;
      } else {
        mergeSuffixes = {};
        mergeOrderedTitles = [];
        data = await _service.fetchItemsBySdNo(
          employeeId: emp,
          sdNo: widget.main.sdNo,
          main: widget.main,
        );
      }
      if (!mounted) return;
      final itemKeys =
          data.map((e) => itemKeyForPick(e, merge: _isMerge)).toSet();
      final (completed, notFound) = _isReadOnly
          ? (<String>{}, <String>{})
          : await _restoreProgress(itemKeys);
      if (!mounted) return;
      setState(() {
        _items = data;
        _mergeSdNoToSuffix = mergeSuffixes;
        _mergeOrderedTitles = mergeOrderedTitles;
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
        _mergeOrderedTitles = [];
        _mergeSdNoToSuffix = {};
      });
    }
  }

  Future<(Set<String>, Set<String>)> _restoreProgress(
    Set<String> validKeys,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_progressStorageKey());
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
        _progressStorageKey(),
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
      await prefs.remove(_progressStorageKey());
    } catch (_) {}
  }

  Future<void> _unlockAllMerged() async {
    if (!_isMerge || _isReadOnly) return;
    final mains = widget.mergeMains!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('釋放全部'),
        content: Text(
          '確定釋放以下 ${mains.length} 張揀貨單？\n${mains.map((m) => m.sdNo).join('\n')}',
        ),
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
      for (final m in mains) {
        await _service.unlock(m.sdNo);
      }
      if (!mounted) return;
      await _clearProgress();
      if (!mounted) return;
      await removePickingMergeGroup(mains.map((m) => m.sdNo).toList());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('釋放失敗: $e')));
    }
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
    final mains = _isMerge ? widget.mergeMains! : <PickListMain>[widget.main];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認完成至待驗收'),
        content: SingleChildScrollView(
          child: Text(
            mains.length > 1
                ? '將對以下 ${mains.length} 張揀貨單標記為完成至待驗收：\n\n'
                    '${mains.map((m) => m.sdNo).join('\n')}'
                : '確定將揀貨單 ${widget.main.sdNo} 標記為完成至待驗收？',
          ),
        ),
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
      for (final m in mains) {
        await _service.finishToQc(m.sdNo);
      }
      if (!mounted) return;
      await _clearProgress();
      if (!mounted) return;
      if (_isMerge) {
        await addCompletedMergeGroup(
          widget.mergeMains!.map((m) => m.sdNo).toList(),
        );
        await removePickingMergeGroup(
          widget.mergeMains!.map((m) => m.sdNo).toList(),
        );
      }
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
        title: _isMerge && _mergeOrderedTitles.isNotEmpty
            ? Text.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.titleSmall,
                  children: [
                    for (var i = 0; i < _mergeOrderedTitles.length; i++) ...[
                      if (i > 0) const TextSpan(text: ' · '),
                      _textSpanWithRedMergeOrdinal(
                        _mergeOrderedTitles[i],
                        Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                '揀貨單 ${widget.main.sdNo}',
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          if (!_isReadOnly && _isMerge)
            TextButton(
              onPressed: _unlockAllMerged,
              child: const Text('釋放全部'),
            ),
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
                        sourceOrderLabel: _isMerge &&
                                pageItem.sdNo != null &&
                                pageItem.sdNo!.isNotEmpty
                            ? '${pageItem.sdNo}${_mergeSdNoToSuffix[pageItem.sdNo] ?? ''}'
                            : null,
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
        sdNo: item.sdNo ?? widget.main.sdNo,
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
        sdNo: item.sdNo ?? widget.main.sdNo,
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

  static const _cannotPickReasons = [
    '缺貨',
    '損壞',
    '找不到',
    '其他',
  ];

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

  String _itemKey(PickListItem item) =>
      itemKeyForPick(item, merge: _isMerge);

  List<int> _filteredIndexes() {
    final result = <int>[];
    if (_showCompleted) {
      // 已撿貨顯示倒序，讓使用者優先看到剛剛完成的項目。
      for (var i = _items.length - 1; i >= 0; i--) {
        final key = _itemKey(_items[i]);
        final isDone = _completed.contains(key);
        if (isDone) result.add(i);
      }
      return result;
    }

    // 找不到項目放前面且倒序，方便回看剛剛回報的品項。
    for (var i = _items.length - 1; i >= 0; i--) {
      final key = _itemKey(_items[i]);
      final isDone = _completed.contains(key);
      final isNotFound = _notFound.contains(key);
      if (!isDone && isNotFound) {
        result.add(i);
      }
    }

    // 其餘未撿貨項目維持原始順序。
    for (var i = 0; i < _items.length; i++) {
      final key = _itemKey(_items[i]);
      final isDone = _completed.contains(key);
      final isNotFound = _notFound.contains(key);
      if (!isDone && !isNotFound) {
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
