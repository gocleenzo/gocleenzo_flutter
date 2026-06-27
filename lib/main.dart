import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'router.dart';
import 'utils/theme.dart';
import 'services/notification_service.dart';

const _supabaseUrl     = 'https://hxrqgqhlbdconvgmmhgu.supabase.co';
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh4cnFncWhsYmRjb252Z21taGd1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2ODIwMjQsImV4cCI6MjA5NTI1ODAyNH0.mHaAtk4e_vPysJ-6MBdYgZNirgp8bj3iabwkDmjxfFw';

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Firebase
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler);

  // Initialize Supabase
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  runApp(const ProviderScope(child: CleenzoApp()));
}

class CleenzoApp extends StatefulWidget {
  const CleenzoApp({super.key});
  @override
  State<CleenzoApp> createState() => _CleenzoAppState();
}

class _CleenzoAppState extends State<CleenzoApp> {
  @override
  void initState() {
    super.initState();
    // Initialize notifications after app starts
    NotificationService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cleenzo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: router,
    );
  }
}