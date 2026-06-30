import 'dart:async';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'service_detail_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with TickerProviderStateMixin {
  final _supabase   = Supabase.instance.client;
  final _scrollCtrl = ScrollController();

  // ── Hero animation controllers ─────────────────────────────────
  late AnimationController _ringCtrl;   // pulsing rings
  late AnimationController _orbCtrl;    // floating orbs
  late AnimationController _sweepCtrl;  // shimmer sweep
  late AnimationController _bobCtrl;    // emoji bob
  late AnimationController _orbitCtrl;  // orbit spin
  late AnimationController _sparkCtrl;  // sparkle twinkle

  // ── Entrance controllers ───────────────────────────────────────
  late AnimationController _headerCtrl;
  late AnimationController _greetCtrl;
  late AnimationController _pillsCtrl;
  late AnimationController _gridCtrl;

  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _greetFade;
  late Animation<Offset> _greetSlide;
  late Animation<double> _pillsFade;
  late Animation<Offset> _pillsSlide;

  final List<Animation<double>> _cardFades  = [];
  final List<Animation<double>> _cardScales = [];

  // ── Tokens ─────────────────────────────────────────────────────
  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _navy   = Color(0xFF0C4A6E);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE8EDF2);
  static const _bg     = Color(0xFFF8FAFC);

  static const _cardEmojis = [
    '🚿','🍳','🗄️','💨','🌿','🧹',
    '🧺','🍽️','👔','❄️','🏠','🎉','🧽',
  ];
  static const _cardGrads = [
    [Color(0xFFECFEFF), Color(0xFFCFFAFE)],
    [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
    [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
    [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
    [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
    [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
    [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
    [Color(0xFFECFEFF), Color(0xFFCFFAFE)],
  ];
  static const _cardAccents = [
    Color(0xFF0891B2), Color(0xFF059669), Color(0xFF7C3AED),
    Color(0xFFD97706), Color(0xFFDC2626), Color(0xFF0D9488),
    Color(0xFF16A34A), Color(0xFFEA580C),
  ];

  List<Map<String, dynamic>> _services   = [];
  List<String>               _categories = ['All'];
  String _activeTab = 'All';
  bool   _loading   = true;
  String _userName  = 'there';
  String _userArea  = 'Mumbai';
  String _userCity  = '';

  @override
  void initState() {
    super.initState();
    _initHeroAnimations();
    _initEntranceAnimations();
    _load();
  }

  void _initHeroAnimations() {
    // Pulsing rings — slow in/out
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);

    // Floating orbs — bob up/down
    _orbCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);

    // Shimmer sweep
    _sweepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3600))
      ..repeat();

    // Emoji bob
    _bobCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);

    // Orbit spin
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 6000))
      ..repeat();

    // Sparkle twinkle
    _sparkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
  }

  void _initEntranceAnimations() {
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade  = CurvedAnimation(
        parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
        begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _headerCtrl, curve: Curves.easeOut));

    _greetCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _greetFade  = CurvedAnimation(
        parent: _greetCtrl, curve: Curves.easeOut);
    _greetSlide = Tween<Offset>(
        begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _greetCtrl, curve: Curves.easeOut));

    _pillsCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _pillsFade  = CurvedAnimation(
        parent: _pillsCtrl, curve: Curves.easeOut);
    _pillsSlide = Tween<Offset>(
        begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _pillsCtrl, curve: Curves.easeOut));

    _gridCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
  }

  void _buildCardAnimations(int count) {
    _cardFades.clear();
    _cardScales.clear();
    for (int i = 0; i < count; i++) {
      final start = (i * 90) / 1400.0;
      final end   = (start + 0.4).clamp(0.0, 1.0);
      final curve = Interval(start, end, curve: Curves.easeOutBack);
      _cardFades.add(Tween<double>(begin: 0.0, end: 1.0)
          .animate(CurvedAnimation(parent: _gridCtrl, curve: curve)));
      _cardScales.add(Tween<double>(begin: 0.88, end: 1.0)
          .animate(CurvedAnimation(parent: _gridCtrl, curve: curve)));
    }
  }

  Future<void> _runEntrance() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _headerCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 150));
    _greetCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 180));
    _pillsCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    _gridCtrl.forward();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _orbCtrl.dispose();
    _sweepCtrl.dispose();
    _bobCtrl.dispose();
    _orbitCtrl.dispose();
    _sparkCtrl.dispose();
    _headerCtrl.dispose();
    _greetCtrl.dispose();
    _pillsCtrl.dispose();
    _gridCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = await SupabaseService.loadCachedUserId() ??
        _supabase.auth.currentUser?.id;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    try {
      final results = await Future.wait([
        _supabase.from('users').select('full_name')
            .eq('id', userId).maybeSingle(),
        _supabase.from('addresses').select('area,city')
            .eq('user_id', userId).limit(1).maybeSingle(),
        _supabase.from('services').select('*')
            .eq('is_active', true).order('category'),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>?;
      final addr    = results[1] as Map<String, dynamic>?;
      final svcs    = results[2] as List<dynamic>;
      setState(() {
        if (profile != null) {
          _userName = (profile['full_name'] as String?)
              ?.split(' ').first ?? 'there';
        }
        if (addr != null) {
          _userArea = addr['area'] as String? ?? 'Mumbai';
          _userCity = addr['city'] as String? ?? '';
        }
        _services = svcs.cast<Map<String, dynamic>>();
        final cats = _services
            .map((s) => s['category'] as String? ?? '')
            .where((c) => c.isNotEmpty).toSet().toList()..sort();
        _categories = ['All', ...cats];
        _loading    = false;
      });
      _buildCardAnimations(_services.length);
      _runEntrance();
    } catch (e, st) {
      debugPrint('SERVICES LOAD ERROR: $e');
      debugPrint('Stack: $st');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered => _services
      .where((s) => _activeTab == 'All' || s['category'] == _activeTab)
      .toList();

  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    debugPrint('ServicesScreen.build() called. _loading=$_loading services=${_services.length}');
    final topPad  = MediaQuery.of(context).padding.top;
    final botPad  = MediaQuery.of(context).padding.bottom;
    final screenW = MediaQuery.of(context).size.width;
    final cardW   = (screenW - 36 - 12) / 2;
    final cardH   = cardW * 1.36;

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(
            color: _cyan, strokeWidth: 2.5)));
    }

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(),
        slivers: [

          // ── Animated hero ──────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _headerFade,
              child: SlideTransition(
                position: _headerSlide,
                child: _buildHero(topPad),
              ),
            ),
          ),

          // ── Promo strip ────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _greetFade,
              child: SlideTransition(
                position: _greetSlide,
                child: _buildPromoStrip(),
              ),
            ),
          ),


          // ── Section label ──────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pillsFade,
              child: SlideTransition(
                position: _pillsSlide,
                child: _buildSectionLabel(),
              ),
            ),
          ),

          // ── Category pills ─────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pillsFade,
              child: SlideTransition(
                position: _pillsSlide,
                child: _buildCategoryPills(),
              ),
            ),
          ),

          // ── Grid ───────────────────────────────────────────────
          _buildGrid(cardW, cardH),

          // ── Why us ─────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildWhyUs()),

          SliverToBoxAdapter(
              child: SizedBox(height: botPad + 100)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ANIMATED HERO
  // ═══════════════════════════════════════════════════════════════
  Widget _buildHero(double topPad) {
    final h        = DateTime.now().hour;
    final greeting = h < 12 ? 'Good morning'
        : h < 17 ? 'Good afternoon' : 'Good evening';
    final location = _userCity.isNotEmpty
        ? '$_userArea, $_userCity' : _userArea;

    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: 420,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0C4A6E),
              Color(0xFF075985),
              Color(0xFF0891B2),
              Color(0xFF06B6D4),
            ],
            stops: [0.0, 0.3, 0.65, 1.0],
          ),
        ),
        child: Stack(children: [

          // ── Layer 1: Shimmer sweep ────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _sweepCtrl,
              builder: (_, __) => Transform.translate(
                offset: Offset(
                    (_sweepCtrl.value * 2 - 0.5) *
                        MediaQuery.of(context).size.width * 1.5,
                    0),
                child: Container(
                  width: 120,
                  height: 420,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 2: Pulsing rings top-right ──────────────────
          Positioned(
            top: -50, right: -50,
            width: 240, height: 240,
            child: AnimatedBuilder(
              animation: _ringCtrl,
              builder: (_, __) {
                final v = _ringCtrl.value;
                return Stack(alignment: Alignment.center, children: [
                  _ring(220, v, 0.0),
                  _ring(160, v, 0.3),
                  _ring(100, v, 0.6),
                ]);
              },
            ),
          ),

          // ── Layer 3: Floating orbs bottom-left ────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbCtrl,
              builder: (_, __) {
                final dy = _orbCtrl.value * -12.0;
                return Stack(children: [
                  Positioned(
                    bottom: 55 + dy, left: -18,
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle)),
                  ),
                  Positioned(
                    bottom: 92 + dy * 0.6, left: 42,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle)),
                  ),
                ]);
              },
            ),
          ),

          // ── Layer 4: Sparkle dots ─────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _sparkCtrl,
              builder: (_, __) {
                return Stack(children: [
                  _spark(topPad + 36, null, null, 80,  0.5),
                  _spark(topPad + 76, null, null, 150, 0.35),
                  _spark(topPad + 55, null, 115, null, 0.30),
                  _spark(topPad + 105, null, 84, null, 0.40),
                ]);
              },
            ),
          ),

          // ── Layer 5: Bobbing emoji + orbits ───────────────────
          Positioned(right: 18, top: topPad + 44,
            child: SizedBox(
              width: 90, height: 160,
              child: Stack(alignment: Alignment.center, children: [
                // Orbiting ✨
                AnimatedBuilder(
                  animation: _orbitCtrl,
                  builder: (_, __) => Transform.rotate(
                    angle: _orbitCtrl.value * 2 * math.pi,
                    child: Stack(children: [
                      Positioned(top: 0, left: 38,
                        child: Transform.rotate(
                          angle: -_orbitCtrl.value * 2 * math.pi,
                          child: const Text('✨',
                              style: TextStyle(fontSize: 16)))),
                    ]),
                  ),
                ),
                // Orbiting 🧹 (reverse)
                AnimatedBuilder(
                  animation: _orbitCtrl,
                  builder: (_, __) => Transform.rotate(
                    angle: -_orbitCtrl.value * 2 * math.pi,
                    child: Stack(children: [
                      Positioned(bottom: 0, left: 30,
                        child: Transform.rotate(
                          angle: _orbitCtrl.value * 2 * math.pi,
                          child: const Text('🧹',
                              style: TextStyle(fontSize: 16)))),
                    ]),
                  ),
                ),
                // Bobbing main emoji
                AnimatedBuilder(
                  animation: _bobCtrl,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, _bobCtrl.value * -10),
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 1.5)),
                      child: const Center(
                          child: Text('🏠',
                              style: TextStyle(fontSize: 40)))),
                  ),
                ),
              ]),
            )),

          // ── Content ───────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                18, topPad + 12, 18, 48),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              // Top row: location + notif + avatar
              Row(children: [
                GestureDetector(
                  onTap: () => context.go('/account'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25))),
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: [
                      const Icon(Icons.location_on_rounded,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 130),
                        child: Text(location,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1)),
                      const SizedBox(width: 2),
                      Icon(Icons.expand_more_rounded,
                          color: Colors.white.withValues(alpha: 0.65),
                          size: 15),
                    ]),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22))),
                  child: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.white, size: 17)),
                const SizedBox(width: 9),
                GestureDetector(
                  onTap: () => context.go('/account'),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 1.5)),
                    child: Center(child: Text(
                      _userName.isNotEmpty
                          ? _userName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14))))),
              ]),

              const SizedBox(height: 24),

              // Greeting
              Text(greeting,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              RichText(text: TextSpan(children: [
                TextSpan(
                  text: '$_userName ',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.1)),
                const TextSpan(
                    text: '👋',
                    style: TextStyle(fontSize: 24)),
              ])),
              const SizedBox(height: 5),
              Text('What needs cleaning today?',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),

              const SizedBox(height: 20),

              // Quick chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(children: [
                  _heroChip(Icons.water_drop_outlined, 'Bathroom'),
                  _heroChip(Icons.soup_kitchen_outlined, 'Kitchen'),
                  _heroChip(Icons.home_outlined, 'Full House'),
                  _heroChip(Icons.celebration_outlined, 'Party'),
                  _heroChip(Icons.air_outlined, 'Fan'),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ring(double size, double v, double delay) {
    final opacity = ((math.sin((v + delay) * math.pi)).abs() * 0.6)
        .clamp(0.05, 0.60);
    final scale   = 1.0 + v * 0.06;
    return Container(
      width: size * scale,
      height: size * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white.withValues(alpha: opacity),
            width: 1.0)),
    );
  }

  Widget _spark(double top, double? bottom, double? left,
      double? right, double base) {
    final opacity = base + _sparkCtrl.value * 0.4;
    final pos = <Widget>[];
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 4, height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          shape: BoxShape.circle)));
  }

  Widget _heroChip(IconData icon, String label) {
    return GestureDetector(
      onTap: () {
        setState(() => _activeTab = 'All');
        HapticFeedback.selectionClick();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PROMO STRIP
  // ═══════════════════════════════════════════════════════════════
  Widget _buildPromoStrip() {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(const ClipboardData(text: 'CLEAN20'));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('🎉 CLEAN20 copied!'),
          backgroundColor: _cyanDk,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          duration: const Duration(seconds: 2)));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        height: 84,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C4A6E), Color(0xFF0891B2)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
              color: _cyanDk.withValues(alpha: 0.28),
              blurRadius: 16, offset: const Offset(0, 6))]),
        child: Stack(children: [
          Positioned(right: 55, top: -16,
            child: Container(width: 60, height: 60,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle))),
          Positioned(right: -4, bottom: -6,
            child: Text('🧴', style: TextStyle(
                fontSize: 68,
                color: Colors.white.withValues(alpha: 0.88)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 90, 0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5)),
                child: const Text('LIMITED OFFER',
                    style: TextStyle(color: Colors.white,
                        fontSize: 7.5, fontWeight: FontWeight.w900,
                        letterSpacing: 1.3))),
              const SizedBox(height: 5),
              const Text('Flat 20% OFF',
                  style: TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('Use CLEAN20 at checkout',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }



  // ═══════════════════════════════════════════════════════════════
  // SECTION LABEL
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('Our Services',
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w900, color: _ink)),
          Text('${_filtered.length} available',
              style: const TextStyle(fontSize: 11,
                  color: _cyan, fontWeight: FontWeight.w600)),
        ]),
        Row(children: [
          Container(width: 7, height: 7,
            decoration: const BoxDecoration(
                color: Color(0xFF10B981), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          const Text('All pros verified',
              style: TextStyle(color: Color(0xFF059669),
                  fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CATEGORY PILLS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCategoryPills() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: _categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat    = _categories[i];
            final active = cat == _activeTab;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _activeTab = cat;
                  _buildCardAnimations(_filtered.length);
                  _gridCtrl.forward(from: 0);
                });
                HapticFeedback.selectionClick();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _cyan : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: active ? _cyan : _border,
                      width: active ? 0 : 1.5),
                  boxShadow: active
                      ? [BoxShadow(
                          color: _cyan.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3))]
                      : []),
                child: Text(cat,
                    style: TextStyle(
                        color: active ? Colors.white : _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // GRID
  // ═══════════════════════════════════════════════════════════════
  Widget _buildGrid(double cardW, double cardH) {
    final svcs = _filtered;

    if (svcs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                  border: Border.all(color: _border)),
              child: const Center(child: Text('🔍',
                  style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 16),
            const Text('No services found',
                style: TextStyle(color: _ink, fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Try a different category',
                style: TextStyle(color: _faint, fontSize: 13)),
          ]),
        ),
      );
    }

    if (_cardFades.length < svcs.length) {
      _buildCardAnimations(svcs.length);
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   2,
          crossAxisSpacing: 12,
          mainAxisSpacing:  12,
          childAspectRatio: cardW / cardH,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final fade  = i < _cardFades.length
                ? _cardFades[i]
                : const AlwaysStoppedAnimation(1.0);
            final scale = i < _cardScales.length
                ? _cardScales[i]
                : const AlwaysStoppedAnimation(1.0);
            return AnimatedBuilder(
              animation: _gridCtrl,
              builder: (_, child) => FadeTransition(
                opacity: fade,
                child: ScaleTransition(scale: scale, child: child)),
              child: _buildCard(svcs[i], i, cardW, cardH),
            );
          },
          childCount: svcs.length,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SERVICE CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCard(Map<String, dynamic> svc, int i,
      double cardW, double cardH) {
    final grads  = _cardGrads[i % _cardGrads.length];
    final accent = _cardAccents[i % _cardAccents.length];
    final emoji  = _cardEmojis[i % _cardEmojis.length];
    final price  = (svc['base_price'] as num).toInt();
    final dur    = (svc['duration_minutes'] as num).toInt();
    final imgH   = cardH * 0.50;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => ServiceDetailScreen(
                serviceId: svc['id'] as String)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

          // Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20)),
            child: Container(
              height: imgH,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: grads)),
              child: Stack(children: [
                Positioned(right: -10, bottom: -10,
                  child: Text(emoji, style: TextStyle(
                      fontSize: 72,
                      color: accent.withValues(alpha: 0.12)))),
                Center(child: Text(emoji,
                    style: const TextStyle(fontSize: 44))),
                Positioned(top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: [
                      Icon(Icons.schedule_rounded,
                          size: 9, color: accent),
                      const SizedBox(width: 3),
                      Text('${dur}m', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w800,
                          color: accent)),
                    ]))),
              ]),
            )),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Text(svc['name'] as String,
                    style: const TextStyle(fontSize: 12.5,
                        fontWeight: FontWeight.w800, color: _ink,
                        height: 1.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                  Column(crossAxisAlignment:
                      CrossAxisAlignment.start, children: [
                    Text('₹$price', style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900,
                        color: _ink, height: 1.1)),
                    const Text('per visit', style: TextStyle(
                        fontSize: 9, color: _faint,
                        fontWeight: FontWeight.w500)),
                  ]),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: accent, size: 15)),
                ]),
              ]),
            )),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WHY US
  // ═══════════════════════════════════════════════════════════════
  Widget _buildWhyUs() {
    const items = [
      {'e': '🛡️', 't': 'Fully Insured',    's': 'All damage covered',
        'c': Color(0xFFF5F3FF)},
      {'e': '⚡',  't': 'Always On Time',   's': 'Or your money back',
        'c': Color(0xFFFFFBEB)},
      {'e': '🌿', 't': 'Eco Products',      's': 'Safe for kids & pets',
        'c': Color(0xFFECFDF5)},
      {'e': '🔄', 't': 'Free Re-Clean',     's': 'If not satisfied',
        'c': Color(0xFFECFEFF)},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        const Text('Why Cleenzo?',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 4),
        const Text("Mumbai's most trusted home cleaning",
            style: TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Expanded(child: Column(children: [
            _whyCard(items[0]),
            const SizedBox(height: 12),
            _whyCard(items[2]),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(children: [
            _whyCard(items[1]),
            const SizedBox(height: 12),
            _whyCard(items[3]),
          ])),
        ]),
      ]),
    );
  }

  Widget _whyCard(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item['c'] as Color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: (item['c'] as Color).withValues(alpha: 0.6))),
      child: Row(children: [
        Text(item['e'] as String,
            style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(item['t'] as String, style: const TextStyle(
              color: _ink, fontSize: 11,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(item['s'] as String, style: const TextStyle(
              color: _muted, fontSize: 10)),
        ])),
      ]),
    );
  }
}

// ── Wave clipper ─────────────────────────────────────────────────
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 32);
    path.quadraticBezierTo(
        size.width * 0.25, size.height,
        size.width * 0.5,  size.height - 16);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 32,
        size.width,        size.height - 8);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}