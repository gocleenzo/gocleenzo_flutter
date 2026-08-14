import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
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
  // Set only when the edge function tells us this "new user" signup is
  // actually a REACTIVATION of a previously soft-deleted account (same
  // phone, same role) — see firebase-auth's is_deleted branch. When
  // set, _saveProfile() must UPDATE this existing row instead of
  // INSERT-ing a new one, since a row (with this exact id) already
  // exists and would violate the users_phone_role_unique constraint on
  // insert. Keeping the same id is deliberate — it's what preserves
  // this customer's real booking history (and therefore
  // _isFirstBooking) across a delete-then-resignup cycle.
  String? _reactivatedUserId;
  // Guards against a race between Firebase's automatic SMS auto-retrieval
  // (verificationCompleted) and Android's own Autofill Framework filling
  // the on-screen OTP boxes from the same incoming SMS — both can fire
  // within milliseconds of each other and each independently calls
  // _signInWithCredential(). A phone-auth verification session can only
  // be consumed once; whichever attempt reaches Firebase first succeeds,
  // and the second one comes back with "session expired" even though
  // nothing actually expired — it's just Firebase's generic error for a
  // verification ID that's already been used. This flag makes sure only
  // the FIRST attempt is ever sent to Firebase; the second is silently
  // dropped instead of surfacing a confusing, false error to the user.
  bool    _signingIn      = false;

  // ── Resend handling ──────────────────────────────────────────
  // Firebase's own token for linking a genuine resend to the SAME
  // verification attempt (via forceResendingToken). Without passing this
  // back on resend, Firebase can treat a rapid re-request as a near-
  // duplicate and not actually issue a fresh SMS/session — which is what
  // was causing "type the OTP once it finally arrives -> session has
  // expired" even right after tapping Resend.
  int? _resendToken;
  // 30s cooldown before Resend is tappable again — standard OTP UX,
  // and it also stops the user (or a mis-tap) from firing multiple
  // concurrent verification requests before the first one even has a
  // chance to deliver.
  static const _resendCooldownSeconds = 30;
  int _resendSecondsLeft = 0;
  Timer? _resendCooldownTimer;
  // Bumped on every resend to force OtpInputRow to remount with a fresh
  // ValueKey — clears any stale digits left over from an expired code
  // instead of leaving them sitting in the box looking "entered".
  int _otpFieldGeneration = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _resendCooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendCooldownTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldownSeconds);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendSecondsLeft -= 1;
        if (_resendSecondsLeft <= 0) t.cancel();
      });
    });
  }

  /// True for transient connectivity failures (dropped signal, DNS
  /// hiccup, request timeout) — the kind of error a brief retry can
  /// often ride straight through — as opposed to a genuine auth failure
  /// (wrong code, expired session) that retrying would never fix.
  bool _isNetworkError(Object e) {
    if (e is fb.FirebaseAuthException) return e.code == 'network-request-failed';
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('network') ||
        s.contains('timeout') ||
        s.contains('failed host lookup') ||
        s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('clientexception');
  }

  /// Runs [action] with a [timeout], silently retrying up to [maxRetries]
  /// more times (1s, then 2s backoff) ONLY when the failure looks like a
  /// transient network issue per [_isNetworkError] — a genuine auth error
  /// (wrong OTP, expired session) is rethrown immediately on the first
  /// attempt without wasting time retrying something a retry can never
  /// fix. This is what makes mobile-data sign-ins resilient to the kind
  /// of brief signal drop / tower handoff that WiFi doesn't experience,
  /// without ever masking a real error.
  ///
  /// [timeout] should be generous for anything that can have a genuine
  /// cold start (e.g. a Supabase Edge Function) — too short a timeout
  /// here makes NORMAL slowness look identical to a dropped connection,
  /// which is what happened when this was a flat 20s for every call.
  Future<T> _withNetworkRetry<T>(
    Future<T> Function() action, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await action().timeout(timeout);
      } catch (e) {
        attempt++;
        if (attempt > maxRetries || !_isNetworkError(e)) rethrow;
        debugPrint('Network retry $attempt/$maxRetries after: $e');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
  }

  // ── STEP 1: Send OTP via Firebase ────────────────────────────
  // [isResend] passes Firebase's forceResendingToken (captured from the
  // previous codeSent callback) so a genuine resend is properly linked to
  // this verification attempt instead of silently no-op'ing.
  Future<void> _sendOtp({bool isResend = false}) async {
    if (_phoneCtrl.text.length < 10) return;
    setState(() {
      _loading = true;
      _error = '';
      if (isResend) {
        _otp = '';
        _otpFieldGeneration++; // forces OtpInputRow to remount empty
      }
    });

    try {
      await _fireAuth.verifyPhoneNumber(
        phoneNumber: '+91${_phoneCtrl.text}',
        // Widened from 60s -> 120s. This only controls how long Firebase
        // waits before firing codeAutoRetrievalTimeout (falling back to
        // manual entry) — a longer window gives slow SMS delivery more
        // of a chance to auto-fill before the user is forced to type it
        // manually, without changing the actual server-side session
        // validity window.
        timeout: const Duration(seconds: 120),
        forceResendingToken: isResend ? _resendToken : null,
        verificationCompleted: (fb.PhoneAuthCredential credential) async {
          debugPrint('Auto-verification completed');
          await _signInWithCredential(credential);
        },
        verificationFailed: (fb.FirebaseAuthException e) {
          debugPrint('Verification failed: ${e.code} - ${e.message}');
          if (mounted) {
            setState(() {
              _error   = _friendlyAuthError(e);
              _loading = false;
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('OTP sent. verificationId set. resendToken=$resendToken');
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _resendToken    = resendToken;
              _step           = 'otp';
              _loading        = false;
            });
          }
          _startResendCooldown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('Auto retrieval timeout');
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Send OTP error: $e');
      if (mounted) {
        setState(() {
          _error   = 'Failed to send OTP. Please try again.';
          _loading = false;
        });
      }
    }
  }

  /// Turns Firebase's raw auth error into a clear, actionable message
  /// instead of showing its internal wording verbatim (which is exactly
  /// how "The SMS code has expired. Please re-send the verification code
  /// to try again." was reaching the user as-is — technically accurate,
  /// but not actionable on its own inside this screen's flow).
  String _friendlyAuthError(fb.FirebaseAuthException e) {
    final msg = (e.message ?? '').toLowerCase();
    if (e.code == 'session-expired' || msg.contains('expired')) {
      return 'That code expired before it arrived. Tap "Resend OTP" below '
          'for a fresh one.';
    }
    if (e.code == 'invalid-verification-code') {
      return 'Incorrect OTP. Please check the code and try again.';
    }
    if (e.code == 'too-many-requests') {
      return 'Too many attempts. Please wait a few minutes before trying '
          'again.';
    }
    return e.message ?? 'Failed to send OTP. Try again.';
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
      if (mounted) {
        final expired = e.code == 'session-expired' ||
            (e.message ?? '').toLowerCase().contains('expired');
        setState(() {
          _error   = _friendlyAuthError(e);
          _loading = false;
          // An expired session's verificationId can never succeed no
          // matter how many times it's retried — clear it and the typed
          // code so the ONLY path forward the UI offers is a real resend,
          // rather than letting the user keep retrying the same dead code.
          if (expired) {
            _verificationId = null;
            _otp = '';
            _otpFieldGeneration++;
          }
        });
      }
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      if (mounted) {
        setState(() {
          _error   = 'Something went wrong. Please try again.';
          _loading = false;
        });
      }
    }
  }

  /// Actively waits for `fb.FirebaseAuth.instance.currentUser` to become
  /// non-null, instead of hoping a fixed delay was long enough. The
  /// router's redirect logic gates every route on this value, so
  /// navigating before it's actually set sends the user straight back to
  /// /login — which is exactly the "OTP verified but bounced to login"
  /// symptom this replaces a fragile `Future.delayed(300ms)` guess with.
  /// Polls quickly (50ms) and gives up after 5s so a genuine failure
  /// still surfaces instead of hanging forever.
  Future<bool> _waitForFirebaseAuthState({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (fb.FirebaseAuth.instance.currentUser != null) return true;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return fb.FirebaseAuth.instance.currentUser != null;
  }

  // ── Sign in with Firebase → call Edge Function ────────────────
  Future<void> _signInWithCredential(
      fb.PhoneAuthCredential credential) async {
    // If a sign-in is already in flight (from the other of the two
    // possible triggers — auto-verify or manual OTP entry — racing this
    // one), drop this duplicate attempt entirely rather than sending it
    // to Firebase, where it would fail with a confusing "session expired"
    // error even though the first attempt is about to succeed normally.
    if (_signingIn) {
      debugPrint('Sign-in already in progress — ignoring duplicate '
          'credential (auto-verify vs manual OTP race)');
      return;
    }
    _signingIn = true;

    // ── Phase 1: Firebase auth + edge function. If either fails,
    // the user genuinely isn't signed in — show "Sign in failed".
    fb.User? fireUser;
    Map<String, dynamic> data;
    try {
      debugPrint('Signing in with credential...');
      // Retries automatically on a dropped/flaky connection (common on
      // mobile data, rare on WiFi) — a genuine wrong/expired code is
      // NOT retried, it fails immediately below in the catch block.
      final userCred = await _withNetworkRetry(
          () => _fireAuth.signInWithCredential(credential));
      fireUser = userCred.user;
      if (fireUser == null) throw Exception('Firebase user is null');
      debugPrint('Firebase signed in: ${fireUser.uid}');

      final phone = '+91${_phoneCtrl.text}';

      debugPrint('Calling edge function...');
      // Firebase credential is already consumed/valid at this point, so
      // only THIS call is retried if it's the one that hits a network
      // blip — no need to redo the Firebase step or ask for a new OTP.
      //
      // 45s (not the default 20s) — this call can have a genuine cold
      // start (Supabase Edge Functions spin up on demand) plus a DB
      // lookup/insert, and 20s was cutting off calls that were simply
      // slow, not actually disconnected — which is what made "Network
      // issue" appear even on a good WiFi connection.
      final res = await _withNetworkRetry(
        () => _supabase.functions.invoke(
          'firebase-auth',
          body: {
            'firebase_uid': fireUser!.uid,
            'phone':        phone,
            // REQUIRED — this is what keeps this app's users separate
            // from the worker app's users for the same phone number.
            // The edge function now looks up (and creates) rows scoped
            // to (phone, role), backed by the users_phone_role_unique
            // DB constraint. Without this, the edge function returns a
            // 400 error ("role is required").
            'role':         'customer',
          },
        ),
        timeout: const Duration(seconds: 45),
      );

      debugPrint('Edge function status: ${res.status}');
      data = res.data as Map<String, dynamic>;
      debugPrint('Edge function response: $data');
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('Firebase sign in error: ${e.code} - ${e.message}');
      _signingIn = false;
      if (mounted) {
        final expired = e.code == 'session-expired' ||
            (e.message ?? '').toLowerCase().contains('expired');
        setState(() {
          _error   = _friendlyAuthError(e);
          _loading = false;
          if (expired) {
            _verificationId = null;
            _otp = '';
            _otpFieldGeneration++;
          }
        });
      }
      return;
    } on FunctionException catch (e) {
      debugPrint('Edge function error: ${e.status} - ${e.details}');
      _signingIn = false;
      if (mounted) {
        setState(() {
          _error   = 'Could not verify your account. Please try again.';
          _loading = false;
        });
      }
      return;
    } catch (e) {
      debugPrint('Sign in error: $e');
      _signingIn = false;
      if (mounted) {
        // Network failures get a specific, actionable message and —
        // deliberately — the typed OTP and verificationId are LEFT
        // INTACT (not cleared like the expired-session case above),
        // since the code itself was correct; only the connection/server
        // was slow. The customer can just tap "Verify & Continue" again
        // — often the retry alone succeeds once a cold start has warmed
        // up, with no fresh OTP needed.
        setState(() {
          if (e is TimeoutException) {
            _error = 'That took longer than expected. Please tap '
                'Verify again.';
          } else if (_isNetworkError(e)) {
            _error = 'Network issue — please check your connection and '
                'tap Verify again.';
          } else {
            _error = 'Sign in failed. Please try again.';
          }
          _loading = false;
        });
      }
      return;
    }

    if (!mounted) return;

    if (data['is_new_user'] == true) {
      debugPrint('New user — going to profile step');
      _reactivatedUserId = data['reactivated_user_id'] as String?;
      if (_reactivatedUserId != null) {
        debugPrint('This is a REACTIVATION of id: $_reactivatedUserId');
      }
      _signingIn = false;
      setState(() { _step = 'profile'; _loading = false; });
      return;
    }

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

    // Actively confirm Firebase's local auth state has actually
    // propagated (router.dart's redirect gates on
    // fb.FirebaseAuth.instance.currentUser) instead of guessing with a
    // fixed delay. This is the fix for OTP-verifies-then-bounces-to-login.
    debugPrint('Waiting for Firebase auth state to propagate...');
    final authReady = await _waitForFirebaseAuthState();
    debugPrint('Firebase auth state ready: $authReady '
        '(currentUser=${fb.FirebaseAuth.instance.currentUser?.uid})');

    if (!authReady) {
      debugPrint('Firebase auth state never propagated — aborting navigation');
      _signingIn = false;
      if (mounted) {
        setState(() => _error =
            'Signed in, but the app took too long to confirm it. '
            'Please try again.');
      }
      return;
    }

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

      final Map<String, dynamic> data;
      if (_reactivatedUserId != null) {
        // Reactivation — UPDATE the existing (soft-deleted, now
        // un-deleted) row instead of inserting a new one. Same id,
        // same booking history, just fresh name/gender.
        data = await _supabase.from('users').update({
          'full_name': _nameCtrl.text.trim(),
          'gender':    _gender.isEmpty ? null : _gender,
        }).eq('id', _reactivatedUserId!).select().single();
      } else {
        data = await _supabase.from('users').insert({
          'full_name': _nameCtrl.text.trim(),
          'phone':     phone,
          'role':      'customer',
          'gender':    _gender.isEmpty ? null : _gender,
        }).select().single();
      }

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

      // Same fix as the existing-user path — confirm auth state before
      // navigating, instead of hoping.
      await _waitForFirebaseAuthState();

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

    final baseHeroH = (h * 0.48).clamp(300.0, 480.0);
    final heroH     = kbOpen ? baseHeroH * 0.62 : baseHeroH;
    final rowsArea  = heroH - topPad - 24 - 14 - 12;
    final cardH     = (rowsArea / 2).clamp(96.0, 220.0);
    final cardW     = cardH * 0.86;

    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Column(children: [

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

  Widget _buildStep() {
    if (_step == 'otp') return _otpStep();
    return _phoneStep();
  }

  Widget _phoneStep() {
    return Column(children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('MOBILE NUMBER',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                color: Color.fromARGB(255, 0, 0, 0), letterSpacing: 1.5)),
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
          onPressed: val.text.length == 10 ? () => _sendOtp() : null,
        ),
      ),
    ]);
  }

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

  Widget _otpStep() {
    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => setState(
              () { _step = 'phone'; _error = ''; _verificationId = null; }),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back_ios, size: 16, color: AppColors.cyan),
            Text('Back', style: TextStyle(
                color: AppColors.cyan, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Enter the 6-digit code sent to',
          style: TextStyle(color: AppColors.gray500, fontSize: 13)),
      const SizedBox(height: 4),
      Text('+91 ${_phoneCtrl.text}',
          style: GoogleFonts.spaceGrotesk(color: AppColors.cyan,
              fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 1.5)),
      const SizedBox(height: 6),
      const SizedBox(height: 16),
      OtpInputRow(
        // Remounts with a clean slate whenever we resend or hit an
        // expired-session error, so no stale digits from a dead code
        // linger visually in the boxes.
        key: ValueKey(_otpFieldGeneration),
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
      // Resend — disabled during the cooldown window with a visible
      // countdown, and properly passes forceResendingToken via
      // _sendOtp(isResend: true) so Firebase treats it as a genuine
      // resend of THIS attempt rather than a fresh, possibly-ignored
      // duplicate request.
      TextButton(
        onPressed: (_loading || _resendSecondsLeft > 0)
            ? null
            : () => _sendOtp(isResend: true),
        child: Text(
          _resendSecondsLeft > 0
              ? 'Resend OTP in ${_resendSecondsLeft}s'
              : 'Resend OTP',
          style: TextStyle(
              color: _resendSecondsLeft > 0 ? AppColors.gray400 : AppColors.cyan,
              fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }

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
              GestureDetector(
                onTap: () => setState(() { _step = 'otp'; _error = ''; }),
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: _kCyanBg, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: _kCyanDk, size: 22),
                ),
              ),
              const SizedBox(height: 20),

              const BrandLogo(size: 54),
              const SizedBox(height: 32),

              Text('Welcome to Cleenzo!',
                  style: GoogleFonts.nunito(fontSize: 32,
                      fontWeight: FontWeight.w900, height: 1.15,
                      color: _kInk)),
              const SizedBox(height: 8),
              const Text("Let's set up your profile so we can\npersonalise your cleans.",
                  style: TextStyle(fontSize: 15, height: 1.5,
                      color: _kFaint, fontWeight: FontWeight.w500)),
              const SizedBox(height: 36),

              const Text('YOUR NAME',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                      color: AppColors.gray400, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              _bigNameField(),
              const SizedBox(height: 32),

              const Text('GENDER (OPTIONAL)',
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
                child: const Icon(Icons.cancel_rounded,
                    size: 20, color: AppColors.cyanLight))
            : const SizedBox.shrink(),
      ),
    ]),
  );

  Widget _termsLine() => RichText(
    textAlign: TextAlign.center,
    text: TextSpan(
      style: const TextStyle(color: AppColors.gray400, fontSize: 11),
      children: [
        const TextSpan(text: 'By proceeding, I accept the '),
        WidgetSpan(
          child: GestureDetector(
            onTap: () => _openExternalLink('https://www.gocleenzo.com/terms'),
            child: const Text('Terms of use',
                style: TextStyle(color: AppColors.cyan,
                    fontWeight: FontWeight.w600, fontSize: 11)),
          ),
        ),
        const TextSpan(text: ' & '),
        WidgetSpan(
          child: GestureDetector(
            onTap: () => _openExternalLink('https://www.gocleenzo.com/terms'),
            child: const Text('Privacy policy',
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