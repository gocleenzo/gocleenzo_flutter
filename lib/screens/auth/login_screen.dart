import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../../widgets/auth_widgets.dart';

// ── Shared palette (mirrors the services screen) ────────────────
const _kCyan   = Color(0xFF00B1FC);
const _kCyanDk = Color(0xFF00B1FC);
const _kCyanBg = Color(0xFF00B1FC);
const _kCyanB2 = Color(0xFF00B1FC);
const _kInk    = Color(0xFF0F172A);
const _kFaint  = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE8EDF2);
const _kBg     = Color(0xFFF8FAFC);

// ── Marquee card data (real Cleenzo service photos) ─────────────
const _rowCardsA = [
  {'img': 'assets/services/bathroom-cleaning.png',  'label': 'Bathroom Cleaning'},
  {'img': 'assets/services/kitchen-cleaning.png',   'label': 'Kitchen Cleaning'},
  {'img': 'assets/services/full-home-cleaning.png', 'label': 'Full Home Cleaning'},
  {'img': 'assets/services/fan-cleaning.png',       'label': 'Fan Cleaning'},
  {'img': 'assets/services/balcony-cleaning.png',   'label': 'Balcony Cleaning'},
  {'img': 'assets/services/fridge-cleaning.png',    'label': 'Refrigerator Cleaning'},
  {'img': 'assets/services/wardrobe.png',           'label': 'Wardrobe Cleaning'},
];
const _rowCardsB = [
  {'img': 'assets/services/dusting-wiping.png',     'label': 'Dusting & Wiping'},
  {'img': 'assets/services/sweeping-mopping.png',   'label': 'Sweeping & Mopping'},
  {'img': 'assets/services/cabinet.png',            'label': 'Kitchen Cabinet'},
  {'img': 'assets/services/Utensils-cleaning.png',  'label': 'Utensil Cleaning'},
  {'img': 'assets/services/after.png',              'label': 'After-Party Cleanup'},
  {'img': 'assets/services/pre.png',                'label': 'Pre-Party Cleaning'},
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _supabase  = Supabase.instance.client;
  final _fireAuth  = fb.FirebaseAuth.instance;
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();

  String  _step           = 'phone';
  String  _otp            = '';
  String  _gender         = '';
  bool    _loading        = false;
  String  _error          = '';
  String? _verificationId;
  String? _userId;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── STEP 1: Send OTP via Firebase ────────────────────────────
  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.length < 10) return;
    setState(() { _loading = true; _error = ''; });

    try {
      await _fireAuth.verifyPhoneNumber(
        phoneNumber: '+91${_phoneCtrl.text}',
        timeout: const Duration(seconds: 60),
        verificationCompleted: (fb.PhoneAuthCredential credential) async {
          debugPrint('Auto-verification completed');
          await _signInWithCredential(credential);
        },
        verificationFailed: (fb.FirebaseAuthException e) {
          debugPrint('Verification failed: ${e.message}');
          if (mounted) setState(() {
            _error   = e.message ?? 'Failed to send OTP. Try again.';
            _loading = false;
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('OTP sent. verificationId set.');
          if (mounted) setState(() {
            _verificationId = verificationId;
            _step           = 'otp';
            _loading        = false;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('Auto retrieval timeout');
          if (mounted) setState(() {
            _verificationId = verificationId;
          });
        },
      );
    } catch (e) {
      debugPrint('Send OTP error: $e');
      if (mounted) setState(() {
        _error   = 'Failed to send OTP. Please try again.';
        _loading = false;
      });
    }
  }

  // ── STEP 2: Verify OTP ────────────────────────────────────────
  Future<void> _verifyOtp() async {
    debugPrint('_verifyOtp called. OTP: $_otp, verificationId: $_verificationId');
    if (_otp.length < 6) {
      setState(() => _error = 'Please enter the 6-digit OTP');
      return;
    }
    if (_verificationId == null) {
      setState(() => _error = 'Verification session expired. Please resend OTP.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final credential = fb.PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode:        _otp,
      );
      await _signInWithCredential(credential);
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
      if (mounted) setState(() {
        _error   = e.code == 'invalid-verification-code'
            ? 'Invalid OTP. Please try again.'
            : e.message ?? 'Verification failed.';
        _loading = false;
      });
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      if (mounted) setState(() {
        _error   = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  // ── Sign in with Firebase → call Edge Function ────────────────
  Future<void> _signInWithCredential(
      fb.PhoneAuthCredential credential) async {
    // ── Phase 1: Firebase auth + edge function. If either fails,
    // the user genuinely isn't signed in — show "Sign in failed".
    fb.User? fireUser;
    Map<String, dynamic> data;
    try {
      debugPrint('Signing in with credential...');
      final userCred = await _fireAuth.signInWithCredential(credential);
      fireUser = userCred.user;
      if (fireUser == null) throw Exception('Firebase user is null');
      debugPrint('Firebase signed in: ${fireUser.uid}');

      final phone = '+91${_phoneCtrl.text}';

      debugPrint('Calling edge function...');
      final res = await _supabase.functions.invoke(
        'firebase-auth',
        body: {
          'firebase_uid': fireUser.uid,
          'phone':        phone,
        },
      );

      debugPrint('Edge function status: ${res.status}');
      data = res.data as Map<String, dynamic>;
      debugPrint('Edge function response: $data');
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('Firebase sign in error: ${e.code} - ${e.message}');
      if (mounted) setState(() {
        _error   = e.message ?? 'Sign in failed.';
        _loading = false;
      });
      return;
    } on FunctionException catch (e) {
      // Thrown by supabase_flutter when the edge function returns
      // a non-2xx status or can't be reached.
      debugPrint('Edge function error: ${e.status} - ${e.details}');
      if (mounted) setState(() {
        _error   = 'Could not verify your account. Please try again.';
        _loading = false;
      });
      return;
    } catch (e) {
      debugPrint('Sign in error: $e');
      if (mounted) setState(() {
        _error   = 'Sign in failed. Please try again.';
        _loading = false;
      });
      return;
    }

    if (!mounted) return;

    if (data['is_new_user'] == true) {
      debugPrint('New user — going to profile step');
      setState(() { _step = 'profile'; _loading = false; });
      return;
    }

    // ── Phase 2: non-critical post-login steps. Firebase + the
    // edge function already succeeded, so the user IS signed in —
    // a failure here must never surface as "Sign in failed", and
    // must never block navigation to /services.
    debugPrint('Existing user — navigating to services');
    _userId = data['user_id'] as String?;

    if (_userId != null) {
      try {
        await SupabaseService.setCachedUserId(_userId!);
      } catch (e) {
        debugPrint('setCachedUserId failed (non-fatal): $e');
      }
    }

    try {
      await NotificationService.saveTokenAfterLogin();
    } catch (e) {
      debugPrint('saveTokenAfterLogin failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // Small delay lets Firebase auth state propagate to the router
    await Future.delayed(const Duration(milliseconds: 300));
    debugPrint('About to call context.go(/services). mounted=$mounted');
    if (mounted) {
      try {
        context.go('/services');
        debugPrint('context.go(/services) call completed without throwing');
      } catch (navErr, st) {
        debugPrint('NAVIGATION ERROR: $navErr');
        debugPrint('Stack: $st');
      }
    }
  }

  // ── STEP 3: Save profile (new users) ─────────────────────────
  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final phone = '+91${_phoneCtrl.text}';
      final data  = await _supabase.from('users').insert({
        'full_name': _nameCtrl.text.trim(),
        'phone':     phone,
        'role':      'customer',
        'gender':    _gender.isEmpty ? null : _gender,
      }).select().single();

      _userId = data['id'] as String;

      try {
        await SupabaseService.setCachedUserId(_userId!);
      } catch (e) {
        debugPrint('setCachedUserId failed (non-fatal): $e');
      }
      try {
        await NotificationService.saveTokenAfterLogin();
      } catch (e) {
        debugPrint('saveTokenAfterLogin failed (non-fatal): $e');
      }

      if (!mounted) return;
      context.go('/location-gate');
    } catch (e) {
      debugPrint('Save profile error: $e');
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Open an external website link (Terms / Privacy) ──────────
  Future<void> _openExternalLink(String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    } catch (e) {
      debugPrint('Open link error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // New users get a dedicated, full blank page (no hero images).
    if (_step == 'profile') return _profilePage();

    final mq       = MediaQuery.of(context);
    final topPad   = mq.padding.top;
    final kbOpen   = mq.viewInsets.bottom > 0;
    final h        = mq.size.height;

    // Hero takes ~half the screen, clamped so it works on any device.
    // When the keyboard opens it shrinks a little (not away) so the
    // images stay visible while the form lifts above the keyboard.
    final baseHeroH = (h * 0.48).clamp(300.0, 480.0);
    final heroH     = kbOpen ? baseHeroH * 0.62 : baseHeroH;
    final rowsArea  = heroH - topPad - 24 - 14 - 12; // top gap, row gap, base
    final cardH     = (rowsArea / 2).clamp(96.0, 220.0);
    final cardW     = cardH * 0.86;

    // Proven skeleton: Column → hero → Expanded form sheet.
    return Scaffold(
      backgroundColor: _kBg,
      // Let the layout resize so the focused field lifts above the keyboard.
      resizeToAvoidBottomInset: true,
      body: Column(children: [

        // ── Hero: two photo marquees; shrinks gently while typing ──
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOut,
          height: heroH,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(color: _kCyanBg),
          child: Stack(children: [
            Positioned(top: -70, right: -60, child: _blob(220, _kCyanB2)),
            Positioned(top: 40, left: -70,
                child: _blob(170, const Color(0xFF00B1FC))),
            Column(children: [
              SizedBox(height: topPad + 24),
              _MarqueeRow(cards: _rowCardsA, reverse: false,
                  cardH: cardH, cardW: cardW),
              const SizedBox(height: 14),
              _MarqueeRow(cards: _rowCardsB, reverse: true,
                  cardH: cardH, cardW: cardW),
            ]),
            Positioned(bottom: 0, left: 0, right: 0, child: Container(
              height: 64,
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, _kBg])),
            )),
          ]),
        ),

        // ── Form sheet fills the rest (Expanded → can't collapse) ──
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24, offset: const Offset(0, -6))],
            ),
            child: Column(children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: _kBorder, borderRadius: BorderRadius.circular(2))),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(children: [
                    const BrandLogo(size: 46),
                    const SizedBox(height: 8),
                    const SizedBox(height: 3),
                    const Text('Log in or Sign up',
                        style: TextStyle(color: Color.fromARGB(255, 0, 0, 0), fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 24),

                    _buildStep(),

                    const SizedBox(height: 18),
                    _termsLine(),
                    const SizedBox(height: 6),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Step router (profile is handled as a full page in build) ──
  Widget _buildStep() {
    if (_step == 'otp') return _otpStep();
    return _phoneStep();
  }

  // ── Phone step ────────────────────────────────────────────────
  Widget _phoneStep() {
    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text('MOBILE NUMBER',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                color: const Color.fromARGB(255, 0, 0, 0), letterSpacing: 1.5)),
      ),
      const SizedBox(height: 8),
      _phoneField(),
      const SizedBox(height: 12),
      ErrorBox(message: _error),
      const SizedBox(height: 12),
      ValueListenableBuilder(
        valueListenable: _phoneCtrl,
        builder: (_, val, __) => CyanButton(
          label: 'Proceed',
          icon: Icons.arrow_forward,
          loading: _loading,
          onPressed: val.text.length == 10 ? _sendOtp : null,
        ),
      ),
    ]);
  }

  // ── Custom phone field with a bold, attractive number font ────
  Widget _phoneField() {
    return Container(
      decoration: BoxDecoration(
        color: _kCyanBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kCyanB2, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(children: [
        const Text('🇮🇳', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Text('+91', style: GoogleFonts.spaceGrotesk(
            fontSize: 19, fontWeight: FontWeight.w800, color: _kInk)),
        const SizedBox(width: 10),
        Container(width: 1.5, height: 24, color: _kCyanB2),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onSubmitted: (_) => _sendOtp(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.spaceGrotesk(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: _kInk, letterSpacing: 3.0),
            decoration: InputDecoration(
              counterText: '',
              border: InputBorder.none,
              hintText: '00000 00000',
              hintStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 22, fontWeight: FontWeight.w700,
                  color: _kFaint, letterSpacing: 3.0),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _phoneCtrl,
          builder: (_, val, __) => val.text.length == 10
              ? const Icon(Icons.check_circle_rounded, color: _kCyan, size: 22)
              : const SizedBox(width: 22),
        ),
      ]),
    );
  }

  // ── OTP step ──────────────────────────────────────────────────
  Widget _otpStep() {
    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => setState(
              () { _step = 'phone'; _error = ''; _verificationId = null; }),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back_ios, size: 16, color: AppColors.cyan),
            Text('Back', style: TextStyle(
                color: AppColors.cyan, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text('Enter the 6-digit code sent to',
          style: TextStyle(color: AppColors.gray500, fontSize: 13)),
      const SizedBox(height: 4),
      Text('+91 ${_phoneCtrl.text}',
          style: GoogleFonts.spaceGrotesk(color: AppColors.cyan,
              fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 1.5)),
      const SizedBox(height: 6),
      const SizedBox(height: 16),
      OtpInputRow(
        onCompleted: (v) {
          debugPrint('OTP completed: $v');
          setState(() => _otp = v);
          _verifyOtp();
        },
        onChange: (v) => setState(() => _otp = v),
      ),
      const SizedBox(height: 12),
      ErrorBox(message: _error),
      const SizedBox(height: 12),
      CyanButton(
        label: 'Verify & Continue',
        icon: Icons.check_circle_outline,
        loading: _loading,
        onPressed: _otp.length == 6 ? _verifyOtp : null,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _loading ? null : _sendOtp,
        child: Text('Resend OTP',
            style: TextStyle(
                color: AppColors.cyan, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  // ── Profile page (new users) — full, dedicated blank screen ───
  Widget _profilePage() {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back to OTP
              GestureDetector(
                onTap: () => setState(() { _step = 'otp'; _error = ''; }),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _kCyanBg, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: _kCyanDk, size: 22),
                ),
              ),
              const SizedBox(height: 20),

              // Brand
              const BrandLogo(size: 54),
              const SizedBox(height: 32),

              // Big heading
              Text('Welcome to Cleenzo!',
                  style: GoogleFonts.nunito(fontSize: 32,
                      fontWeight: FontWeight.w900, height: 1.15,
                      color: _kInk)),
              const SizedBox(height: 8),
              Text("Let's set up your profile so we can\npersonalise your cleans.",
                  style: TextStyle(fontSize: 15, height: 1.5,
                      color: _kFaint, fontWeight: FontWeight.w500)),
              const SizedBox(height: 36),

              // Name
              Text('YOUR NAME',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                      color: AppColors.gray400, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              _bigNameField(),
              const SizedBox(height: 32),

              // Gender
              Text('GENDER (OPTIONAL)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                      color: AppColors.gray400, letterSpacing: 1.5)),
              const SizedBox(height: 14),
              Row(
                children: ['Male', 'Female', 'Other'].map((g) {
                  final selected = _gender == g;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _gender = selected ? '' : g);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.cyan.withValues(alpha: 0.10)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? AppColors.cyan
                                  : const Color(0xFFDDE3EB),
                              width: selected ? 2.0 : 1.5,
                            ),
                          ),
                          child: Text(g, style: TextStyle(
                            color: selected
                                ? AppColors.cyan
                                : const Color(0xFF64748B),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          )),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              ErrorBox(message: _error),
              const SizedBox(height: 8),

              // Tall continue button
              SizedBox(
                width: double.infinity,
                child: ValueListenableBuilder(
                  valueListenable: _nameCtrl,
                  builder: (_, val, __) => CyanButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward,
                    loading: _loading,
                    onPressed: val.text.trim().isNotEmpty ? _saveProfile : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Larger name field for the profile page ────────────────────
  Widget _bigNameField() => Container(
    decoration: BoxDecoration(
      color: AppColors.cyanBg,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.cyanLight, width: 2),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    child: Row(children: [
      const Text('👤', style: TextStyle(fontSize: 22)),
      const SizedBox(width: 12),
      Expanded(
        child: TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w800,
              fontSize: 18, color: const Color(0xFF0F172A)),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Your full name',
            hintStyle: GoogleFonts.nunito(
                color: AppColors.cyanLight, fontSize: 18,
                fontWeight: FontWeight.w700),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: _nameCtrl,
        builder: (_, val, __) => val.text.isNotEmpty
            ? GestureDetector(
                onTap: () => _nameCtrl.clear(),
                child: Icon(Icons.cancel_rounded,
                    size: 20, color: AppColors.cyanLight))
            : const SizedBox.shrink(),
      ),
    ]),
  );

  Widget _termsLine() => RichText(
    textAlign: TextAlign.center,
    text: TextSpan(
      style: TextStyle(color: AppColors.gray400, fontSize: 11),
      children: [
        const TextSpan(text: 'By proceeding, I accept the '),
        WidgetSpan(
          child: GestureDetector(
            onTap: () => _openExternalLink('https://www.gocleenzo.com/terms'),
            child: Text('Terms of use',
                style: TextStyle(color: AppColors.cyan,
                    fontWeight: FontWeight.w600, fontSize: 11)),
          ),
        ),
        const TextSpan(text: ' & '),
        WidgetSpan(
          child: GestureDetector(
            onTap: () => _openExternalLink('https://www.gocleenzo.com/terms'),
            child: Text('Privacy policy',
                style: TextStyle(color: AppColors.cyan,
                    fontWeight: FontWeight.w600, fontSize: 11)),
          ),
        ),
      ],
    ),
  );

  Widget _blob(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ── Auto-scrolling marquee row of service photos ────────────────
class _MarqueeRow extends StatefulWidget {
  final List<Map<String, dynamic>> cards;
  final bool reverse;
  final double cardH;
  final double cardW;
  const _MarqueeRow({
    required this.cards,
    required this.reverse,
    required this.cardH,
    required this.cardW,
  });

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final ScrollController    _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _ctrl   = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();
    _ctrl.addListener(_tick);
  }

  void _tick() {
    if (!_scroll.hasClients) return;
    final maxScroll = _scroll.position.maxScrollExtent;
    if (maxScroll <= 0) return;
    // List is doubled, so half the extent is one seamless loop.
    final t = widget.reverse ? (1 - _ctrl.value) : _ctrl.value;
    _scroll.jumpTo(t * maxScroll / 2);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doubled = [...widget.cards, ...widget.cards];
    return SizedBox(
      height: widget.cardH,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: doubled.map(_card).toList()),
      ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    return Container(
      width: widget.cardW, height: widget.cardH,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          Image.asset(c['img'] as String, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: _kCyanB2)),
          // Bottom scrim for label legibility
          Container(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
            stops: const [0.45, 1.0]))),
          Positioned(left: 12, right: 12, bottom: 12, child: Text(
            c['label'] as String,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white,
                fontSize: 13, fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black45, blurRadius: 4)]))),
        ]),
      ),
    );
  }
}