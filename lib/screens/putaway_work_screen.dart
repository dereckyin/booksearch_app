import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/putaway.dart';
import '../services/putaway_service.dart';
import 'barcode_camera_scan_screen.dart';

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
  late final TabController _tabs = TabController(length: 2, vsync: this);

  PutawaySuDetail? _su;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String _rkId = '';
  int _rackQty = 0;
  String _megText = '請先刷讀儲位代碼（6 碼）';
  bool _megOk = true;

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
    _scanController.dispose();
    _scanFocus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  bool get _editable => _su?.editable ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final su = await widget.service.fetchSu(widget.suNo);
      if (!mounted) return;
      setState(() {
        _su = su;
        _loading = false;
        if (_rkId.isNotEmpty) {
          _rackQty = su.details
              .where((d) => d.rkId == _rkId)
              .fold<int>(0, (s, d) => s + d.realQty);
        }
      });
      _refocusScan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _refocusScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editable) _scanFocus.requestFocus();
    });
  }

  void _setMeg(String text, {required bool ok}) {
    setState(() {
      _megText = text;
      _megOk = ok;
    });
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定')),
        ],
      ),
    );
  }

  Future<void> _onScanSubmit(String raw) async {
    final code = raw.trim().toUpperCase();
    _scanController.clear();
    if (code.isEmpty || _busy || !_editable) {
      _refocusScan();
      return;
    }
    if (code.length == 13 && (code.startsWith('CA') || code.startsWith('CB'))) {
      await _showError('輸入：$code', '上架單建立後無法再增減驗收單；請直接刷儲位與物流條碼');
      _refocusScan();
      return;
    }
    setState(() => _busy = true);
    try {
      if (code.length == 6) {
        final qty = await widget.service.checkRack(widget.suNo, code);
        if (!mounted) return;
        HapticFeedback.selectionClick();
        setState(() {
          _rkId = code;
          _rackQty = qty;
          _busy = false;
        });
        _setMeg('上架儲位 $code，請刷物流條碼', ok: true);
      } else {
        if (_rkId.isEmpty) {
          setState(() => _busy = false);
          await _showError('輸入物流條碼：$code', '請先輸入 < 儲位代碼 >');
          _refocusScan();
          return;
        }
        final r = await widget.service.scan(widget.suNo, _rkId, code);
        if (!mounted) return;
        if (r.over) {
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.mediumImpact();
        }
        setState(() {
          _rackQty = r.rackQty;
          _busy = false;
        });
        _setMeg('${r.message}（${r.realQty}/${r.mustQty}）', ok: !r.over);
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError('輸入：$code', e.toString());
    }
    _refocusScan();
  }

  Future<void> _openCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BarcodeCameraScanScreen(
          title: _rkId.isEmpty ? '掃描儲位代碼' : '掃描物流條碼（儲位 $_rkId）',
        ),
      ),
    );
    if (!mounted) return;
    if (code != null && code.trim().isNotEmpty) {
      await _onScanSubmit(code);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, d.realQty > 0 ? d.realQty - 1 : 0),
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
      _setMeg('已修改 ${d.rkId} ${d.prodNm.isEmpty ? d.logcode : d.prodNm} → $qty', ok: true);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確定完成')),
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
          (c) => '【${c.clashFlg}】儲位 ${c.rkId}：${c.prodNm}（${c.logcode}）'
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
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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
        content: Text(
          '確定作廢上架單 ${widget.suNo}？\n已刷讀的上架紀錄會失效，驗收單將釋放回待上架。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
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

  Widget? _buildBottomBar() {
    final su = _su;
    if (su == null) return null;
    if (!su.editable) {
      final m = su.main;
      return SafeArea(
        child: Container(
          color: m.statusFlg == 'D' ? Colors.grey.shade300 : Colors.green.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            '${m.statusLabel}'
            '${m.finUser.isNotEmpty ? '（完成 ${m.finUser}）' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: su.main.ttlDifQty == 0
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
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

  Widget _buildSums(PutawaySuDetail su) {
    if (su.sums.isEmpty) return const Center(child: Text('無應上架商品'));
    final sums = [...su.sums]
      ..sort((a, b) {
        final ar = a.remainQty > 0 ? 0 : 1;
        final br = b.remainQty > 0 ? 0 : 1;
        if (ar != br) return ar - br;
        return a.pitem - b.pitem;
      });
    return ListView.builder(
      itemCount: sums.length,
      itemBuilder: (_, i) {
        final s = sums[i];
        final done = s.difQty == 0;
        final over = s.difQty > 0;
        final color = done
            ? Colors.green.shade700
            : over
                ? Colors.red.shade700
                : Colors.orange.shade800;
        return ListTile(
          dense: true,
          leading: Icon(
            done ? Icons.check_circle : (over ? Icons.error : Icons.radio_button_unchecked),
            color: color,
          ),
          title: Text(
            '${s.prodNm.isEmpty ? s.logcode : s.prodNm}'
            '${s.fragileFlg == 'Y' ? '　易碎' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('物流條碼 ${s.logcode}　${s.iqcNo}'),
          trailing: Text(
            '${s.realQty}/${s.mustQty}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
          ),
        );
      },
    );
  }

  Widget _buildDetails(PutawaySuDetail su) {
    if (su.details.isEmpty) return const Center(child: Text('尚未上架任何商品'));
    return ListView.builder(
      itemCount: su.details.length,
      itemBuilder: (_, i) {
        final d = su.details[i];
        final current = d.rkId == _rkId;
        return ListTile(
          dense: true,
          selected: current,
          leading: Text(
            d.rkId,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: current ? Colors.blue.shade800 : Colors.black87,
            ),
          ),
          title: Text(
            d.prodNm.isEmpty ? d.logcode : d.prodNm,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('物流條碼 ${d.logcode}'),
          trailing: Text(
            '${d.realQty}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          onTap: _editable && !_busy ? () => _adjust(d) : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final su = _su;
    final focused = _scanFocus.hasFocus;
    final m = su?.main;

    return Scaffold(
      bottomNavigationBar: _buildBottomBar(),
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
      body: _loading && su == null
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
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _scanController,
                                  focusNode: _scanFocus,
                                  enabled: !_busy,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: _rkId.isEmpty ? '刷儲位代碼' : '刷物流條碼／換儲位',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.keyboard),
                                    suffixIcon: _busy
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : IconButton(
                                            tooltip: '送出',
                                            icon: const Icon(Icons.send),
                                            onPressed: () => _onScanSubmit(_scanController.text),
                                          ),
                                  ),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: _onScanSubmit,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 52,
                                width: 56,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                                  onPressed: _busy ? null : _openCamera,
                                  child: const Icon(Icons.photo_camera, size: 28),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      color: _megOk ? const Color(0xFF000080) : const Color(0xFFC00C92),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        _megText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _megOk ? const Color(0xFFFFFF00) : const Color(0xFF00FFFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text('上架儲位', style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            _rkId.isEmpty ? '—' : _rkId,
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                              color: Colors.blue.shade800,
                              letterSpacing: 2,
                            ),
                          ),
                          if (_rkId.isNotEmpty)
                            Text('此儲位已上架 $_rackQty 本',
                                style: Theme.of(context).textTheme.bodySmall),
                          if (m != null)
                            Text(
                              '總驗收 ${m.ttlMustQty}／總上架 ${m.ttlRealQty}／總差異 ${m.ttlDifQty}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    TabBar(
                      controller: _tabs,
                      tabs: [
                        Tab(text: '應上架（${su?.sums.length ?? 0}）'),
                        Tab(text: '儲位明細（${su?.details.length ?? 0}）'),
                      ],
                    ),
                    Expanded(
                      child: su == null
                          ? const SizedBox.shrink()
                          : TabBarView(
                              controller: _tabs,
                              children: [_buildSums(su), _buildDetails(su)],
                            ),
                    ),
                  ],
                ),
    );
  }
}
