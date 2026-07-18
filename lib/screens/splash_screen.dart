import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
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

        final role = profile['role'] ?? 'customer';
        if (role == 'worker') {
          context.go('/worker/dashboard');
        } else if (role == 'owner') {
          context.go('/admin-overview');
        } else {
          context.go('/services');
        }
      } catch (e) {
        if (mounted) context.go('/login');
      }
      return;
    }

    // Normal Supabase auth flow
    final profile = await SupabaseService.getUserProfile(supaUser!.id);
    final role = profile?['role'] ?? 'customer';
    if (!mounted) return;
    if (role == 'worker') {
      context.go('/worker/dashboard');
    } else if (role == 'owner') {
      context.go('/admin-overview');
    } else {
      context.go('/services');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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