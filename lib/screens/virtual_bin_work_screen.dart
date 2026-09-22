import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/virtual_bin.dart';
import '../services/kit_tts_service.dart';
import '../services/virtual_bin_service.dart';
import 'barcode_camera_scan_screen.dart';

/// 分貨作業（對齊 E123100M：掃物流條碼 → 大字格位 → 1～50 色板）
class VirtualBinWorkScreen extends StatefulWidget {
  const VirtualBinWorkScreen({
    super.key,
    required this.service,
    required this.sdNo,
  });

  final VirtualBinService service;
  final String sdNo;

  @override
  State<VirtualBinWorkScreen> createState() => _VirtualBinWorkScreenState();
}

class _VirtualBinWorkScreenState extends State<VirtualBinWorkScreen> {
  final _scanController = TextEditingController();
  final _scanFocus = FocusNode();
  final _kitTts = KitTtsService();

  VirtualBinBatchDetail? _batch;
  bool _loading = true;
  bool _scanning = false;
  String? _error;

  /// 大字格位（對齊 dw_kit_no）；失敗顯示 ?
  String _displayKit = '';
  /// 訊息列（對齊 sle_keyin_meg）：成功=商品名／失敗=錯誤
  String _megText = '請掃描物流條碼';
  bool _megOk = true;

  @override
  void initState() {
    super.initState();
    _scanFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _loadBatch();
  }

  @override
  void dispose() {
    _kitTts.dispose();
    _scanController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _loadBatch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.service.fetchBatch(widget.sdNo);
      if (!mounted) return;
      setState(() {
        _batch = detail;
        _loading = false;
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
      if (mounted) _scanFocus.requestFocus();
    });
  }

  Future<void> _onScanSubmit(String raw) async {
    final barcode = raw.trim().toUpperCase();
    _scanController.clear();
    if (barcode.isEmpty || _scanning) {
      _refocusScan();
      return;
    }
    setState(() => _scanning = true);
    try {
      final result = await widget.service.scan(widget.sdNo, barcode);
      if (!mounted) return;

      HapticFeedback.mediumImpact();
      final kitLabel = result.displayKit.isNotEmpty
          ? result.displayKit
          : result.kitNo;
      setState(() {
        _displayKit = kitLabel;
        _megText = result.message.isNotEmpty
            ? result.message
            : (result.prodNm.isNotEmpty ? result.prodNm : '掃碼成功');
        _megOk = true;
        _scanning = false;
        if (result.kitBoard.isNotEmpty && _batch != null) {
          _batch = VirtualBinBatchDetail(
            sdNo: _batch!.sdNo,
            kitCnt: _batch!.kitCnt,
            mustQty: _batch!.mustQty,
            gotQty: _batch!.gotQty,
            remainQty: _batch!.remainQty,
            difQty: _batch!.difQty,
            batchCompleted: result.batchCompleted,
            bins: _batch!.bins,
            kitBoard: result.kitBoard,
          );
        }
      });

      // 語音播報格位：第 N 櫃（齊櫃時改唸「已完成」）
      if (result.binCompleted) {
        await _kitTts.speakKitCompleted(kitLabel);
      } else {
        await _kitTts.speakKit(kitLabel);
      }

      if (result.binCompleted || result.batchCompleted) {
        HapticFeedback.heavyImpact();
        await _showCompletionDialog(result);
      }

      await _loadBatch();
      if (!mounted) return;
      _refocusScan();
    } on VirtualBinScanException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _displayKit = e.displayKit.isNotEmpty ? e.displayKit : '?';
        _megText = e.message;
        _megOk = false;
        _scanning = false;
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('輸入物流條碼：${e.barcode}'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      _refocusScan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _displayKit = '?';
        _megText = e.toString();
        _megOk = false;
        _scanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      _refocusScan();
    }
  }

