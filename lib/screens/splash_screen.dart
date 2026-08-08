import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/app_update_service.dart';
import '../utils/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Guards against build() touching the late _ctrl field before
  // _startSplash() has actually run — since the update check now sits
  // behind an await before that happens.
  bool _splashStarted = false;
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _wordOpacity;
  late Animation<double> _entranceOpacity;

  // Total splash animation budget: 2500ms here + 500ms for the
  // router's zoom-in page transition on the next screen = 3000ms.
  static const _totalDuration = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    debugPrint('🔵 SPLASH INIT — update check starting now');

    // Check for a mandatory Play Store update FIRST — before the splash
    // animation even starts, so a customer on an outdated build never
    // gets to see the app's normal UI at all. If Play grants an
    // Immediate update, this call blocks (Play's own full-screen prompt
    // takes over) until the update completes or is cancelled by the OS;
    // it never returns to let the rest of this screen proceed in that
    // case. If no update is needed/available, it resolves quickly and
    // the splash animation continues completely normally.
    _checkForUpdateThenStart();
  }

  Future<void> _checkForUpdateThenStart() async {
    debugPrint('🔵 Calling AppUpdateService.checkAndForceImmediateUpdate()');
    final triggered = await AppUpdateService.checkAndForceImmediateUpdate();
    debugPrint('🔵 Update check finished — immediate update triggered: $triggered');
    if (!mounted) return;
    _startSplash();
  }

  void _startSplash() {
    _ctrl = AnimationController(vsync: this, duration: _totalDuration);

    // Fades the wordmark in right at the start (pop-in).
    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.10, curve: Curves.easeIn),
      ),
    );

    // Fades the wordmark OUT only during the final part of the zoom,
    // so it dissolves as it grows past the edges of the screen.
    _wordOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.85, 1.0, curve: Curves.easeIn),
      ),
    );

    // ONE continuous scale motion for the whole splash, in four
    // stages (weights are fractions of the 2500ms duration):
    //   1. Pop in with a slight springy overshoot   (0%   -> 15%,  375ms)
    //   2. Settle back down to exactly normal size   (15%  -> 20%,  125ms)
    //   3. Hold steady at normal size                (20%  -> 55%,  875ms)
    //   4. Rapid accelerating zoom out to fill screen (55%  -> 100%, 1125ms)
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.4, end: 1.06)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 9.0)
            .chain(CurveTween(curve: Curves.easeInExpo)),
        weight: 45,
      ),
    ]).animate(_ctrl);

    setState(() => _splashStarted = true);

    _ctrl.forward();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigate();
      }
    });
  }

  Future<void> _navigate() async {
    // Check both Supabase and Firebase auth
    final supaUser = SupabaseService.currentUser;
    final fireUser = fb.FirebaseAuth.instance.currentUser;

    if (supaUser == null && fireUser == null) {
      if (mounted) context.go('/login');
      return;
    }

    // If logged in via Firebase only, look up user by phone in users table
    if (supaUser == null && fireUser != null) {
      try {
        final phone = fireUser.phoneNumber;
        if (phone == null) {
          if (mounted) context.go('/login');
          return;
        }
        final profile = await Supabase.instance.client
            .from('users')
            .select()
            .eq('phone', phone)
            .maybeSingle();

        if (!mounted) return;

        if (profile == null) {
          context.go('/login');
          return;
        }

        // In the customer app, all roles go to /services
        // Workers should use the separate worker app
        context.go('/services');
      } catch (e) {
        if (mounted) context.go('/login');
      }
      return;
    }

    // Normal Supabase auth flow
    final profile = await SupabaseService.getUserProfile(supaUser!.id);
    final role = profile?['role'] ?? 'customer';
    if (!mounted) return;
    // In the customer app, all roles go to /services
    // Workers should use the separate worker app
    context.go('/services');
  }

  @override
  void dispose() {
    if (_splashStarted) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Plain background only, while the update check is still running —
    // _ctrl doesn't exist yet at this point, so nothing here may
    // reference it. This also means: if Play Store's Immediate update
    // prompt takes over, all the customer ever sees behind/before it is
    // this blank cyan background, never a half-initialized animation.
    if (!_splashStarted) {
      return const Scaffold(backgroundColor: AppColors.cyan);
    }

    return Scaffold(
      backgroundColor: AppColors.cyan,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Opacity(
              opacity: _entranceOpacity.value * _wordOpacity.value,
              child: Transform.scale(
                scale: _scale.value,
                // Entire wordmark + sparkle is ONE widget under a
                // single Transform.scale — nothing animates
                // independently, so it can never look scattered.
                child: const _CleenzoWordmark(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The "Cleenzo✦" wordmark — white Montserrat Bold text with the "zo"
/// in #001C42, plus a gently twinkling sparkle. No image asset, no
/// logo file.
class _CleenzoWordmark extends StatefulWidget {
  const _CleenzoWordmark();

  @override
  State<_CleenzoWordmark> createState() => _CleenzoWordmarkState();
}

class _CleenzoWordmarkState extends State<_CleenzoWordmark>
    with SingleTickerProviderStateMixin {
  late AnimationController _twinkleCtrl;
  late Animation<double> _twinkleScale;
  late Animation<double> _twinkleOpacity;

  static const _zoColor = Color(0xFF001C42);

  @override
  void initState() {
    super.initState();
    _twinkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _twinkleScale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _twinkleCtrl, curve: Curves.easeInOut),
    );
    _twinkleOpacity = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _twinkleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _twinkleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Cleen',
              style: GoogleFonts.montserrat(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
            Text(
              'zo',
              style: GoogleFonts.montserrat(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: _zoColor,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ],
        ),
        Positioned(
          top: -6,
          right: -20,
          child: AnimatedBuilder(
            animation: _twinkleCtrl,
            builder: (_, __) {
              return Opacity(
                opacity: _twinkleOpacity.value,
                child: Transform.scale(
                  scale: _twinkleScale.value,
                  child: const Text(
                    '✦',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
} 