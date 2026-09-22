import 'package:flutter/material.dart';

import '../models/virtual_bin.dart';
import '../services/picklist_service.dart';
import '../services/virtual_bin_service.dart';
import 'virtual_bin_work_screen.dart';

/// 虛擬櫃位分貨 — 從可分貨批號清單選擇（不需手打 SD_NO）
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
  List<VirtualBinBatchSummary> _batches = [];
  bool _loading = true;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service.token = widget.pickListService.token;
      final list = await _service.fetchBatches();
      if (!mounted) return;
      setState(() {
        _batches = list;
        // 若先前選的批號仍在清單中則保留，否則預選第一筆
        if (_selectedSdNo == null ||
            !_batches.any((b) => b.sdNo == _selectedSdNo)) {
          _selectedSdNo = _batches.isNotEmpty ? _batches.first.sdNo : null;
        }
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

  Future<void> _openBatch(String sdNo) async {
    final trimmed = sdNo.trim();
    if (trimmed.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VirtualBinWorkScreen(
          service: _service,
          sdNo: trimmed,
        ),
      ),
    );
    if (mounted) await _load();
  }

  String _pickFlgLabel(String? flg) {
    switch ((flg ?? '').toUpperCase()) {
      case 'W':
        return '未分貨';
      case 'N':
        return '未開放';
      case 'U':
        return '未定義';
      case 'Y':
        return '已分貨';
      default:
        return flg ?? '';
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
                  const SizedBox(height: 4),
                  Text(
                    '從下方選單選擇「揀貨單號」，開始後用相機掃物流條碼',
                    style: Theme.of(context).textTheme.bodySmall,
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
                        labelText: '選擇揀貨單號（分貨批）',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.list_alt),
                      ),
                      items: _batches.map((b) {
                        final status = _pickFlgLabel(b.pickFlg);
                        final cnno = (b.cnno != null && b.cnno!.isNotEmpty)
                            ? ' · ${b.cnno}'
                            : '';
                        return DropdownMenuItem<String>(
                          value: b.sdNo,
                          child: Text(
                            '${b.sdNo}（格位 ${b.kitCnt}／應分 ${b.mustQty}$cnno'
                            '${status.isNotEmpty ? ' · $status' : ''}）',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedSdNo = v),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _selectedSdNo == null
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
                      '可分貨清單（也可直接點選）',
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
                return ListTile(
                  selected: selected,
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.grid_view,
                  ),
                  title: Text(b.sdNo),
                  subtitle: Text(
                    '格位 ${b.kitCnt}／應分 ${b.mustQty}'
                    '${b.cnno != null && b.cnno!.isNotEmpty ? '／${b.cnno}' : ''}'
                    '／${_pickFlgLabel(b.pickFlg)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
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
