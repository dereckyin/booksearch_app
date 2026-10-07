import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/putaway.dart';
import '../services/picklist_service.dart';
import '../services/putaway_service.dart';
import 'barcode_camera_scan_screen.dart';
import 'putaway_work_screen.dart';

/// 新品上架 — 未完成上架單／勾選待上架驗收單建單（對齊 C121100M）
class PutawayScreen extends StatefulWidget {
  const PutawayScreen({
    super.key,
    required this.pickListService,
  });

  final PickListService pickListService;

  @override
  State<PutawayScreen> createState() => _PutawayScreenState();
}

class _PutawayScreenState extends State<PutawayScreen> {
  late final PutawayService _service;
  final _scanController = TextEditingController();
  final _scanFocus = FocusNode();

  List<PutawaySuSummary> _openSus = [];
  List<PutawaySuSummary> _doneSus = [];
  List<PutawayPendingIqc> _pending = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = PutawayService(
      token: widget.pickListService.token,
      onUnauthorized: widget.pickListService.onUnauthorized,
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant PutawayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _service.token = widget.pickListService.token;
    _service.onUnauthorized = widget.pickListService.onUnauthorized;
  }

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service.token = widget.pickListService.token;
      final results = await Future.wait([
        _service.fetchSuList(status: 'N'),
        _service.fetchSuList(status: 'Y', days: 1),
        _service.fetchPendingIqc(),
      ]);
      if (!mounted) return;
      setState(() {
        _openSus = results[0] as List<PutawaySuSummary>;
        _doneSus = results[1] as List<PutawaySuSummary>;
        _pending = results[2] as List<PutawayPendingIqc>;
        _selected.removeWhere((q) => !_pending.any((p) => p.iqcNo == q));
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

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  /// 掃描 CA 驗收單號 → 勾選／取消；掃描 CB 上架單號 → 直接開啟
  Future<void> _onScanSubmit(String raw) async {
    final code = raw.trim().toUpperCase();
    _scanController.clear();
    if (code.isEmpty) return;
    if (code.startsWith('CB') && code.length == 13) {
      await _openSu(code);
      return;
    }
    if (!code.startsWith('CA') || code.length != 13) {
      HapticFeedback.heavyImpact();
      _snack('請掃描新品進貨驗收單號（CA…，13 碼）或上架單號（CB…）', error: true);
      return;
    }
    if (!_pending.any((p) => p.iqcNo == code)) {
      HapticFeedback.heavyImpact();
      _snack('$code 不在待上架清單（可能已被點選或尚未驗收完成）', error: true);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(code)) _selected.add(code);
    });
  }

  Future<void> _openCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeCameraScanScreen(title: '掃描驗收單號 CA／上架單號 CB'),
      ),
    );
    if (code != null && code.trim().isNotEmpty) {
      await _onScanSubmit(code);
    }
  }

  Future<void> _createSu() async {
    if (_selected.isEmpty || _busy) return;
    final iqcs = _selected.toList()..sort();
    final ttl = _pending
        .where((p) => _selected.contains(p.iqcNo))
        .fold<int>(0, (s, p) => s + p.ttlIqcQty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('建立上架單'),
        content: Text(
          '驗收單 ${iqcs.length} 張（共 $ttl 本）：\n${iqcs.join('\n')}\n\n'
          '建立後這些驗收單會被此上架單點選，MIS 其他人無法重複點選。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('建立')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final su = await _service.createSu(iqcs);
      if (!mounted) return;
      _selected.clear();
      setState(() => _busy = false);
      _snack('已建立上架單 ${su.main.suNo}');
      await _openSu(su.main.suNo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString(), error: true);
      await _load();
    }
  }

  Future<void> _openSu(String suNo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PutawayWorkScreen(service: _service, suNo: suNo),
      ),
    );
    if (mounted) await _load();
  }

  Widget _sectionTitle(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _suTile(PutawaySuSummary s) {
    final open = s.isOpen;
    final color = open ? Colors.orange.shade800 : Colors.green.shade700;
    return ListTile(
      leading: Icon(open ? Icons.move_to_inbox : Icons.task_alt, color: color),
      title: Text(s.suNo, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '應上 ${s.ttlMustQty}／實上 ${s.ttlRealQty}／差異 ${s.ttlDifQty}　${s.statusLabel}\n'
        '${s.iqcNoList}${s.crtUser.isNotEmpty ? '　建立 ${s.crtUser}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy ? null : () => _openSu(s.suNo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _createSu,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_task),
                    label: Text(
                      '建立上架單（${_selected.length} 張驗收單）',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('新品上架', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: (_loading || _busy) ? null : _openCamera,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text(
                        '相機掃驗收單號',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _scanController,
                    focusNode: _scanFocus,
                    enabled: !_busy,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: '掃槍刷 CA 驗收單號（勾選）或 CB 上架單號（開啟）',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.document_scanner_outlined),
                    ),
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onScanSubmit,
                    onEditingComplete: () {},
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('重試')),
                  ],
                ),
              )
            else ...[
              _sectionTitle('上架中（${_openSus.length}）'),
              if (_openSus.isEmpty)
                const ListTile(dense: true, title: Text('目前沒有未完成的上架單'))
              else
                ..._openSus.map(_suTile),
              _sectionTitle(
                '待上架驗收單（${_pending.length}）',
                trailing: _pending.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(() {
                          if (_selected.length == _pending.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(_pending.take(25).map((p) => p.iqcNo));
                          }
                        }),
                        child: Text(_selected.length == _pending.length ? '全不選' : '全選'),
                      ),
              ),
              if (_pending.isEmpty)
                const ListTile(dense: true, title: Text('目前沒有待上架的新品驗收單'))
              else
                ..._pending.map(
                  (p) => CheckboxListTile(
                    value: _selected.contains(p.iqcNo),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                if (_selected.length >= 25) {
                                  _snack('一張上架單最多 25 張驗收單', error: true);
                                  return;
                                }
                                _selected.add(p.iqcNo);
                              } else {
                                _selected.remove(p.iqcNo);
                              }
                            }),
                    title: Text(p.iqcNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${p.supNm.isNotEmpty ? '${p.supNm}　' : ''}'
                      '${p.lineCnt} 品項／${p.ttlIqcQty} 本',
                    ),
                  ),
                ),
              if (_doneSus.isNotEmpty) ...[
                _sectionTitle('今日已完成（${_doneSus.length}）'),
                ..._doneSus.map(_suTile),
              ],
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
