import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_user.dart';
import '../services/picklist_service.dart';
import 'capture_screen.dart';
import 'pick_list_screen.dart';
import 'upload_gallery_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.token,
    required this.pickListService,
    required this.onLogout,
    this.user,
  });

  final String token;
  final AuthUser? user;
  final PickListService pickListService;
  final Future<void> Function() onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const String _buildDateRaw = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: '',
  );
  static const String _buildSeqRaw = String.fromEnvironment(
    'BUILD_SEQ',
    defaultValue: '01',
  );

  static String _normalizedBuildDate() {
    final digits = _buildDateRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 8) return digits;
    return 'dev';
  }

  static String _normalizedBuildSeq() {
    final digits = _buildSeqRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '01';
    final value = int.tryParse(digits);
    if (value == null || value <= 0) return '01';
    return value.toString().padLeft(2, '0');
  }

  static String _buildDateVersion() {
    return '${_normalizedBuildDate()}_${_normalizedBuildSeq()}';
  }

  final String _appVersion = _buildDateVersion();
  int _index = 0;
  int _pickListCount = 0;
  bool _captureUiVisible = false;
  static const _pickListTabIndex = 0;
  static const _captureTabIndex = 1;
  static const _captureOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const _defaultOrientations = DeviceOrientation.values;

  @override
  void initState() {
    super.initState();
    _refreshPickListCount();
    _setOrientationForIndex(_index);
  }

  Future<void> _setOrientationForIndex(int index) async {
    if (index == _captureTabIndex) {
      await SystemChrome.setPreferredOrientations(_captureOrientations);
    } else {
      await SystemChrome.setPreferredOrientations(_defaultOrientations);
    }
  }

  Future<void> _refreshPickListCount() async {
    try {
      final mains = await widget.pickListService.fetchPickListMain(
        priorOpenDays: PickListService.kDefaultPriorOpenDays,
      );
      if (!mounted) return;
      final unfinished = mains.where((m) => m.isUnfinishedForBadge).length;
      setState(() => _pickListCount = unfinished);
    } catch (_) {
      // Ignore; keep last known count.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('揀貨單'),
            const SizedBox(width: 6),
            Text(
              'v$_appVersion',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (widget.user != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4, top: 14, bottom: 14),
              child: Center(
                child: Text(
                  widget.user!.displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: () async {
              await widget.onLogout();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          PickListScreen(
            service: widget.pickListService,
            employeeId: widget.user?.phone,
            onCountChanged: (count) => setState(() => _pickListCount = count),
          ),
          CaptureScreen(
            showUi: _captureUiVisible,
            onToggleUi: () => setState(() {
              _captureUiVisible = !_captureUiVisible;
            }),
            isActive: _index == _captureTabIndex,
          ),
          UploadGalleryScreen(),
        ],
      ),
      bottomNavigationBar: _index == _captureTabIndex && !_captureUiVisible
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) async {
                setState(() {
                  _index = i;
                  if (i != _captureTabIndex) {
                    _captureUiVisible = true;
                  }
                });
                await _setOrientationForIndex(i);
                if (i == _pickListTabIndex) {
                  await _refreshPickListCount();
                }
              },
              destinations: [
                NavigationDestination(
                  icon: _buildPickListBadgeIcon(context),
                  selectedIcon: _buildPickListBadgeIcon(context),
                  label: '揀貨單',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.camera_alt_outlined),
                  selectedIcon: Icon(Icons.camera_alt),
                  label: '拍照',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.cloud_upload_outlined),
                  selectedIcon: Icon(Icons.cloud_upload),
                  label: '上傳圖檔',
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(_defaultOrientations);
    super.dispose();
  }

  Widget _buildPickListBadgeIcon(BuildContext context) {
    final count = _pickListCount;
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.inventory_2_outlined),
        if (count > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onError,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
