import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pick_list_item.dart';
import '../models/pick_list_main.dart';

const String kPickingMergeGroupsKey = 'pick_list_picking_merge_groups';
const String kCompletedMergeGroupsKey = 'pick_list_completed_merge_groups';

List<List<String>> _decodeMergeGroupsJson(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<List<dynamic>>()
        .map((e) => e.map((x) => x.toString()).toList())
        .where((g) => g.length >= 2)
        .toList();
  } catch (_) {
    return [];
  }
}

/// 列表「完成至待驗收」按鈕是否可點：合併列專用鍵（勿與單張 sd_no 混淆）
String mergeFinishEligibilityKey(Iterable<String> sdNos) {
  final sorted = sdNos.toList()..sort();
  return 'merge:${sorted.join('|')}';
}

bool _sameSortedSdList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final aa = List<String>.of(a)..sort();
  final bb = List<String>.of(b)..sort();
  for (var i = 0; i < aa.length; i++) {
    if (aa[i] != bb[i]) return false;
  }
  return true;
}

Future<List<List<String>>> loadPickingMergeGroups() async {
  final prefs = await SharedPreferences.getInstance();
  return _decodeMergeGroupsJson(prefs.getString(kPickingMergeGroupsKey));
}

Future<void> _savePickingMergeGroups(List<List<String>> groups) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPickingMergeGroupsKey, jsonEncode(groups));
}

/// 成功合併領單後寫入；與既有組別單號重疊者會被取代。
Future<void> addPickingMergeGroup(List<String> sdNos) async {
  if (sdNos.length < 2) return;
  final sorted = List<String>.of(sdNos)..sort();
  final set = sorted.toSet();
  final groups = await loadPickingMergeGroups();
  groups.removeWhere((g) => g.any(set.contains));
  groups.add(sorted);
  await _savePickingMergeGroups(groups);
}

Future<void> removePickingMergeGroup(List<String> sdNos) async {
  if (sdNos.length < 2) return;
  final sorted = List<String>.of(sdNos)..sort();
  final groups = await loadPickingMergeGroups();
  groups.removeWhere((g) => _sameSortedSdList(g, sorted));
  await _savePickingMergeGroups(groups);
}

/// 釋放任一張合併內單據時，整組不再視為合併列。
Future<void> removePickingMergeGroupsTouchingSdNo(String sdNo) async {
  final groups = await loadPickingMergeGroups();
  groups.removeWhere((g) => g.contains(sdNo));
  await _savePickingMergeGroups(groups);
}

Future<List<List<String>>> loadCompletedMergeGroups() async {
  final prefs = await SharedPreferences.getInstance();
  return _decodeMergeGroupsJson(prefs.getString(kCompletedMergeGroupsKey));
}

Future<void> _saveCompletedMergeGroups(List<List<String>> groups) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kCompletedMergeGroupsKey, jsonEncode(groups));
}

/// 合併完成至待驗收後寫入，供 [撿貨完] 分頁摺成與 [撿貨中] 相同卡片版面。
Future<void> addCompletedMergeGroup(List<String> sdNos) async {
  if (sdNos.length < 2) return;
  final sorted = List<String>.of(sdNos)..sort();
  final set = sorted.toSet();
  final groups = await loadCompletedMergeGroups();
  groups.removeWhere((g) => g.any(set.contains));
  groups.add(sorted);
  await _saveCompletedMergeGroups(groups);
}

/// [tabMains] 內依 [mergeGroups] 合併列；[memberMust] 為 null 時只要單號在清單內即可。
List<List<PickListMain>> collapseRowsByMergeGroups(
  List<PickListMain> tabMains,
  List<List<String>> mergeGroups, {
  bool Function(PickListMain m)? memberMust,
}) {
  final bySd = {for (final m in tabMains) m.sdNo: m};
  final used = <String>{};
  final rows = <List<PickListMain>>[];
  for (final g in mergeGroups) {
    if (g.length < 2) continue;
    final members = <PickListMain>[];
    var ok = true;
    for (final sd in g) {
      final m = bySd[sd];
      if (m == null || (memberMust != null && !memberMust(m))) {
        ok = false;
        break;
      }
      members.add(m);
    }
    if (ok && members.length == g.length) {
      rows.add(members);
      used.addAll(g);
    }
  }
  for (final m in tabMains) {
    if (!used.contains(m.sdNo)) {
      rows.add([m]);
    }
  }
  return rows;
}

/// 將 [撿貨中] 清單依本機紀錄的合併組折成多列（每列 1 張或合併多張）。
List<List<PickListMain>> collapsePickingRowsByMergeGroups(
  List<PickListMain> picking,
  List<List<String>> mergeGroups,
) {
  return collapseRowsByMergeGroups(
    picking,
    mergeGroups,
    memberMust: (m) => m.normalizedLockStatus == 'locked_by_me',
  );
}

