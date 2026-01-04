import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshPickListCount();
  }

  Future<void> _refreshPickListCount() async {
    try {
      final items = await _pickListService.fetchPickList();
      if (!mounted) return;
      setState(() => _pickListCount = items.length);
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
          const CaptureScreen(),
          PickListScreen(
            service: _pickListService,
            onCountChanged: (count) => setState(() => _pickListCount = count),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) async {
          setState(() => _index = i);
          if (i == 1) {
            await _refreshPickListCount();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: '拍照',
          ),
          NavigationDestination(
            icon: _buildPickListBadgeIcon(context),
            selectedIcon: _buildPickListBadgeIcon(context),
            label: '檢貨單',
          ),
        ],
      ),
    );
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


