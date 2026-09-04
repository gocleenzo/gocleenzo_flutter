import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationOptInBanner extends StatefulWidget {
  const NotificationOptInBanner({super.key});

  @override
  State<NotificationOptInBanner> createState() => _NotificationOptInBannerState();
}

class _NotificationOptInBannerState extends State<NotificationOptInBanner>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _denied = settings.authorizationStatus == AuthorizationStatus.denied;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_denied) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDD5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.notifications_off_rounded, color: Color(0xFFEA580C), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Notifications are off',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF9A3412))),
              const SizedBox(height: 2),
              const Text('Turn them on to know when your cleaner is assigned or on the way.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309), height: 1.3)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => openAppSettings(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Turn on',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
