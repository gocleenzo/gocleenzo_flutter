import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';

class CustomerShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const CustomerShell({super.key, required this.navigationShell});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  static const _tabs = [
    (path: '/services', icon: Icons.cleaning_services_outlined,
      active: Icons.cleaning_services, label: 'Services'),
    (path: '/bookings', icon: Icons.receipt_long_outlined,
      active: Icons.receipt_long,      label: 'Bookings'),
    (path: '/offers',   icon: Icons.local_offer_outlined,
      active: Icons.local_offer,       label: 'Offers'),
  ];

  /// Timestamp of the last back-press while already on the Services tab —
  /// used for the "press back again to exit" pattern below, so a single
  /// accidental back press can never instantly kill the app.
  DateTime? _lastBackPress;

  int _idx(BuildContext ctx) => widget.navigationShell.currentIndex;

  bool _isOnServices(BuildContext ctx) =>
      widget.navigationShell.currentIndex == 0;

  void _handleBack(BuildContext context) {
    // If there's a real screen underneath (e.g. pushed on top of a tab's
    // own branch stack), respect that stack first — otherwise we'd
    // silently blow away whatever was pushed below us.
    if (context.canPop()) {
      context.pop();
      return;
    }

    final onServices = _isOnServices(context);

    if (!onServices) {
      // No real history beneath us — fall back to standard bottom-nav
      // convention: back always returns to the Services (home) tab first.
      widget.navigationShell.goBranch(0);
      return;
    }

    // Already on the home tab with no history — require a second back
    // press within 2s before actually exiting, so a stray tap can't
    // instantly close the app.
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep NotificationService context fresh so notification taps
    // can navigate to the correct booking detail screen.
    NotificationService.setContext(context);

    final idx = _idx(context);

    return PopScope(
      // Always intercept and decide manually in _handleBack — avoids any
      // staleness issue with computing canPop once per build.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        body: widget.navigationShell,
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
                      onTap: () => widget.navigationShell.goBranch(
                        i,
                        initialLocation: i == widget.navigationShell.currentIndex,
                      ),
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