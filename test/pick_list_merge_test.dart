import 'package:booksearch_app/models/pick_list_item.dart';
import 'package:booksearch_app/models/pick_list_main.dart';
import 'package:booksearch_app/utils/pick_list_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chineseOrdinal', () {
    test('1-10', () {
      expect(chineseOrdinal(1), '一');
      expect(chineseOrdinal(9), '九');
      expect(chineseOrdinal(10), '十');
    });
    test('11-19', () {
      expect(chineseOrdinal(11), '十一');
      expect(chineseOrdinal(15), '十五');
    });
  });

  group('buildMergePlan', () {
    /// 2025-06-04 週三（台灣），走平日通路序
    final weekdayAt = DateTime.utc(2025, 6, 4, 4, 0);

    test('weekday: 灰熊 before 蝦皮店到店; suffix by channel then ttl asc; rk merge sort', () {
      final grizzly = PickListMain(sdNo: 'A', companyId: 'IRD', ttlMustQty: 99);
      final shopeeStore = PickListMain(sdNo: 'B', cnno: 'SPE', ttlMustQty: 1);
      final plan = buildMergePlan(
        [
          (
            main: shopeeStore,
            items: [
              PickListItem(
                id: 'R2',
                productId: 'p1',
                title: 't',
                imageUrl: '',
                rkId: 'R2',
                sdNo: 'B',
              ),
            ],
          ),
          (
            main: grizzly,
            items: [
              PickListItem(
                id: 'R1',
                productId: 'p2',
                title: 't',
                imageUrl: '',
                rkId: 'R1',
                sdNo: 'A',
              ),
              PickListItem(
                id: 'R3',
                productId: 'p3',
                title: 't',
                imageUrl: '',
                rkId: 'R3',
                sdNo: 'A',
              ),
            ],
          ),
        ],
        mergeOrderAt: weekdayAt,
      );
      expect(plan.sdNoToSuffix['A'], '（一）');
      expect(plan.sdNoToSuffix['B'], '（二）');
      expect(plan.orderedTitlesForAppBar.first, contains('A'));
      expect(plan.orderedTitlesForAppBar.first, contains('（一）'));
      expect(plan.mergedItems.map((e) => e.rkId).toList(), ['R1', 'R2', 'R3']);
    });

    test('same tier: lower ttl first then sd_no', () {
      final plan = buildMergePlan(
        [
          (
            main: PickListMain(sdNo: 'Z', ttlMustQty: 2),
            items: [
              PickListItem(id: 'x', productId: 'p', title: 't', imageUrl: '', sdNo: 'Z'),
            ],
          ),
          (
            main: PickListMain(sdNo: 'M', ttlMustQty: 1),
            items: [
              PickListItem(id: 'x', productId: 'p', title: 't', imageUrl: '', sdNo: 'M'),
            ],
          ),
        ],
        mergeOrderAt: weekdayAt,
      );
      expect(plan.sdNoToSuffix['M'], '（一）');
      expect(plan.sdNoToSuffix['Z'], '（二）');
    });

    test('holiday: 蝦皮店到店 before 大榮', () {
      final saturdayTw = DateTime.utc(2025, 6, 7, 4, 0);
      final plan = buildMergePlan(
        [
          (
            main: PickListMain(sdNo: 'H1', cnno: 'H'),
            items: [
              PickListItem(id: 'a', productId: 'p', title: 't', imageUrl: '', sdNo: 'H1'),
            ],
          ),
          (
            main: PickListMain(sdNo: 'S1', cnno: 'SPE'),
            items: [
              PickListItem(id: 'b', productId: 'p', title: 't', imageUrl: '', sdNo: 'S1'),
            ],
          ),
        ],
        mergeOrderAt: saturdayTw,
      );
      expect(plan.sdNoToSuffix['S1'], '（一）');
      expect(plan.sdNoToSuffix['H1'], '（二）');
    });
  });

  group('mergeChannelTier', () {
    test('weekday: IRD before 大榮 before SPE', () {
      final grizzly = PickListMain(sdNo: 'a', companyId: 'IRD');
      final h = PickListMain(sdNo: 'b', cnno: 'H');
      final spe = PickListMain(sdNo: 'c', cnno: 'SPE');
      expect(mergeChannelTier(grizzly, holidayOrder: false), lessThan(mergeChannelTier(h, holidayOrder: false)));
      expect(mergeChannelTier(h, holidayOrder: false), lessThan(mergeChannelTier(spe, holidayOrder: false)));
    });

    test('holiday: SPE before 大榮 H', () {
      final spe = PickListMain(sdNo: 'a', cnno: 'SPE');
      final h = PickListMain(sdNo: 'b', cnno: 'H');
      expect(mergeChannelTier(spe, holidayOrder: true), lessThan(mergeChannelTier(h, holidayOrder: true)));
    });

    test('蝦皮店宅: SPE company + deliver B, cnno not SPE/SPH', () {
      final home = PickListMain(sdNo: 'x', companyId: 'SPE', deliver: 'B', cnno: 'F');
      expect(mergeChannelTier(home, holidayOrder: false), 4);
    });
  });

  group('mergeCardMainsOrdered', () {
    test('same weekday tier: ttl asc then sd_no', () {
      final o = mergeCardMainsOrdered([
        PickListMain(sdNo: 'FC_B', ttlMustQty: 32, cnno: '7'),
        PickListMain(sdNo: 'FC_A', ttlMustQty: 5, cnno: 'F'),
      ]);
      expect(o[0].sdNo, 'FC_A');
      expect(o[1].sdNo, 'FC_B');
    });
    test('single element list unchanged', () {
      final o = mergeCardMainsOrdered([PickListMain(sdNo: 'X')]);
      expect(o.length, 1);
      expect(o.single.sdNo, 'X');
    });
  });

  group('splitMergeOrdinalSuffix', () {
    test('splits full-width ordinal at end', () {
      expect(splitMergeOrdinalSuffix('FC123（一）'), ('FC123', '（一）'));
      expect(splitMergeOrdinalSuffix('A（十一）'), ('A', '（十一）'));
    });
    test('no suffix returns whole string', () {
      expect(splitMergeOrdinalSuffix('FC123'), ('FC123', null));
      expect(splitMergeOrdinalSuffix(''), ('', null));
    });
  });

  group('collapseRowsByMergeGroups', () {
    PickListMain main(String sd, {String? lock}) =>
        PickListMain(sdNo: sd, lockStatus: lock);

    test('done tab collapses full group, singles preserve tab order', () {
      final a = main('A');
      final b = main('B');
      final c = main('C');
      final rows = collapseDoneTabRowsByMergeGroups(
        [a, b, c],
        [
          ['A', 'B'],
        ],
      );
      expect(rows.length, 2);
      expect(rows[0].map((m) => m.sdNo).toList(), ['A', 'B']);
      expect(rows[1].single.sdNo, 'C');
    });

    test('picking requires locked_by_me when memberMust set', () {
      final locked = main('A', lock: 'locked_by_me');
      final other = main('B', lock: 'locked_by_other');
      final rows = collapsePickingRowsByMergeGroups(
        [locked, other],
        [
          ['A', 'B'],
        ],
      );
      expect(rows.length, 2);
      expect(rows[0].single.sdNo, 'A');
      expect(rows[1].single.sdNo, 'B');
    });
  });

  group('itemKeyForPick', () {
    test('merge includes sdNo', () {
      final item = PickListItem(
        id: 'R',
        productId: 'P',
        title: 't',
        imageUrl: '',
        seqNum: '1',
        sdNo: 'FC1',
      );
      expect(itemKeyForPick(item, merge: false), 'R-1-P');
      expect(itemKeyForPick(item, merge: true), 'FC1-R-1-P');
    });
  });
}
