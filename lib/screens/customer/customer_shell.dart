import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';

class CustomerShell extends StatelessWidget {
  final Widget child;
  const CustomerShell({super.key, required this.child});

  static const _tabs = [
    (path: '/services', icon: Icons.cleaning_services_outlined,
      active: Icons.cleaning_services, label: 'Services'),
    (path: '/bookings', icon: Icons.receipt_long_outlined,
      active: Icons.receipt_long,      label: 'Bookings'),
    (path: '/offers',   icon: Icons.local_offer_outlined,
      active: Icons.local_offer,       label: 'Offers'),
  ];

  int _idx(BuildContext ctx) {
    final loc = GoRouterState.of(ctx).matchedLocation;
    final i   = _tabs.indexWhere((t) => t.path == loc);
    return i < 0 ? 0 : i;
  }

  bool _isOnServices(BuildContext ctx) {
    final loc = GoRouterState.of(ctx).matchedLocation;
    // ignore: avoid_print
    debugPrint('[BACKBTN] _isOnServices check — matchedLocation="$loc"');
    return loc == '/services';
  }

  @override
  Widget build(BuildContext context) {
    // Keep NotificationService context fresh so notification taps
    // can navigate to the correct booking detail screen.
    NotificationService.setContext(context);

    final idx = _idx(context);
    final onServices = _isOnServices(context);
    // ignore: avoid_print
    debugPrint('[BACKBTN] CustomerShell build — canPop will be set to $onServices');

    return PopScope(
      canPop: onServices,
      onPopInvokedWithResult: (didPop, result) {
        // ignore: avoid_print
        debugPrint('[BACKBTN] onPopInvokedWithResult fired — didPop=$didPop');
        if (didPop) return;
        // ignore: avoid_print
        debugPrint('[BACKBTN] Redirecting to /services now...');
        context.go('/services');
      },
      child: Scaffold(
        body: child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final tab    = _tabs[i];
                  final active = i == idx;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => context.go(tab.path),
                      behavior: HitTestBehavior.opaque,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                          decoration: active
                              ? BoxDecoration(
                                  color: const Color(0xFFE0F7FA),
                                  borderRadius: BorderRadius.circular(12),
                                )
                              : null,
                          child: Icon(
                            active ? tab.active : tab.icon,
                            color: active ? const Color(0xFF00B1FC) : const Color(0xFF94A3B8),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(tab.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? const Color(0xFF00B1FC) : const Color(0xFF94A3B8),
                            )),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}