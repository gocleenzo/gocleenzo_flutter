import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/theme.dart';

class AdminShell extends StatelessWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  static const _tabs = [
    (path: '/admin-overview',    icon: Icons.bar_chart_outlined,   activeIcon: Icons.bar_chart,    label: 'Overview'),
    (path: '/admin-bookings',    icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Bookings'),
    (path: '/admin-workers',     icon: Icons.people_outline,        activeIcon: Icons.people,       label: 'Workers'),
    (path: '/admin-reports',     icon: Icons.assessment_outlined,   activeIcon: Icons.assessment,   label: 'Reports'),
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
        decoration: BoxDecoration(
          color: const Color(0xFF0D2D5E),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 16)],
        ),
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
                          color: active ? AppColors.cyan : Colors.white38, size: 22),
                        const SizedBox(height: 2),
                        Text(tab.label, style: TextStyle(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? AppColors.cyan : Colors.white38,
                        )),
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
