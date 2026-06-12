import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'utils/theme.dart';

// ⚠️  Replace these with your actual Supabase credentials from .env.local
const _supabaseUrl = 'https://hxrqgqhlbdconvgmmhgu.supabase.co';
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh4cnFncWhsYmRjb252Z21taGd1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2ODIwMjQsImV4cCI6MjA5NTI1ODAyNH0.mHaAtk4e_vPysJ-6MBdYgZNirgp8bj3iabwkDmjxfFw';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  runApp(const ProviderScope(child: CleenzoApp()));
}

class CleenzoApp extends StatelessWidget {
  const CleenzoApp({super.key});

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