/// 將 [撿貨完] 清單依「曾合併完成」紀錄折成多列（版面與撿貨中合併卡一致）。
List<List<PickListMain>> collapseDoneTabRowsByMergeGroups(
  List<PickListMain> doneMains,
  List<List<String>> completedMergeGroups,
) {
  return collapseRowsByMergeGroups(doneMains, completedMergeGroups);
}

/// 中文序號：1→一、10→十、11→十一（超過 99 回退阿拉伯數字）
String chineseOrdinal(int n) {
  if (n <= 0) return '';
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (n <= 10) {
    if (n == 10) return '十';
    return digits[n];
  }
  if (n < 20) {
    return '十${digits[n % 10]}';
  }
  if (n < 100) {
    final tens = n ~/ 10;
    final ones = n % 10;
    return '${digits[tens]}十${ones == 0 ? '' : digits[ones]}';
  }
  return n.toString();
}

/// 合併顯示字串若結尾為全形括號中文序號（如 `（一）`），拆成前綴與該段後綴。
(String prefix, String? ordinalSuffix) splitMergeOrdinalSuffix(String display) {
  final m = RegExp(r'（[^）]+）$').firstMatch(display);
  if (m == null) return (display, null);
  final i = m.start;
  return (display.substring(0, i), display.substring(i));
}

// --- 合併撿貨：通路優先序（平日／假日）+ 件數少優先 ---

/// 台灣國定假日（YYYYMMDD），可自行擴充；與週六日皆走假日通路順序。
final Set<String> taiwanMergePickPublicHolidayYyyymmdd = <String>{
  // 例：'20250101', '20250128',
};

/// 以 UTC+8 對齊之曆日（用於假日判斷與 YYYYMMDD）。
DateTime mergeTaiwanCalendarDate(DateTime at) {
  final ms = at.toUtc().millisecondsSinceEpoch + 8 * 3600 * 1000;
  final u = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return DateTime.utc(u.year, u.month, u.day);
}

String mergeTaiwanYyyymmdd(DateTime at) {
  final c = mergeTaiwanCalendarDate(at);
  final y = c.year.toString().padLeft(4, '0');
  final m = c.month.toString().padLeft(2, '0');
  final d = c.day.toString().padLeft(2, '0');
  return '$y$m$d';
}

/// 週六日或 [taiwanMergePickPublicHolidayYyyymmdd] 視為假日排序。
bool isMergePickHolidayOrder(DateTime at) {
  if (taiwanMergePickPublicHolidayYyyymmdd.contains(mergeTaiwanYyyymmdd(at))) {
    return true;
  }
  final wd = mergeTaiwanCalendarDate(at).weekday;
  return wd == DateTime.saturday || wd == DateTime.sunday;
}

/// 通路階層（數字越小越優先）。比對前請用 [PickListMain] 之 companyId / cnno / deliver。
int mergeChannelTier(PickListMain m, {required bool holidayOrder}) {
  final comp = (m.companyId ?? '').trim().toUpperCase();
  final cn = (m.cnno ?? '').trim().toUpperCase();
  final d = (m.deliver ?? '').trim().toUpperCase();

  if (comp == 'IRD') return 0;

  if (!holidayOrder) {
    if (cn == 'H') return 1;
    if (cn == 'SPE') return 2;
    if (cn == 'SPH') return 3;
    if ((comp == 'SPE' || comp == 'SPH') && d == 'B') return 4;
    if (comp == 'TAZ' || d == 'C') return 5;
    return 6;
  }

  if (cn == 'SPE') return 1;
  if (cn == 'SPH') return 2;
  if ((comp == 'SPE' || comp == 'SPH') &&
      d == 'B' &&
      cn != 'SPE' &&
      cn != 'SPH') {
    return 3;
  }
  if (comp == 'TAZ' || d == 'C') return 4;
  if (d != 'S' && d != 'L' && cn != 'H') return 5;
  if (d == 'S' || d == 'L') return 6;
  if (cn == 'H') return 7;
  return 5;
}

num _ttlForMergeSort(PickListMain m) => m.ttlMustQty ?? 0;

/// 合併多選排序：通路階層 → ttl 升序 → sd_no。
int compareMergeMainsPickOrder(
  PickListMain a,
  PickListMain b, {
  required bool holidayOrder,
}) {
  final ta = mergeChannelTier(a, holidayOrder: holidayOrder);
  final tb = mergeChannelTier(b, holidayOrder: holidayOrder);
  final tc = ta.compareTo(tb);
  if (tc != 0) return tc;
  final qa = _ttlForMergeSort(a);
  final qb = _ttlForMergeSort(b);
  final qc = qa.compareTo(qb);
  if (qc != 0) return qc;
  return a.sdNo.compareTo(b.sdNo);
}