  Future<void> _showCompletionDialog(VirtualBinScanResult result) async {
    final title = result.batchCompleted ? '本批分貨完成' : '格位已完成';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.green.shade50,
        title: Text(title, style: TextStyle(color: Colors.green.shade900)),
        content: Text(result.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('繼續'),
          ),
        ],
      ),
    );
  }

  Future<void> _openBinDetail(String kitNo) async {
    try {
      final detail = await widget.service.fetchBin(widget.sdNo, kitNo);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (_, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          '格位 ${detail.displayKit.isNotEmpty ? detail.displayKit : detail.kitNo}',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        Text('${detail.gotQty}/${detail.mustQty}'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: detail.lines.length,
                      itemBuilder: (_, i) {
                        final line = detail.lines[i];
                        final done = !line.mustScan || line.remain <= 0;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            done
                                ? Icons.check_circle
                                : Icons.help_outline,
                            color: done ? Colors.green : Colors.orange,
                          ),
                          title: Text(
                            line.prodNm.isEmpty ? line.barNo : line.prodNm,
                          ),
                          subtitle: Text(
                            '物流條碼 ${line.barNo}　'
                            '${line.scannedQty}/${line.spQty}'
                            '${line.mustScan ? '　須刷' : '　免刷'}',
                          ),
                          trailing: done
                              ? null
                              : Text(
                                  '缺 ${line.remain}',
                                  style: const TextStyle(color: Colors.orange),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      _refocusScan();
    }
  }

  Future<void> _openCameraScan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeCameraScanScreen(title: '掃描物流條碼'),
      ),
    );
    if (!mounted) return;
    if (code != null && code.trim().isNotEmpty) {
      await _onScanSubmit(code);
    } else {
      _refocusScan();
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除掃描進度'),
        content: Text('確定清除批號 ${widget.sdNo} 的模擬掃描進度？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.resetProgress(widget.sdNo);
      if (!mounted) return;
      setState(() {
        _displayKit = '';
        _megText = '請掃描物流條碼';
        _megOk = true;
      });
      await _loadBatch();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除模擬進度')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Color _slotColor(String flg) {
    switch (flg) {
      case 'Y':
        return const Color(0xFFFFB74D); // 待完成（橘）
      case 'G':
        return const Color(0xFF81C784); // 已完成（綠）
      default:
        return const Color(0xFFBDBDBD); // 未開放（灰）
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = _batch;
    final focused = _scanFocus.hasFocus;

    return Scaffold(
      appBar: AppBar(
        title: Text('分貨 ${widget.sdNo}'),
        actions: [
          IconButton(
            tooltip: '重新載入',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadBatch,
          ),
          IconButton(
            tooltip: '清除進度',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== 掃碼輸入（對齊 sle_keyin_data，硬體掃槍）=====
          Material(
            color: focused ? const Color(0xFFFFF59D) : Colors.white,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '掃描物流條碼',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.blue.shade900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: (_scanning || _loading) ? null : _openCameraScan,
                      icon: const Icon(Icons.photo_camera, size: 26),
                      label: const Text(
                        '開啟相機掃碼',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _scanController,
                    focusNode: _scanFocus,
                    autofocus: false,
                    enabled: !_scanning && !_loading,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                    decoration: InputDecoration(
                      hintText: '或手動輸入條碼後按 Enter',
                      filled: true,
                      fillColor: focused
                          ? const Color(0xFFFFFDE7)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: focused
                              ? Colors.amber.shade800
                              : Colors.grey,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.blueGrey.shade300,
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.amber.shade800,
                          width: 3,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.keyboard, size: 26),
                      suffixIcon: _scanning
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: '送出',
                              icon: const Icon(Icons.send),
                              onPressed: () =>
                                  _onScanSubmit(_scanController.text),
                            ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onScanSubmit,
                  ),
                ],
              ),
            ),
          ),
          // ===== 訊息列（sle_keyin_meg）=====
          Container(
            width: double.infinity,
            color: _megOk
                ? const Color(0xFF000080)
                : const Color(0xFFC00C92),
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
          // ===== 大字格位（dw_kit_no）=====
          Container(
            width: double.infinity,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  '請放入格位',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  _displayKit.isEmpty ? '—' : _displayKit,
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: _displayKit == '?'
                        ? Colors.red
                        : Colors.blue.shade800,
                  ),
                ),
                if (batch != null)
                  Text(
                    '應分 ${batch.mustQty}／實分 ${batch.gotQty}／差異 ${batch.mustQty - batch.gotQty}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          // ===== 圖例 + 1～50 格位板 =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                _legend(const Color(0xFFFFB74D), '待完成'),
                const SizedBox(width: 10),
                _legend(const Color(0xFF81C784), '已完成'),
                const SizedBox(width: 10),
                _legend(const Color(0xFFBDBDBD), '未開放'),
              ],
            ),
          ),
          if (_loading && batch == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null && batch == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadBatch,
                        child: const Text('重試'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 168,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 10,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: 50,
                  itemBuilder: (context, index) {
                    final slot = index + 1;
                    VirtualBinKitSlot? info;
                    if (batch != null && batch.kitBoard.length >= slot) {
                      info = batch.kitBoard[index];
                    }
                    final flg = info?.runningFlg ?? 'N';
                    final label = '${info?.displayKit ?? slot}';
                    return InkWell(
                      onTap: flg == 'N'
                          ? null
                          : () => _openBinDetail(info?.kitNo ?? '$slot'),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _slotColor(flg),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: batch == null || batch.bins.isEmpty
                  ? const Center(child: Text('此批無格位資料'))
                  : ListView.builder(
                      itemCount: batch.bins.length,
                      itemBuilder: (context, index) {
                        final bin = batch.bins[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: _slotColor(bin.runningFlg),
                            child: Text(
                              bin.displayKit.isNotEmpty
                                  ? bin.displayKit
                                  : bin.kitNo,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          title: Text('格位 ${bin.displayKit}'),
                          subtitle: Text(
                            '${bin.gotQty}/${bin.mustQty}'
                            '${bin.ordNo.isNotEmpty ? ' · 訂單 ${bin.ordNo}' : ''}',
                          ),
                          trailing: bin.binCompleted
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : Text(
                                  '${bin.remainQty}',
                                  style: const TextStyle(color: Colors.orange),
                                ),
                          onTap: () => _openBinDetail(bin.kitNo),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
