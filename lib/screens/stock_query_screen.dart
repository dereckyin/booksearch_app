import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/stock_query.dart';
import '../services/picklist_service.dart';
import '../services/stock_query_service.dart';
import 'barcode_camera_scan_screen.dart';

/// 庫存查詢 — 對齊 MIS H111100R（通道別／儲位代碼／物流條碼）
class StockQueryScreen extends StatefulWidget {
  const StockQueryScreen({
    super.key,
    required this.pickListService,
  });

  final PickListService pickListService;

  @override
  State<StockQueryScreen> createState() => _StockQueryScreenState();
}

class _StockQueryScreenState extends State<StockQueryScreen> {
  late final StockQueryService _service;

  final _rkRowFrom = TextEditingController();
  final _rkRowTo = TextEditingController();
  final _rkIdFrom = TextEditingController();
  final _rkIdTo = TextEditingController();
  final _logcode = TextEditingController();

  List<StockLocationItem> _items = [];
  bool _truncated = false;
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = StockQueryService(
      token: widget.pickListService.token,
      onUnauthorized: widget.pickListService.onUnauthorized,
    );
  }

  @override
  void didUpdateWidget(covariant StockQueryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _service.token = widget.pickListService.token;
    _service.onUnauthorized = widget.pickListService.onUnauthorized;
  }

  @override
  void dispose() {
    _rkRowFrom.dispose();
    _rkRowTo.dispose();
    _rkIdFrom.dispose();
    _rkIdTo.dispose();
    _logcode.dispose();
    super.dispose();
  }

  bool get _hasAnyCriteria {
    return _rkRowFrom.text.trim().isNotEmpty ||
        _rkRowTo.text.trim().isNotEmpty ||
        _rkIdFrom.text.trim().isNotEmpty ||
        _rkIdTo.text.trim().isNotEmpty ||
        _logcode.text.trim().isNotEmpty;
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

  Future<void> _openScan({
    required String title,
    required List<BarcodeFormat> formats,
    required TextEditingController target,
    TextEditingController? alsoFill,
  }) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BarcodeCameraScanScreen(
          title: title,
          formats: formats,
        ),
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    final v = code.trim().toUpperCase();
    setState(() {
      target.text = v;
      alsoFill?.text = v;
    });
  }

  Future<void> _search() async {
    if (!_hasAnyCriteria) {
      _snack('請至少輸入通道別、儲位代碼或物流條碼其中一項', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      _service.token = widget.pickListService.token;
      final result = await _service.queryLocations(
        rkRowFrom: _rkRowFrom.text,
        rkRowTo: _rkRowTo.text,
        rkIdFrom: _rkIdFrom.text,
        rkIdTo: _rkIdTo.text,
        logcode: _logcode.text,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _truncated = result.truncated;
        _loading = false;
      });
      if (result.truncated) {
        _snack('結果超過 500 筆，請縮小查詢範圍');
      } else if (result.items.isEmpty) {
        _snack('查無資料');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _items = [];
        _truncated = false;
        _loading = false;
      });
      _snack(e.toString(), error: true);
    }
  }

  void _reset() {
    setState(() {
      _rkRowFrom.clear();
      _rkRowTo.clear();
      _rkIdFrom.clear();
      _rkIdTo.clear();
      _logcode.clear();
      _items = [];
      _truncated = false;
      _searched = false;
      _error = null;
    });
  }

  Widget _rangeRow({
    required String label,
    required String hint,
    required TextEditingController from,
    required TextEditingController to,
    required int maxLen,
    VoidCallback? onScanFrom,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: from,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: onScanFrom == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: '掃描',
                          onPressed: _loading ? null : onScanFrom,
                        ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(maxLen),
                  _UpperCaseTextFormatter(),
                ],
                textInputAction: TextInputAction.next,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('～', style: TextStyle(fontSize: 18)),
            ),
            Expanded(
              child: TextField(
                controller: to,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(maxLen),
                  _UpperCaseTextFormatter(),
                ],
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultTile(StockLocationItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(
          item.prodNm.isEmpty ? '（無商品名稱）' : item.prodNm,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '儲位 ${item.rkId}　條碼 ${item.logcode}',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: Text(
          '${item.qty}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('庫存查詢', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '對齊 MIS 商品儲位庫存明細（物流倉）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _rangeRow(
            label: '通道別',
            hint: 'A01',
            from: _rkRowFrom,
            to: _rkRowTo,
            maxLen: 3,
          ),
          const SizedBox(height: 12),
          _rangeRow(
            label: '儲位代碼',
            hint: 'A01A11',
            from: _rkIdFrom,
            to: _rkIdTo,
            maxLen: 6,
            onScanFrom: () => _openScan(
              title: '掃描儲位代碼',
              formats: kCodeBarcodeFormats,
              target: _rkIdFrom,
              alsoFill: _rkIdTo,
            ),
          ),
          const SizedBox(height: 12),
          Text('物流條碼', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          TextField(
            controller: _logcode,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '掃槍或相機掃描',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: '掃描物流條碼',
                onPressed: _loading
                    ? null
                    : () => _openScan(
                          title: '掃描物流條碼',
                          formats: kBookBarcodeFormats,
                          target: _logcode,
                        ),
              ),
            ),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(40),
            ],
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _search,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: const Text(
                      '查詢',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _loading ? null : _reset,
                  child: const Text('重設'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          else if (_searched) ...[
            Text(
              _truncated
                  ? '結果 ${_items.length} 筆（已截斷，請縮小範圍）'
                  : '結果 ${_items.length} 筆',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const ListTile(
                dense: true,
                title: Text('查無資料'),
              )
            else
              ..._items.map(_resultTile),
          ],
        ],
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