/// 合併撿貨用主檔順序（[at] 決定平日／假日；預設現在）。
List<PickListMain> sortMergeMainsForPickOrder(
  List<PickListMain> mains, {
  DateTime? at,
}) {
  if (mains.isEmpty) return [];
  if (mains.length < 2) return List<PickListMain>.of(mains);
  final ref = at ?? DateTime.now();
  final holiday = isMergePickHolidayOrder(ref);
  final sorted = List<PickListMain>.of(mains)
    ..sort((a, b) => compareMergeMainsPickOrder(a, b, holidayOrder: holiday));
  return sorted;
}

/// [撿貨中] 合併卡列印順序：與合併明細（一）（二）相同規則（通路 + 件數少優先 + sd_no）。
List<PickListMain> mergeCardMainsOrdered(List<PickListMain> mains) {
  return sortMergeMainsForPickOrder(mains);
}

int? _parseSeqNum(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

int _comparePickItemsForMerge(PickListItem a, PickListItem b) {
  final ra = (a.rkId != null && a.rkId!.trim().isNotEmpty) ? a.rkId!.trim() : '';
  final rb = (b.rkId != null && b.rkId!.trim().isNotEmpty) ? b.rkId!.trim() : '';
  if (ra.isEmpty && rb.isNotEmpty) return 1;
  if (ra.isNotEmpty && rb.isEmpty) return -1;
  final rk = ra.compareTo(rb);
  if (rk != 0) return rk;

  final sa = _parseSeqNum(a.seqNum);
  final sb = _parseSeqNum(b.seqNum);
  if (sa != null && sb != null && sa != sb) {
    return sa.compareTo(sb);
  }
  final seqStr = (a.seqNum ?? '').compareTo(b.seqNum ?? '');
  if (seqStr != 0) return seqStr;

  final da = a.sdNo ?? '';
  final db = b.sdNo ?? '';
  return da.compareTo(db);
}

class MergePickPlan {
  MergePickPlan({
    required this.mergedItems,
    required this.sdNoToSuffix,
    required this.orderedTitlesForAppBar,
  });

  final List<PickListItem> mergedItems;
  /// 揀貨單號 → `（一）` 形式（全形括號）
  final Map<String, String> sdNoToSuffix;
  final List<String> orderedTitlesForAppBar;
}

/// 依通路（平日／假日）與主檔件數少優先給後綴；品項聯集後先依單順序再依櫃號、序號排序。
MergePickPlan buildMergePlan(
  List<({PickListMain main, List<PickListItem> items})> bundles, {
  DateTime? mergeOrderAt,
}) {
  if (bundles.isEmpty) {
    return MergePickPlan(
      mergedItems: [],
      sdNoToSuffix: {},
      orderedTitlesForAppBar: [],
    );
  }

  final at = mergeOrderAt ?? DateTime.now();
  final holiday = isMergePickHolidayOrder(at);
  final orderedBundles =
      List<({PickListMain main, List<PickListItem> items})>.of(bundles)
        ..sort(
          (a, b) => compareMergeMainsPickOrder(
            a.main,
            b.main,
            holidayOrder: holiday,
          ),
        );

  final sdNoToSuffix = <String, String>{};
  for (var i = 0; i < orderedBundles.length; i++) {
    sdNoToSuffix[orderedBundles[i].main.sdNo] = '（${chineseOrdinal(i + 1)}）';
  }

  final merged = <PickListItem>[];
  for (final b in orderedBundles) {
    merged.addAll(b.items);
  }
  merged.sort(_comparePickItemsForMerge);

  final orderedTitlesForAppBar = [
    for (final b in orderedBundles)
      '${b.main.sdNo}${sdNoToSuffix[b.main.sdNo] ?? ''}',
  ];

  return MergePickPlan(
    mergedItems: merged,
    sdNoToSuffix: sdNoToSuffix,
    orderedTitlesForAppBar: orderedTitlesForAppBar,
  );
}

String mergeProgressKey(Iterable<String> sdNos) {
  final sorted = sdNos.toList()..sort();
  final raw = sorted.join('__');
  return 'pick_list_merge_${raw.replaceAll(RegExp(r'[^\w\-]'), '_')}';
}

/// 單張與合併共用鍵規則；合併時須含 [PickListItem.sdNo] 避免跨單撞鍵。
String itemKeyForPick(PickListItem item, {required bool merge}) {
  final base = '${item.id}-${item.seqNum ?? ''}-${item.productId}';
  if (!merge) return base;
  final sd = item.sdNo ?? '';
  return '$sd-$base';
}
