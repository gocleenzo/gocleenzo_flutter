import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    // Initialize Supabase before tests
    await Supabase.initialize(
      url: 'https://hxrqgqhlbdconvgmmhgu.supabase.co  ',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh4cnFncWhsYmRjb252Z21taGd1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2ODIwMjQsImV4cCI6MjA5NTI1ODAyNH0.mHaAtk4e_vPysJ-6MBdYgZNirgp8bj3iabwkDmjxfFw',
    );
  });

  testWidgets('CleenzoApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CleenzoApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}