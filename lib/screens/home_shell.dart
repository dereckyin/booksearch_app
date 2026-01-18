import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/picklist_service.dart';
import 'capture_screen.dart';
import 'pick_list_screen.dart';

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
  static const _pickListTabIndex = 0;
  static const _captureTabIndex = 1;
  static const _captureOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const _defaultOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  void initState() {
    super.initState();
    _refreshPickListCount();
    _setOrientationForIndex(_index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptEmployeeId());
  }

  Future<void> _setOrientationForIndex(int index) async {
    await SystemChrome.setPreferredOrientations(
      index == _captureTabIndex ? _captureOrientations : _defaultOrientations,
    );
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
          const CaptureScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) async {
          setState(() => _index = i);
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
    final controller = TextEditingController(text: _employeeId ?? '');
    String? input = _employeeId;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('請輸入工號'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '例如：A12345',
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final trimmed = controller.text.trim();
                    if (trimmed.isEmpty) return;
                    input = trimmed;
                    Navigator.of(context).pop();
                  },
                  child: const Text('確認'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;
    if (input == null || input!.isEmpty) return;
    setState(() {
      _employeeId = input;
    });
    await _refreshPickListCount();
  }
}


