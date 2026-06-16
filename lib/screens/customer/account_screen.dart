import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _supabase  = Supabase.instance.client;
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();

  String  _step     = 'phone'; // 'phone' → 'otp' → 'profile'
  String  _otp      = '';
  String  _gender   = '';
  bool    _loading  = false;
  String  _error    = '';
  String? _userId;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── STEP 1 : send OTP ────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.length < 10) return;
    setState(() { _loading = true; _error = ''; });
    try {
      await SupabaseService.sendOtp(_phoneCtrl.text);
      setState(() => _step = 'otp');
    } catch (_) {
      setState(() => _error = 'Failed to send OTP. Please try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── STEP 2 : verify OTP ──────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (_otp.length < 6) return;
    setState(() { _loading = true; _error = ''; });

    AuthResponse res;
    try {
      res = await SupabaseService.verifyOtp(_phoneCtrl.text, _otp);
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Invalid OTP. Please try again.'; _loading = false; });
      return;
    }

    final user = res.user;
    if (user == null) {
      if (!mounted) return;
      setState(() { _error = 'Verification failed. Please try again.'; _loading = false; });
      return;
    }
    _userId = user.id;

    Map<String, dynamic>? profile;
    try {
      profile = await SupabaseService.getUserProfile(user.id);
    } catch (_) {
      profile = null;
    }

    if (!mounted) return;

    final fullName = profile?['full_name'];
    final needsProfile = profile == null ||
        fullName == null ||
        (fullName is String && fullName.trim().isEmpty);

    if (needsProfile) {
      setState(() { _step = 'profile'; _loading = false; });
    } else {
      setState(() => _loading = false);
      await _goToNextScreen(user.id);
    }
  }

  // ── STEP 3 : save profile (new users) ────────────────────────
  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      await SupabaseService.createUser({
        'id':        _userId,
        'full_name': _nameCtrl.text.trim(),
        'phone':     '+91${_phoneCtrl.text}',
        'role':      'customer',
        'gender':    _gender.isEmpty ? null : _gender,
      });
      if (!mounted) return;
      context.go('/location-gate');
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Check address → route accordingly ────────────────────────
  Future<void> _goToNextScreen(String userId) async {
    try {
      final addresses = await _supabase
          .from('addresses')
          .select('id')
          .eq('user_id', userId)
          .limit(1);

      if (!mounted) return;

      if ((addresses as List).isEmpty) {
        context.go('/location-gate');
      } else {
        context.go('/services');
      }
    } catch (_) {
      if (mounted) context.go('/services');
    }
  }

  // ─────────────────────────────────────────────────────────────
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

              if (_step == 'phone') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('MOBILE NUMBER',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                          color: AppColors.gray400, letterSpacing: 1.5)),
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

              if (_step == 'otp') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => setState(() { _step = 'phone'; _error = ''; }),
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
                    style: TextStyle(color: AppColors.cyan,
                        fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 16),
                OtpInputRow(
                  onCompleted: (v) { setState(() => _otp = v); _verifyOtp(); },
                  onChange:    (v) => setState(() => _otp = v),
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
                  onPressed: _sendOtp,
                  child: Text('Resend OTP',
                      style: TextStyle(
                          color: AppColors.cyan, fontWeight: FontWeight.w600)),
                ),
              ],

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
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                          color: AppColors.gray400, letterSpacing: 1.5)),
                ),
                const SizedBox(height: 8),
                _nameField(),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('GENDER (optional)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                          color: AppColors.gray400, letterSpacing: 1.5)),
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
                                ? AppColors.cyan : const Color(0xFFDDE3EB),
                            width: selected ? 2.0 : 1.5,
                          ),
                        ),
                        child: Text(g, style: TextStyle(
                          color: selected ? AppColors.cyan : const Color(0xFF64748B),
                          fontSize: 13, fontWeight: FontWeight.w700,
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
                    onPressed: val.text.trim().isNotEmpty ? _saveProfile : null,
                  ),
                ),
              ],

              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(color: AppColors.gray400, fontSize: 11),
                  children: [
                    const TextSpan(text: 'By proceeding, I accept the '),
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () => context.push('/terms'),
                        child: Text('Terms of use',
                            style: TextStyle(color: AppColors.cyan,
                                fontWeight: FontWeight.w600, fontSize: 11)),
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
                color: AppColors.cyanLight, fontWeight: FontWeight.w700),
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