import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/picklist_service.dart';
import 'capture_screen.dart';
import 'pick_list_screen.dart';
import 'upload_gallery_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _pickListService = PickListService();
  int _pickListCount = 0;
  String? _employeeId;
  bool _captureUiVisible = false;
  bool _pickingEmployee = false;
  static const _pickListTabIndex = 0;
  static const _captureTabIndex = 1;
  static const _uploadTabIndex = 2;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptEmployeeId());
  }

  Future<void> _setOrientationForIndex(int index) async {
    if (index == _captureTabIndex) {
      await SystemChrome.setPreferredOrientations(_captureOrientations);
    } else {
      await SystemChrome.setPreferredOrientations(_defaultOrientations);
    }
  }

  Future<void> _refreshPickListCount() async {
    if (_employeeId == null || _employeeId!.isEmpty) return;
    try {
      final mains =
          await _pickListService.fetchPickListMain(employeeId: _employeeId!);
      if (!mounted) return;
      setState(() => _pickListCount = mains.length);
    } catch (_) {
      // Ignore; keep last known count.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          PickListScreen(
            service: _pickListService,
            employeeId: _employeeId,
            onRequestEmployeeId: _promptEmployeeId,
            onCountChanged: (count) => setState(() => _pickListCount = count),
          ),
          CaptureScreen(
            showUi: _captureUiVisible,
            onToggleUi: () => setState(() {
              _captureUiVisible = !_captureUiVisible;
            }),
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
                    _captureUiVisible = true; // ensure nav/AppBar visible on other tabs
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
                  label: '撿貨單',
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

  Future<void> _promptEmployeeId() async {
    if (_pickingEmployee) return;
    setState(() => _pickingEmployee = true);
    try {
      final pickers = await _pickListService.fetchPickersToday();
      if (!mounted) return;
      if (pickers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('今日沒有可用的撿貨電話號碼')),
        );
        return;
      }
      String? selected = _employeeId;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('選擇您的電話號碼'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: pickers.length,
                    itemBuilder: (context, index) {
                      final picker = pickers[index];
                      return RadioListTile<String>(
                        value: picker.employeeNo,
                        groupValue: selected,
                        onChanged: (val) => setState(() => selected = val),
                        title: Text(picker.display),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: selected == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                          },
                    child: const Text('使用此電話號碼'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (!mounted) return;
      if (selected == null || selected?.isEmpty == true) return;
      setState(() {
        _employeeId = selected;
      });
      await _refreshPickListCount();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法取得電話號碼清單: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _pickingEmployee = false);
      }
    }
  }
}


