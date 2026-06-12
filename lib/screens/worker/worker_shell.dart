import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/theme.dart';

class WorkerShell extends StatelessWidget {
  final Widget child;
  const WorkerShell({super.key, required this.child});

  static const _tabs = [
    (path: '/worker/dashboard', icon: Icons.dashboard_outlined,    activeIcon: Icons.dashboard,    label: 'Dashboard'),
    (path: '/worker/earnings',  icon: Icons.payments_outlined,     activeIcon: Icons.payments,     label: 'Earnings'),
    (path: '/worker/history',   icon: Icons.history_outlined,      activeIcon: Icons.history,      label: 'History'),
    (path: '/worker/profile',   icon: Icons.person_outline,        activeIcon: Icons.person,       label: 'Profile'),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    return _tabs.indexWhere((t) => t.path == loc).clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Colors.white,
          boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4))]),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final active = i == idx;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => context.go(tab.path),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(active ? tab.activeIcon : tab.icon,
                          color: active ? AppColors.navy : AppColors.gray400, size: 22),
                        const SizedBox(height: 2),
                        Text(tab.label, style: TextStyle(
                          fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? AppColors.navy : AppColors.gray400)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
