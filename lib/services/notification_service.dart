import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _supabase  = Supabase.instance.client;

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
      debugPrint('Notification tapped: ${message.data}');
      _handleMessageTap(message);
    });

    // 7. Check if app was opened from a terminated notification
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('App opened from notification: ${initial.data}');
      _handleMessageTap(initial);
    }
  }

  // ── Setup local notifications ──────────────────────────────
  static Future<void> _setupLocalNotifications() async {
    // Create high importance channel on Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    // Initialize plugin
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings =
        InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Local notification tapped: ${details.payload}');
      },
    );

    // Tell FCM to not show notifications automatically
    // (we handle them via local notifications instead)
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

  // ── Save FCM token to Supabase ─────────────────────────────
  static Future<void> _saveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      debugPrint('FCM Token: $token');
      await _saveTokenToSupabase(token);
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('users').update({
        'fcm_token': token,
      }).eq('id', user.id);
      debugPrint('FCM token saved to Supabase');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  // ── Handle notification tap ────────────────────────────────
  static void _handleMessageTap(RemoteMessage message) {
    final bookingId = message.data['booking_id'] as String?;
    debugPrint('Tapped notification for booking: $bookingId');
  }

  // ── Call this after login to save token ───────────────────
  static Future<void> saveTokenAfterLogin() async {
    await _saveToken();
  }

  // ── Call this on logout to clear token ────────────────────
  static Future<void> clearTokenOnLogout() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('users').update({
        'fcm_token': null,
      }).eq('id', user.id);
      await _messaging.deleteToken();
      debugPrint('FCM token cleared');
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }
  }
}