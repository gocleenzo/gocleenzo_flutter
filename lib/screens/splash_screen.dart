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
  late Animation<double> _opacity;
  late Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _scale = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.04, 0.5, curve: Curves.easeOutExpo),
      ),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.04, 0.25, curve: Curves.easeIn),
      ),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.82, 1.0, curve: Curves.easeIn),
      ),
    );

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
              opacity: _fadeOut.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _opacity.value,
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                'Cleen',
                                style: GoogleFonts.nunito(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.navy,
                                  letterSpacing: -1,
                                  height: 1,
                                ),
                              ),
                              Text(
                                'zo',
                                style: GoogleFonts.nunito(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            top: -8,
                            right: -18,
                            child: Text(
                              '✦',
                              style: TextStyle(
                                fontSize: 22,
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Opacity(
                    opacity: _opacity.value,
                    child: Text(
                      'CLEAN HOME. HAPPY YOU',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.navy.withOpacity(0.8),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Opacity(
                    opacity: _opacity.value,
                    child: const _PulsingDots(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      );
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrls[i],
          builder: (_, __) {
            final v = _ctrls[i].value;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5 + 0.5 * v),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.identity()..scale(1.0 + 0.6 * v),
              transformAlignment: Alignment.center,
            );
          },
        );
      }),
    );
  }
}