import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _supabase  = Supabase.instance.client;

  // Store router context for navigation on notification tap.
  // Call NotificationService.setContext(context) from your root widget.
  static BuildContext? _context;
  static void setContext(BuildContext context) => _context = context;

  // Local notifications plugin
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // High importance channel for Android
  static const _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important Cleenzo notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // ── Initialize ─────────────────────────────────────────────
  static Future<void> initialize() async {
    // 1. Request FCM permission
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

    // 2. Setup local notifications
    await _setupLocalNotifications();

    // 3. Get FCM token and save to Supabase
    await _saveToken();

    // 4. Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refreshed');
      _saveTokenToSupabase(newToken);
    });

    // 5. Handle foreground messages — show as local notification
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground message: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // 6. Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Notification tapped (background): ${message.data}');
      _handleMessageTap(message.data);
    });

    // 7. Check if app was opened from a terminated notification
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('App opened from notification: ${initial.data}');
      // Delay so router is ready before navigating
      await Future.delayed(const Duration(milliseconds: 800));
      _handleMessageTap(initial.data);
    }
  }

  // ── Setup local notifications ──────────────────────────────
  static Future<void> _setupLocalNotifications() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings =
        InitializationSettings(android: androidSettings);

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

  // ── Show local notification ────────────────────────────────
  static Future<void> _showLocalNotification(
      RemoteMessage message) async {
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
      largeIcon: const DrawableResourceAndroidBitmap(
          '@mipmap/ic_launcher'),
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

  // ── Handle notification tap ────────────────────────────────
  static void _handleMessageTap(Map<String, dynamic> data) {
    final bookingId = data['booking_id'] as String?;
    if (bookingId == null || bookingId.isEmpty) return;
    _navigateToBooking(bookingId);
  }

  static void _navigateToBooking(String bookingId) {
    final ctx = _context;
    if (ctx == null) {
      debugPrint('No context for navigation to booking $bookingId');
      return;
    }
    // Use Navigator directly since go_router's context push works here
    Navigator.of(ctx, rootNavigator: true).pushNamed(
      '/bookings/$bookingId',
    );
  }

  // ── Save FCM token to Supabase ─────────────────────────────
  //
  // FIXED: on iOS, calling FirebaseMessaging.getToken() before Apple's
  // own APNs (Apple Push Notification service) token has finished
  // registering with the OS returns null SILENTLY — no exception, no
  // error, `getToken()` just resolves to null. The original code called
  // getToken() immediately after requestPermission(), which on a real
  // device is almost always too early: APNs registration happens
  // asynchronously in the background and can take anywhere from
  // under a second to several seconds depending on network conditions.
  // Since this whole call chain is wrapped in a non-fatal try/catch at
  // the call site (login_screen.dart), a null token was never surfaced
  // as an error anywhere — it just silently resulted in fcm_token never
  // getting saved, which is exactly the symptom we were chasing
  // (iOS customers showing fcm_token: null even after logging in).
  //
  // Fix: on iOS specifically, wait for getAPNSToken() to return non-null
  // FIRST (polling with a short delay, up to a bounded number of
  // attempts), and only THEN call getToken(). Android is unaffected —
  // it has no APNs concept at all, so this whole wait is skipped there
  // and behavior is identical to before.
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

  /// Polls FirebaseMessaging.instance.getAPNSToken() until it returns a
  /// non-null value, or gives up after [maxAttempts] tries. Returns true
  /// once ready, false if it timed out. No-op concept on Android (this
  /// is only ever called when Platform.isIOS is true — see _saveToken).
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
    debugPrint('APNs token still null after $maxAttempts attempts '
        '(~${(maxAttempts * delay.inMilliseconds / 1000).toStringAsFixed(1)}s)');
    return false;
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    try {
      // Use cached userId since app uses Firebase Phone Auth +
      // custom Supabase session — auth.currentUser is null in this setup.
      final user = _supabase.auth.currentUser;
      String? userId = user?.id;

      // Fallback to cached userId for Firebase Phone Auth flow
      if (userId == null) {
        final prefs = await SharedPreferences.getInstance();
        userId = prefs.getString('app_user_id');
      }

      if (userId == null) return;
      await _supabase.from('users').update({
        'fcm_token': token,
      }).eq('id', userId);
      debugPrint('FCM token saved to Supabase for user: $userId');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  // ── Call this after login to save token ───────────────────
  static Future<void> saveTokenAfterLogin() async {
    await _saveToken();
  }

  // ── Call this on logout to clear token ────────────────────
  static Future<void> clearTokenOnLogout() async {
    try {
      final user = _supabase.auth.currentUser;
      String? userId = user?.id;
      if (userId == null) {
        final prefs = await SharedPreferences.getInstance();
        userId = prefs.getString('app_user_id');
      }
      if (userId == null) return;
      await _supabase.from('users').update({
        'fcm_token': null,
      }).eq('id', userId);
      await _messaging.deleteToken();
      debugPrint('FCM token cleared');
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }
  }
}