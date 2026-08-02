import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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

// ── Native back-button bridge ────────────────────────────────────
// On some OEM ROMs (observed on this ColorOS build), Flutter's normal
// back-dispatch pipeline (Activity.onBackPressed -> engine ->
// WidgetsBinding.backButtonDispatcher -> PopScope) silently fails to
// deliver the event to Dart, even though the native onBackPressed()
// genuinely runs. MainActivity.kt now bypasses that pipeline entirely
// and calls this channel directly instead. We handle navigation here,
// globally, based on GoRouter's current location — this does not rely
// on PopScope at all, so it works regardless of the OEM bug above.
const _backChannel = MethodChannel('com.cubicleventurespvtltd.cleenzoapp/back');

DateTime? _lastBackPress;

void _handleNativeBack() {
  debugPrint('[NATIVE BACK] handler called');
  final ctx = rootNavigatorKey.currentContext;
  debugPrint('[NATIVE BACK] ctx=$ctx');
  if (ctx == null) return;

  final goRouter = GoRouter.of(ctx);
  final canPop = goRouter.canPop();
  debugPrint('[NATIVE BACK] canPop=$canPop');

  if (canPop) {
    goRouter.pop();
    return;
  }

  final loc = goRouter.routerDelegate.currentConfiguration.uri.path;
  debugPrint('[NATIVE BACK] loc=$loc');

  if (loc != '/services') {
    // No history beneath us on any secondary screen (Bookings, Offers,
    // Account, etc.) — standard bottom-nav convention: back always
    // returns to the Services (home) tab first.
    goRouter.go('/services');
    return;
  }

  // Already on Services with no history — require a second back press
  // within 2s before actually exiting.
  final now = DateTime.now();
  if (_lastBackPress == null ||
      now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
    _lastBackPress = now;
    ScaffoldMessenger.of(ctx).clearSnackBars();
    ScaffoldMessenger.of(ctx).showSnackBar(
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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
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
    NotificationService.initialize();

    _backChannel.setMethodCallHandler((call) async {
      if (call.method == 'backPressed') {
        _handleNativeBack();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp.router doesn't support navigatorKey directly.
    // Instead we use a Builder to get a context after the router
    // is set up, then store it in NotificationService so it can
    // navigate to booking detail when a notification is tapped.
    return MaterialApp.router(
      title: 'Cleenzo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: router,
    );
  }
}