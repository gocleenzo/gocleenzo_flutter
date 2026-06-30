import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../../widgets/auth_widgets.dart';

const _cleaningCards = [
  {'emoji': '🧹', 'label': 'Deep Cleaning',     'color': 0xFFE0F9FF},
  {'emoji': '🚿', 'label': 'Bathroom Cleaning',  'color': 0xFFDBEAFE},
  {'emoji': '🍳', 'label': 'Kitchen Cleaning',   'color': 0xFFFEF3C7},
  {'emoji': '🏠', 'label': 'Full Home Cleaning', 'color': 0xFFD1FAE5},
  {'emoji': '🪟', 'label': 'Window Cleaning',    'color': 0xFFEDE9FE},
  {'emoji': '🛋',  'label': 'Sofa Cleaning',      'color': 0xFFFCE7F3},
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
<<<<<<< HEAD
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
=======
      await SupabaseService.sendOtp(_phoneCtrl.text);
      setState(() => _step = 'otp');
    } catch (e) {
  debugPrint('===> OTP ERROR: $e');
  setState(() => _error = 'Failed to send OTP. Please try again.');
} finally {
      setState(() => _loading = false);
>>>>>>> 7b7a43646a02ef1a0f3ff5b2e13b499a96512c0f
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
    try {
      debugPrint('Signing in with credential...');
      final userCred = await _fireAuth.signInWithCredential(credential);
      final fireUser = userCred.user;
      if (fireUser == null) throw Exception('Firebase user is null');
      debugPrint('Firebase signed in: ${fireUser.uid}');

      final phone = '+91${_phoneCtrl.text}';

      // Call Supabase Edge Function
      debugPrint('Calling edge function...');
      final res = await _supabase.functions.invoke(
        'firebase-auth',
        body: {
          'firebase_uid': fireUser.uid,
          'phone':        phone,
        },
      );

      debugPrint('Edge function status: ${res.status}');
      final data = res.data as Map<String, dynamic>;
      debugPrint('Edge function response: $data');

      if (!mounted) return;

      if (data['is_new_user'] == true) {
        debugPrint('New user — going to profile step');
        setState(() { _step = 'profile'; _loading = false; });
      } else {
        debugPrint('Existing user — navigating to services');
        _userId = data['user_id'] as String?;
        if (_userId != null) {
          await SupabaseService.setCachedUserId(_userId!);
        }
        await NotificationService.saveTokenAfterLogin();
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
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('Firebase sign in error: ${e.code} - ${e.message}');
      if (mounted) setState(() {
        _error   = e.message ?? 'Sign in failed.';
        _loading = false;
      });
    } catch (e) {
      debugPrint('Sign in error: $e');
      if (mounted) setState(() {
        _error   = 'Sign in failed. Please try again.';
        _loading = false;
      });
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
      await SupabaseService.setCachedUserId(_userId!);
      await NotificationService.saveTokenAfterLogin();

      if (!mounted) return;
      context.go('/location-gate');
    } catch (e) {
      debugPrint('Save profile error: $e');
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [

        SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: Stack(children: [
            _ScrollingCards(),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 80,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.white, Colors.transparent],
                  ),
                ),
              ),
            ),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              const SizedBox(height: 8),
              const BrandLogo(size: 48),
              const SizedBox(height: 4),
              Text('Log in or Sign up',
                  style: TextStyle(color: AppColors.gray400,
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // ── Phone step ──────────────────────────────────
              if (_step == 'phone') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('MOBILE NUMBER',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.gray400,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(height: 8),
                PhoneInput(controller: _phoneCtrl, onSubmit: _sendOtp),
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
              ],

              // ── OTP step ────────────────────────────────────
              if (_step == 'otp') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => setState(
                        () { _step = 'phone'; _error = ''; _verificationId = null; }),
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: [
                      Icon(Icons.arrow_back_ios,
                          size: 16, color: AppColors.cyan),
                      Text('Back', style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Enter the 6-digit code sent to',
                    style: TextStyle(
                        color: AppColors.gray500, fontSize: 13)),
                const SizedBox(height: 4),
                Text('+91 ${_phoneCtrl.text}',
                    style: TextStyle(color: AppColors.cyan,
                        fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFFFCC02)
                            .withValues(alpha: 0.5))),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min, children: [
                    Text('🔥', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 4),
                    Text('Verified by Firebase',
                        style: TextStyle(
                            color: Color(0xFFE65100),
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
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
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w600)),
                ),
              ],

              // ── Profile step (new users) ─────────────────────
              if (_step == 'profile') ...[
                const SizedBox(height: 4),
                Text("What's your name?",
                    style: GoogleFonts.nunito(fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A))),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('FULL NAME',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.gray400,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(height: 8),
                _nameField(),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('GENDER (optional)',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.gray400,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: ['Male', 'Female', 'Other'].map((g) {
                    final selected = _gender == g;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _gender = selected ? '' : g);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.cyan.withValues(alpha: 0.10)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ErrorBox(message: _error),
                const SizedBox(height: 8),
                ValueListenableBuilder(
                  valueListenable: _nameCtrl,
                  builder: (_, val, __) => CyanButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward,
                    loading: _loading,
                    onPressed: val.text.trim().isNotEmpty
                        ? _saveProfile : null,
                  ),
                ),
              ],

              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                      color: AppColors.gray400, fontSize: 11),
                  children: [
                    const TextSpan(text: 'By proceeding, I accept the '),
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () => context.push('/terms'),
                        child: Text('Terms of use',
                            style: TextStyle(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.w600,
                                fontSize: 11)),
                      ),
                    ),
                    const TextSpan(text: ' & Privacy policy'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _nameField() => Container(
    decoration: BoxDecoration(
      color: AppColors.cyanBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cyanLight, width: 2),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      const Text('👤', style: TextStyle(fontSize: 18)),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w700,
              fontSize: 15, color: const Color(0xFF0F172A)),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Your full name',
            hintStyle: TextStyle(
                color: AppColors.cyanLight,
                fontWeight: FontWeight.w700),
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: _nameCtrl,
        builder: (_, val, __) => val.text.isNotEmpty
            ? GestureDetector(
                onTap: () => _nameCtrl.clear(),
                child: Icon(Icons.cancel_rounded,
                    size: 18, color: AppColors.cyanLight))
            : const SizedBox.shrink(),
      ),
    ]),
  );
}

// ── Auto-scrolling cards ─────────────────────────────────────────
class _ScrollingCards extends StatefulWidget {
  @override
  State<_ScrollingCards> createState() => _ScrollingCardsState();
}

class _ScrollingCardsState extends State<_ScrollingCards>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late ScrollController    _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _ctrl   = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _ctrl.addListener(() {
      if (!_scroll.hasClients) return;
      final maxScroll = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(_ctrl.value * maxScroll / 2);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doubled = [..._cleaningCards, ..._cleaningCards];
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: doubled.map((card) {
          return Container(
            width: 160,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Color(card['color'] as int),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(children: [
              Center(child: Text(card['emoji'] as String,
                  style: const TextStyle(fontSize: 64))),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24)),
                  ),
                  child: Text(card['label'] as String,
                      style: GoogleFonts.nunito(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}