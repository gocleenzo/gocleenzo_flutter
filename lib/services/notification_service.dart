import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../router.dart' show rootNavigatorKey;

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _supabase  = Supabase.instance.client;

  static const _softAskShownKey = 'notif_soft_ask_shown_v1';

  static void setContext(BuildContext context) {}

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important Cleenzo notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    try {
      await _setupLocalNotifications();
    } catch (e) {
      // Defensive — local-notification setup failing should never be
      // able to take down the rest of the notification flow (FCM
      // listeners, permission handling, token saving) the way the
      // missing-iOS-settings bug above did. Local notifications (the
      // foreground in-app banner) would be degraded, but everything
      // else below still runs.
      debugPrint('Local notifications setup failed (non-fatal): $e');
    }

    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refreshed');
      _saveTokenToSupabase(newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground message: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Notification tapped (background): ${message.data}');
      _handleMessageTap(message.data);
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('App opened from notification: ${initial.data}');
      await Future.delayed(const Duration(milliseconds: 800));
      _handleMessageTap(initial.data);
    }

    final existing = await _messaging.getNotificationSettings();
    if (existing.authorizationStatus == AuthorizationStatus.authorized ||
        existing.authorizationStatus == AuthorizationStatus.provisional) {
      await _saveToken();
      return;
    }
    if (existing.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    await _maybeShowSoftAskThenRequestPermission();
  }

  static Future<void> _maybeShowSoftAskThenRequestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_softAskShownKey) ?? false;
    if (alreadyShown) return;

    BuildContext? ctx;
    for (var i = 0; i < 20; i++) {
      ctx = rootNavigatorKey.currentContext;
      if (ctx != null) break;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    await prefs.setBool(_softAskShownKey, true);

    if (ctx == null) {
      await _requestRealPermissionAndSaveToken();
      return;
    }

    final allowed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Stay updated on your bookings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: const Text(
          'Turn on notifications to know the moment a cleaner is assigned, '
          'on the way, or your cleaning is complete.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B1FC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Turn on notifications'),
          ),
        ],
      ),
    );

    if (allowed == true) {
      await _requestRealPermissionAndSaveToken();
    }
  }

  static Future<void> _requestRealPermissionAndSaveToken() async {
    final settings = await _messaging.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );
    debugPrint('Notification permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Notifications denied by user');
      return;
    }
    await _saveToken();
  }

  static Future<void> _setupLocalNotifications() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    // FIXED: flutter_local_notifications REQUIRES iOS settings when
    // running on iOS — without this, .initialize() below throws
    // "iOS settings must be set when targeting iOS platform" as an
    // UNCAUGHT exception, which crashes the entire initialize() chain
    // before it ever reaches the permission/token-saving code further
    // down. This is why nothing related to notifications ever ran on
    // iOS — not the soft-ask, not permission requests, not token
    // saving — the whole thing died silently at this very first step
    // every single time on iOS, release mode included (where the
    // crash produces no visible error to the user at all).
    //
    // request*Permission are all false here deliberately — actual
    // permission requesting is handled entirely by our own soft-ask
    // flow via FirebaseMessaging.requestPermission() further down;
    // letting this plugin ALSO request permission on init would risk
    // firing the real OS prompt before our soft-ask dialog even has a
    // chance to show.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Local notification tapped: ${details.payload}');
        if (details.payload != null && details.payload!.isNotEmpty) {
          _navigateToBooking(details.payload!);
        }
      },
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    final details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data['booking_id'],
    );
  }

  static void _handleMessageTap(Map<String, dynamic> data) {
    final bookingId = data['booking_id'] as String?;
    if (bookingId == null || bookingId.isEmpty) return;
    _navigateToBooking(bookingId);
  }

  static void _navigateToBooking(String bookingId) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) {
      debugPrint(
          'No router context available yet for navigation to booking '
          '$bookingId');
      return;
    }
    GoRouter.of(ctx).push('/bookings/$bookingId');
  }

  static Future<void> _saveToken() async {
    try {
      if (Platform.isIOS) {
        final apnsReady = await _waitForApnsToken();
        if (!apnsReady) {
          debugPrint(
              'FCM token skipped: APNs token never became available '
              '(iOS). Will retry on next app open or via onTokenRefresh.');
          return;
        }
      }

      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('FCM getToken() returned null even after APNs wait');
        return;
      }
      debugPrint('FCM Token: $token');
      await _saveTokenToSupabase(token);
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  static Future<bool> _waitForApnsToken({
    int maxAttempts = 10,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null) {
        debugPrint('APNs token ready after $attempt attempt(s)');
        return true;
      }
      await Future.delayed(delay);
    }
    debugPrint('APNs token still null after $maxAttempts attempts');
    return false;
  }

  // UPDATED: multi-device support. Instead of overwriting a single
  // users.fcm_token column (which meant a second device's login
  // silently killed the first device's notifications), this upserts
  // a row into user_fcm_tokens keyed on the TOKEN itself. Every
  // device this account is logged into keeps its own row and keeps
  // receiving pushes independently.
  static Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = _supabase.auth.currentUser;
      String? userId = user?.id;

      if (userId == null) {
        final prefs = await SharedPreferences.getInstance();
        userId = prefs.getString('app_user_id');
      }

      if (userId == null) return;

      await _supabase.from('user_fcm_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
      debugPrint('FCM token saved (multi-device) for user: $userId');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  static Future<void> saveTokenAfterLogin() async {
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _saveToken();
    }
  }

  // UPDATED: only removes THIS device's own token row — signing out
  // on Android must not affect the same account's iPhone token (or
  // vice versa). Reads the current device's own token directly from
  // FCM (cached locally, doesn't require re-requesting permission)
  // rather than clearing anything user-wide.
  static Future<void> clearTokenOnLogout() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _supabase.from('user_fcm_tokens').delete().eq('token', token);
        debugPrint('FCM token cleared for this device only');
      }
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }
  }
}