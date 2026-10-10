import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/putaway.dart';
import '../services/kit_tts_service.dart';
import '../services/putaway_service.dart';
import 'barcode_camera_scan_screen.dart';

enum _Meg { info, ok, warn, error }

/// 上架作業（對齊 C121100M sle_keyin_data：6 碼＝儲位，其他＝物流條碼上架＋１）
class PutawayWorkScreen extends StatefulWidget {
  const PutawayWorkScreen({
    super.key,
    required this.service,
    required this.suNo,
  });

  final PutawayService service;
  final String suNo;

  @override
  State<PutawayWorkScreen> createState() => _PutawayWorkScreenState();
}

class _PutawayWorkScreenState extends State<PutawayWorkScreen>
    with SingleTickerProviderStateMixin {
  final _scanController = TextEditingController();
  final _scanFocus = FocusNode();
  final _tts = KitTtsService();

  /// 掃描框預設聚焦，方便連續刷碼。iPhone 用輸入框旁的按鈕收起鍵盤。
  bool _keepScanFocus = true;
  static final bool _isIOS = defaultTargetPlatform == TargetPlatform.iOS;
  late final TabController _tabs = TabController(length: 3, vsync: this);
  static const _diffTab = 2;

  /// 已上架頁籤排序：false＝依條碼、true＝依儲位
  bool _placedByRack = false;

  PutawaySuDetail? _su;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String _rkId = '';
  int _rackQty = 0;
  String _megText = '請先刷讀儲位代碼（6 碼）';
  _Meg _megKind = _Meg.info;
  String _megQty = '';
  bool _flash = false;

  /// 刷槍一秒可刷多筆：先排隊、依序送出，處理中也不丟碼
  final List<String> _queue = [];
  bool _processing = false;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _scanFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _tts.dispose();
    _scanController.dispose();
    _scanFocus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  bool get _editable => _su?.editable ?? false;

  int _rackTotal(PutawaySuDetail su, String rkId) => su.details
      .where((d) => d.rkId == rkId)
      .fold<int>(0, (s, d) => s + d.realQty);

  /// [silent]：刷讀告一段落後背景同步，不顯示 loading、刷讀中則略過
  Future<void> _load({bool silent = false}) async {
    if (silent && (_processing || _busy)) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final su = await widget.service.fetchSu(widget.suNo);
      if (!mounted) return;
      if (silent && (_processing || _queue.isNotEmpty)) return;
      setState(() {
        _su = su;
        _loading = false;
        if (_rkId.isNotEmpty) _rackQty = _rackTotal(su, _rkId);
      });
      _refocusScan();
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _refocusScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editable && _keepScanFocus) _scanFocus.requestFocus();
    });
  }

  void _hideKeyboard() {
    _keepScanFocus = false;
    _scanFocus.unfocus();
  }

  void _setMeg(
    String text, {
    required bool ok,
    bool warn = false,
    String qty = '',
  }) {
    setState(() {
      _megText = text;
      _megKind = !ok ? _Meg.error : (warn ? _Meg.warn : _Meg.ok);
      _megQty = qty;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _fail(String message, {String speech = '錯誤'}) {
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();
    _setMeg(message, ok: false);
    _tts.speak(speech);
  }

  Future<void> _showError(String title, String message) async {
    HapticFeedback.heavyImpact();
    _setMeg(message, ok: false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _onScanSubmit(String raw) {
    final code = raw.trim().toUpperCase();
    _scanController.clear();
    if (code.isEmpty) {
      if (_isIOS) {
        _hideKeyboard();
      } else {
        _refocusScan();
      }
      return;
    }
    if (!_editable) return;
    if (_busy) {
      _fail('處理中，請稍候再刷：$code');
      return;
    }
    setState(() => _queue.add(code));
    _refocusScan();
    _pump();
  }

  Future<void> _pump() async {
    if (_processing) return;
    _syncTimer?.cancel();
    setState(() => _processing = true);
    while (_queue.isNotEmpty && mounted) {
      final code = _queue.removeAt(0);
      await _handleCode(code);
    }
    if (!mounted) return;
    setState(() => _processing = false);
    _syncTimer = Timer(const Duration(seconds: 2), () => _load(silent: true));
  }

  Future<void> _handleCode(String code) async {
    if (code.length == 13 && (code.startsWith('CA') || code.startsWith('CB'))) {
      _fail('$code：上架單建立後無法再增減驗收單，請刷儲位或物流條碼');
      return;
    }
    if (code.length == 6) {
      try {
        final qty = await widget.service.checkRack(widget.suNo, code);
        if (!mounted) return;
        HapticFeedback.selectionClick();
        setState(() {
          _rkId = code;
          _rackQty = qty;
        });
        _setMeg('儲位 $code，請刷物流條碼', ok: true);
        _tts.speakRack(code);
      } catch (e) {
        if (!mounted) return;
        // 儲位錯了，後面排隊的書會放錯位置，一律丟棄請使用者重刷
        final dropped = _queue.length;
        setState(_queue.clear);
        _fail(
          '儲位 $code：$e${dropped > 0 ? '（後面 $dropped 筆未上架，請重刷）' : ''}',
          speech: '儲位錯誤',
        );
      }
      return;
    }
    if (_rkId.isEmpty) {
      _fail('$code 未上架：請先刷儲位代碼（6 碼）', speech: '請先刷儲位');
      return;
    }
    try {
      final r = await widget.service.scan(widget.suNo, _rkId, code);
      if (!mounted) return;
      _applyScan(r);
      if (r.over) {
        HapticFeedback.heavyImpact();
        _tts.speak('溢上架');
      } else {
        HapticFeedback.mediumImpact();
        _tts.speak('${r.realQty}');
      }
      _setMeg(
        r.prodNm.isNotEmpty ? r.prodNm : r.logcode,
        ok: true,
        warn: r.over,
        qty: '${r.realQty}/${r.mustQty}',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      _fail('$code：$msg', speech: msg.contains('不存在') ? '查無此書' : '錯誤');
    }
  }

  void _applyScan(PutawayScanResult r) {
    final su = _su;
    if (su == null) return;
    final sums = [
      for (final s in su.sums)
        s.logcode == r.logcode ? s.copyWithReal(r.realQty) : s,
    ];
    final details = [...su.details];
    final i = details.indexWhere(
      (d) => d.rkId == r.rkId && d.logcode == r.logcode,
    );
    if (i >= 0) {
      details[i] = details[i].copyWithReal(r.rackQty);
    } else {
      details.add(
        PutawayDetailLine(
          rkId: r.rkId,
          prodId: r.prodId,
          logcode: r.logcode,
          prodNm: r.prodNm,
          realQty: r.rackQty,
        ),
      );
    }
    final next = su.copyWith(
      main: su.main.copyWithTotals(
        ttlMustQty: r.ttlMustQty,
        ttlRealQty: r.ttlRealQty,
        ttlDifQty: r.ttlDifQty,
      ),
      sums: sums,
      details: details,
    );
    setState(() {
      _su = next;
      _rackQty = _rackTotal(next, _rkId);
    });
  }

  Future<void> _openCamera({required bool rack}) async {
    if (_isIOS) _hideKeyboard();
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => rack
            ? const BarcodeCameraScanScreen(
                title: '掃描儲位代碼',
                formats: kCodeBarcodeFormats,
              )
            : BarcodeCameraScanScreen(title: '掃描書籍條碼（儲位 $_rkId）'),
      ),
    );
    if (!mounted) return;
    if (code != null && code.trim().isNotEmpty) {
      _onScanSubmit(code);
    } else {
      _refocusScan();
    }
  }

  Future<void> _adjust(PutawayDetailLine d) async {
    if (!_editable) return;
    final ctrl = TextEditingController(text: '${d.realQty}');
    final qty = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('修改上架量　儲位 ${d.rkId}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.prodNm.isEmpty ? d.logcode : d.prodNm),
            Text('物流條碼 ${d.logcode}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '上架量（0 = 刪除此筆）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, d.realQty > 0 ? d.realQty - 1 : 0),
            child: const Text('－１'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (qty == null || qty == d.realQty || !mounted) {
      _refocusScan();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.adjust(widget.suNo, d.rkId, d.logcode, qty);
      if (!mounted) return;
      setState(() => _busy = false);
      _setMeg(
        '已修改 ${d.rkId} ${d.prodNm.isEmpty ? d.logcode : d.prodNm} → $qty',
        ok: true,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError('修改上架量', e.toString());
    }
    _refocusScan();
  }

  Future<void> _finish() async {
    final su = _su;
    if (su == null || _busy) return;
    final m = su.main;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完成上架'),
        content: Text(
          '上架單 ${m.suNo}\n'
          '總驗收量 ${m.ttlMustQty}／總上架量 ${m.ttlRealQty}／總差異量 ${m.ttlDifQty}\n\n'
          '完成後送 MIS「進貨上架審核」入庫，本單不可再修改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確定完成'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      _refocusScan();
      return;
    }
    await _doFinish(force: false);
  }

  Future<void> _doFinish({required bool force}) async {
    setState(() => _busy = true);
    try {
      final msg = await widget.service.finish(widget.suNo, force: force);
      if (!mounted) return;
      setState(() => _busy = false);
      HapticFeedback.mediumImpact();
      _setMeg(msg, ok: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
      );
      await _load();
    } on PutawayFinishException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      HapticFeedback.heavyImpact();
      final lines = <String>[
        ...e.blockers,
        ...e.warnings,
        ...e.clashes.map(
          (c) =>
              '【${c.clashFlg}】儲位 ${c.rkId}：${c.prodNm}（${c.logcode}）'
              ' 與 ${c.clashProdNm}（${c.clashLogcode}）',
        ),
      ];
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(e.blocked ? '無法完成上架' : '請確認'),
          content: SingleChildScrollView(child: Text(lines.join('\n\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(e.blocked ? '確定' : '取消'),
            ),
            if (!e.blocked && e.needConfirm)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍要完成'),
              ),
          ],
        ),
      );
      if (again == true && mounted) {
        await _doFinish(force: true);
        return;
      }
      _setMeg(e.message, ok: false);
      _refocusScan();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError('完成上架', e.toString());
      _refocusScan();
    }
  }

  Future<void> _revoke() async {
    if (_busy || !_editable) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作廢上架單'),
        content: Text('確定作廢上架單 ${widget.suNo}？\n已刷讀的上架紀錄會失效，驗收單將釋放回待上架。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('作廢'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final msg = await widget.service.revoke(widget.suNo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError('作廢上架單', e.toString());
    }
  }

  Widget? _buildBottomBar(bool keyboardOpen) {
    final su = _su;
    if (su == null) return null;
    if (!su.editable) {
      final m = su.main;
      return SafeArea(
        child: Container(
          color: m.statusFlg == 'D'
              ? Colors.grey.shade300
              : Colors.green.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '${m.statusLabel}'
            '${m.finUser.isNotEmpty ? '（完成 ${m.finUser}）' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    final hasDiff = su.main.ttlDifQty != 0 || su.sums.any((s) => s.difQty != 0);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          keyboardOpen ? 2 : 6,
          12,
          keyboardOpen ? 4 : 8,
        ),
        child: SizedBox(
          height: keyboardOpen ? 40 : 48,
          child: hasDiff
              ? Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.block),
                        label: const Text(
                          '尚有差異，不可完成',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                      ),
                      onPressed: () => _tabs.animateTo(_diffTab),
                      icon: const Icon(Icons.rule),
                      label: const Text('看差異'),
                    ),
                  ],
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  onPressed: (_busy || _loading) ? null : _finish,
                  icon: const Icon(Icons.task_alt),
                  label: const Text(
                    '完成上架',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
        ),
      ),
    );
  }

  String _sumTitle(PutawaySumLine s) =>
      '${s.prodNm.isEmpty ? s.logcode : s.prodNm}'
      '${s.fragileFlg == 'Y' ? '　易碎' : ''}';

  Widget _buildPending(PutawaySuDetail su) {
    final sums = su.sums.where((s) => s.remainQty > 0).toList()
      ..sort((a, b) => a.pitem - b.pitem);
    if (sums.isEmpty) {
      return Center(child: Text(su.sums.isEmpty ? '無應上架商品' : '全部已上架'));
    }
    return ListView.builder(
      itemCount: sums.length,
      itemBuilder: (_, i) {
        final s = sums[i];
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.radio_button_unchecked,
            color: Colors.orange.shade800,
          ),
          title: Text(
            _sumTitle(s),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('物流條碼 ${s.logcode}　${s.iqcNo}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${s.realQty}/${s.mustQty}',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text('尚缺 ${s.remainQty}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _groupHeader(String title, String trailing) {
    return Container(
      color: Colors.blueGrey.shade50,
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaced(PutawaySuDetail su) {
    if (su.details.isEmpty) return const Center(child: Text('尚未上架任何商品'));
    final byRack = _placedByRack;
    final groups = <String, List<PutawayDetailLine>>{};
    for (final d in su.details) {
      groups.putIfAbsent(byRack ? d.rkId : d.logcode, () => []).add(d);
    }
    final keys = groups.keys.toList()..sort();
    final mustOf = <String, int>{};
    for (final s in su.sums) {
      mustOf[s.logcode] = (mustOf[s.logcode] ?? 0) + s.mustQty;
    }

    final children = <Widget>[];
    for (final k in keys) {
      final lines = groups[k]!
        ..sort(
          (a, b) => byRack
              ? a.logcode.compareTo(b.logcode)
              : a.rkId.compareTo(b.rkId),
        );
      final total = lines.fold<int>(0, (s, d) => s + d.realQty);
      if (byRack) {
        children.add(_groupHeader('儲位 $k', '$total 本'));
      } else {
        final first = lines.first;
        final must = mustOf[k];
        children.add(
          _groupHeader(
            first.prodNm.isEmpty ? k : first.prodNm,
            must == null ? '$total 本' : '$total/$must',
          ),
        );
      }
      for (final d in lines) {
        final current = d.rkId == _rkId;
        children.add(
          ListTile(
            dense: true,
            selected: current,
            leading: byRack
                ? null
                : Text(
                    d.rkId,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: current ? Colors.blue.shade800 : Colors.black87,
                    ),
                  ),
            title: byRack
                ? Text(
                    d.prodNm.isEmpty ? d.logcode : d.prodNm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('物流條碼 ${d.logcode}'),
            subtitle: byRack ? Text('物流條碼 ${d.logcode}') : null,
            trailing: Text(
              '${d.realQty}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            onTap: _editable && !_busy ? () => _adjust(d) : null,
          ),
        );
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.qr_code, size: 18),
                label: Text('依條碼'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.shelves, size: 18),
                label: Text('依儲位'),
              ),
            ],
            selected: {byRack},
            onSelectionChanged: (v) => setState(() => _placedByRack = v.first),
          ),
        ),
        Expanded(child: ListView(children: children)),
      ],
    );
  }

  Widget _buildDiff(PutawaySuDetail su) {
    final sums = su.sums.where((s) => s.difQty != 0).toList()
      ..sort((a, b) => a.pitem - b.pitem);
    if (sums.isEmpty) {
      return Center(
        child: Text(
          '無差異',
          style: TextStyle(
            color: Colors.green.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: sums.length,
      itemBuilder: (_, i) {
        final s = sums[i];
        final over = s.difQty > 0;
        final color = over ? Colors.red.shade700 : Colors.orange.shade800;
        return ListTile(
          dense: true,
          leading: Icon(
            over ? Icons.error : Icons.remove_circle_outline,
            color: color,
          ),
          title: Text(
            _sumTitle(s),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '物流條碼 ${s.logcode}\n應上架 ${s.mustQty}／已上架 ${s.realQty}',
          ),
          isThreeLine: true,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              over ? '多 ${s.difQty}' : '少 ${-s.difQty}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final su = _su;
    final focused = _scanFocus.hasFocus;
    final m = su?.main;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final bottomBar = _buildBottomBar(keyboardOpen);

    return Scaffold(
      appBar: AppBar(
        title: Text('上架 ${widget.suNo}'),
        actions: [
          IconButton(
            tooltip: '重新載入',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          if (_editable)
            IconButton(
              tooltip: '作廢上架單',
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: _busy ? null : _revoke,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(su, m, focused)),
          // 不用 bottomNavigationBar：iOS 鍵盤會蓋住它，放在 body 才會被推到鍵盤上方
          if (bottomBar != null) bottomBar,
        ],
      ),
    );
  }

  Widget _cameraButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 44,
      width: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            Text(label, style: const TextStyle(fontSize: 11, height: 1.1)),
          ],
        ),
      ),
    );
  }

  /// 刷讀結果列：綠＝上架成功、橘＝溢上架、紅＝錯誤；每次刷讀閃一下
  Widget _buildMegBar() {
    final base = switch (_megKind) {
      _Meg.info => const Color(0xFF000080),
      _Meg.ok => Colors.green.shade700,
      _Meg.warn => Colors.orange.shade800,
      _Meg.error => Colors.red.shade700,
    };
    final color = _flash ? Color.lerp(base, Colors.white, 0.5)! : base;
    final icon = switch (_megKind) {
      _Meg.info => Icons.info_outline,
      _Meg.ok => Icons.check_circle,
      _Meg.warn => Icons.warning_amber_rounded,
      _Meg.error => Icons.cancel,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _megText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
              ),
            ),
          ),
          if (_megQty.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              _megQty,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 26,
              ),
            ),
          ],
          if (_queue.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '待處理 ${_queue.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(PutawaySuDetail? su, PutawaySuSummary? m, bool focused) {
    final diffCount = su?.sums.where((s) => s.difQty != 0).length ?? 0;
    return _loading && su == null
        ? const Center(child: CircularProgressIndicator())
        : _error != null && su == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('重試')),
                ],
              ),
            ),
          )
        : Column(
            children: [
              if (_editable)
                Material(
                  color: focused ? const Color(0xFFFFF59D) : Colors.white,
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _scanController,
                            focusNode: _scanFocus,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              hintText: _rkId.isEmpty ? '刷儲位代碼' : '刷物流條碼／換儲位',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.keyboard, size: 20),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              suffixIcon: (_busy || _processing)
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: '送出',
                                      icon: const Icon(Icons.send, size: 20),
                                      onPressed: () =>
                                          _onScanSubmit(_scanController.text),
                                    ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            keyboardType: TextInputType.visiblePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9]'),
                              ),
                            ],
                            textInputAction: TextInputAction.done,
                            onSubmitted: _onScanSubmit,
                            // 預設送出後會失焦，刷槍連續刷的下一筆會漏字
                            onEditingComplete: () {},
                            onTap: () => _keepScanFocus = true,
                            onTapOutside: _isIOS
                                ? (_) => _hideKeyboard()
                                : null,
                          ),
                        ),
                        if (_isIOS)
                          IconButton(
                            tooltip: '收起鍵盤',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.keyboard_hide, size: 26),
                            onPressed: _hideKeyboard,
                          ),
                        _cameraButton(
                          label: '儲位',
                          icon: Icons.shelves,
                          onPressed: _busy
                              ? null
                              : () => _openCamera(rack: true),
                        ),
                        const SizedBox(width: 4),
                        _cameraButton(
                          label: '書',
                          icon: Icons.menu_book,
                          onPressed: (_busy || _rkId.isEmpty)
                              ? null
                              : () => _openCamera(rack: false),
                        ),
                      ],
                    ),
                  ),
                ),
              _buildMegBar(),
              Container(
                width: double.infinity,
                color: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '上架儲位',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _rkId.isEmpty ? '—' : _rkId,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            color: Colors.blue.shade800,
                            letterSpacing: 1,
                          ),
                        ),
                        if (_rkId.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$_rackQty 本',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (m != null)
                      Text(
                        '總驗收 ${m.ttlMustQty}／總上架 ${m.ttlRealQty}／總差異 ${m.ttlDifQty}',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                labelPadding: EdgeInsets.zero,
                tabs: [
                  Tab(
                    height: 34,
                    text:
                        '待上架（${su?.sums.where((s) => s.remainQty > 0).length ?? 0}）',
                  ),
                  Tab(height: 34, text: '已上架（${su?.details.length ?? 0}）'),
                  Tab(
                    height: 34,
                    child: Text(
                      '差異（$diffCount）',
                      style: diffCount > 0
                          ? TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w800,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: su == null
                    ? const SizedBox.shrink()
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _buildPending(su),
                          _buildPlaced(su),
                          _buildDiff(su),
                        ],
                      ),
              ),
            ],
          );
  }
}
