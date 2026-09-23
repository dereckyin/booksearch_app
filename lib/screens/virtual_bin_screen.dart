import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/virtual_bin.dart';
import '../services/picklist_service.dart';
import '../services/virtual_bin_service.dart';
import 'barcode_camera_scan_screen.dart';
import 'virtual_bin_work_screen.dart';

/// 虛擬櫃位分貨 — 刷讀／點選批號進入作業
class VirtualBinScreen extends StatefulWidget {
  const VirtualBinScreen({
    super.key,
    required this.pickListService,
  });

  final PickListService pickListService;

  @override
  State<VirtualBinScreen> createState() => _VirtualBinScreenState();
}

class _VirtualBinScreenState extends State<VirtualBinScreen> {
  late final VirtualBinService _service;
  final _fcController = TextEditingController();
  final _fcFocus = FocusNode();
  List<VirtualBinBatchSummary> _batches = [];
  bool _loading = true;
  bool _opening = false;
  String? _error;
  String? _selectedSdNo;

  @override
  void initState() {
    super.initState();
    _service = VirtualBinService(
      token: widget.pickListService.token,
      onUnauthorized: widget.pickListService.onUnauthorized,
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant VirtualBinScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _service.token = widget.pickListService.token;
    _service.onUnauthorized = widget.pickListService.onUnauthorized;
  }

  @override
  void dispose() {
    _fcController.dispose();
    _fcFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service.token = widget.pickListService.token;
      final list = await _service.fetchBatches();
      list.sort((a, b) => b.sdNo.compareTo(a.sdNo));
      if (!mounted) return;
      setState(() {
        _batches = list;
        if (_selectedSdNo == null ||
            !_batches.any((b) => b.sdNo == _selectedSdNo)) {
          _selectedSdNo = _batches.isNotEmpty ? _batches.first.sdNo : null;
        }
        _loading = false;
      });
      _refocusFc();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _refocusFc() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fcFocus.requestFocus();
    });
  }

  /// 從掃槍／相機字串取出 FC 單號
  String? _extractFc(String raw) {
    final upper = raw.trim().toUpperCase();
    if (upper.isEmpty) return null;
    final match = RegExp(r'FC\d{8,}').firstMatch(upper);
    if (match != null) return match.group(0);
    if (upper.startsWith('FC')) return upper.split(RegExp(r'\s|/')).first;
    return null;
  }

  Future<void> _onFcSubmit(String raw) async {
    final sdNo = _extractFc(raw);
    _fcController.clear();
    if (sdNo == null) {
      _refocusFc();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請掃描揀貨單號（FC…）')),
      );
      return;
    }
    await _openBatch(sdNo);
  }

  Future<void> _openCameraFc() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeCameraScanScreen(title: '掃描揀貨單號 FC'),
      ),
    );
    if (code != null && code.trim().isNotEmpty) {
      await _onFcSubmit(code);
    } else {
      _refocusFc();
    }
  }

  Future<void> _openBatch(String sdNo) async {
    final trimmed = sdNo.trim().toUpperCase();
    if (trimmed.isEmpty || _opening) return;
    setState(() => _opening = true);
    try {
      // 清單外也可開：先確認有 DISPENSING
      if (!_batches.any((b) => b.sdNo == trimmed)) {
        await _service.fetchBatch(trimmed);
      }
      if (!mounted) return;
      setState(() => _selectedSdNo = trimmed);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VirtualBinWorkScreen(
            service: _service,
            sdNo: trimmed,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('無法開啟 $trimmed：${e.toString()}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      _refocusFc();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _statusLabel(VirtualBinBatchSummary b) {
    switch (b.displayStatus) {
      case 'completed':
        return '已分貨';
      case 'shortage':
        return '缺書';
      case 'in_progress':
        return '分貨中';
      default:
        return '未分貨';
    }
  }

  Color _statusColor(VirtualBinBatchSummary b) {
    switch (b.displayStatus) {
      case 'completed':
        return Colors.green.shade700;
      case 'shortage':
        return Colors.red.shade700;
      case 'in_progress':
        return Colors.orange.shade800;
      default:
        return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '虛擬櫃位分貨',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: (_loading || _opening) ? null : _openCameraFc,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text(
                        '相機掃揀貨單號',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fcController,
                    focusNode: _fcFocus,
                    enabled: !_opening,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    decoration: const InputDecoration(
                      labelText: '掃槍刷 FC 單號',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.document_scanner_outlined),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onFcSubmit,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9]'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('重試')),
                      ],
                    )
                  else if (_batches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('目前沒有可分貨批號')),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _selectedSdNo,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '選擇揀貨單號',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.list_alt),
                      ),
                      items: _batches.map((b) {
                        final status = _statusLabel(b);
                        final cnno = (b.cnno != null && b.cnno!.isNotEmpty)
                            ? ' · ${b.cnno}'
                            : '';
                        return DropdownMenuItem<String>(
                          value: b.sdNo,
                          child: Text(
                            '${b.sdNo}（格位 ${b.kitCnt}／應分 ${b.mustQty}$cnno'
                            ' · $status）',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _statusColor(b)),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedSdNo = v),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _selectedSdNo == null || _opening
                            ? null
                            : () => _openBatch(_selectedSdNo!),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          '開始分貨',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '可分貨清單',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!_loading && _error == null && _batches.isNotEmpty)
            SliverList.builder(
              itemCount: _batches.length,
              itemBuilder: (context, index) {
                final b = _batches[index];
                final selected = b.sdNo == _selectedSdNo;
                final color = _statusColor(b);
                return ListTile(
                  selected: selected,
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.grid_view,
                    color: color,
                  ),
                  title: Text(
                    b.sdNo,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '格位 ${b.kitCnt}／應分 ${b.mustQty}'
                    '${b.cnno != null && b.cnno!.isNotEmpty ? '／${b.cnno}' : ''}'
                    '／${_statusLabel(b)}',
                    style: TextStyle(color: color),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _opening
                      ? null
                      : () {
                          setState(() => _selectedSdNo = b.sdNo);
                          _openBatch(b.sdNo);
                        },
                );
              },
            ),
        ],
      ),
    );
  }
}
