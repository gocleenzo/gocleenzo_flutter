import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
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
    _setupAnimations();
    _load();
  }

  void _setupAnimations() {
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade  = CurvedAnimation(
        parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
        begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _headerCtrl, curve: Curves.easeOut));

    _greetCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _greetFade  = CurvedAnimation(
        parent: _greetCtrl, curve: Curves.easeOut);
    _greetSlide = Tween<Offset>(
        begin: const Offset(0, 0.25), end: Offset.zero)
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
        vsync: this,
        duration: const Duration(milliseconds: 1400));
  }

  void _buildCardAnimations(int count) {
    _cardFades.clear();
    _cardScales.clear();
    for (int i = 0; i < count; i++) {
      final start = (i * 90) / 1400.0;
      final end   = (start + 0.4).clamp(0.0, 1.0);
      final interval = Interval(start, end, curve: Curves.easeOutBack);
      _cardFades.add(Tween<double>(begin: 0.0, end: 1.0)
          .animate(CurvedAnimation(parent: _gridCtrl, curve: interval)));
      _cardScales.add(Tween<double>(begin: 0.88, end: 1.0)
          .animate(CurvedAnimation(parent: _gridCtrl, curve: interval)));
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
    _headerCtrl.dispose();
    _greetCtrl.dispose();
    _pillsCtrl.dispose();
    _gridCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) { if (mounted) context.go('/login'); return; }
    try {
      final results = await Future.wait([
        _supabase.from('users').select('full_name')
            .eq('id', user.id).maybeSingle(),
        _supabase.from('addresses').select('area,city')
            .eq('user_id', user.id).limit(1).maybeSingle(),
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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered => _services
      .where((s) => _activeTab == 'All' || s['category'] == _activeTab)
      .toList();

  @override
  Widget build(BuildContext context) {
    final topPad  = MediaQuery.of(context).padding.top;
    final botPad  = MediaQuery.of(context).padding.bottom;
    final screenW = MediaQuery.of(context).size.width;
    final cardW   = (screenW - 36 - 12) / 2;
    final cardH   = cardW * 1.35;

    if (_loading) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(
              color: _cyan, strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text('Loading…', style: TextStyle(
              color: _faint, fontSize: 13)),
        ])));
    }

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(),
        slivers: [

          // ── Gradient hero header ─────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _headerFade,
              child: SlideTransition(
                position: _headerSlide,
                child: _buildHeroHeader(topPad),
              ),
            ),
          ),

          // ── Stats strip ──────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _greetFade,
              child: SlideTransition(
                position: _greetSlide,
                child: _buildStatsStrip(),
              ),
            ),
          ),

          // ── Section label + category pills ───────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pillsFade,
              child: SlideTransition(
                position: _pillsSlide,
                child: _buildSectionLabel(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pillsFade,
              child: SlideTransition(
                position: _pillsSlide,
                child: _buildCategoryPills(),
              ),
            ),
          ),

          // ── Service grid ─────────────────────────────────────
          _buildGrid(cardW, cardH),

          // ── Promo banner ─────────────────────────────────────
          SliverToBoxAdapter(child: _buildPromoBanner()),

          // ── Why us ───────────────────────────────────────────
          SliverToBoxAdapter(child: _buildWhyUs()),

          SliverToBoxAdapter(
              child: SizedBox(height: botPad + 100)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HERO HEADER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildHeroHeader(double topPad) {
    final h        = DateTime.now().hour;
    final greeting = h < 12 ? 'Good morning'
        : h < 17 ? 'Good afternoon' : 'Good evening';
    final location = _userCity.isNotEmpty
        ? '$_userArea, $_userCity' : _userArea;

    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
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

          // ── Decorative blobs ──────────────────────────────────
          Positioned(top: -30, right: -50,
            child: Container(width: 200, height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle))),
          Positioned(top: 80, right: 20,
            child: Container(width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle))),
          Positioned(bottom: 60, left: -40,
            child: Container(width: 160, height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle))),
          Positioned(bottom: 30, right: 30,
            child: Container(width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle))),

          // ── Subtle sparkle dots ───────────────────────────────
          Positioned(top: topPad + 30, right: 80,
            child: Container(width: 4, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                shape: BoxShape.circle))),
          Positioned(top: topPad + 70, right: 140,
            child: Container(width: 3, height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                shape: BoxShape.circle))),
          Positioned(top: topPad + 50, left: 100,
            child: Container(width: 3, height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle))),

          // ── Content ───────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, topPad + 14, 20, 48),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              // Row 1: location + avatar
              Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                GestureDetector(
                  onTap: () => context.go('/account'),
                  child: Row(mainAxisSize: MainAxisSize.min,
                      children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.location_on_rounded,
                          size: 14, color: Colors.white)),
                    const SizedBox(width: 8),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('YOUR LOCATION',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                      Row(children: [
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 140),
                          child: Text(location,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1)),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 16),
                      ]),
                    ]),
                  ]),
                ),
                const Spacer(),
                // Notification
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22))),
                  child: const Icon(Icons.notifications_none_rounded,
                      color: Colors.white, size: 18)),
                const SizedBox(width: 10),
                // Avatar
                GestureDetector(
                  onTap: () => context.go('/account'),
                  child: Container(
                    width: 38, height: 38,
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
                          fontSize: 15))))),
              ]),

              const SizedBox(height: 26),

              // Row 2: greeting text
              Text(greeting,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: '$_userName ',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.15)),
                  const TextSpan(
                    text: '👋',
                    style: TextStyle(fontSize: 24)),
                ]),
              ),
              const SizedBox(height: 6),
              Text('What needs cleaning today?',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500)),

              const SizedBox(height: 22),

              // Row 3: quick service chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(children: [
                  _heroChip('🚿', 'Bathroom'),
                  _heroChip('🍳', 'Kitchen'),
                  _heroChip('🏠', 'Full House'),
                  _heroChip('🎉', 'Party'),
                  _heroChip('❄️', 'Fridge'),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _heroChip(String emoji, String label) {
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
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STATS STRIP
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStatsStrip() {
    const stats = [
      {'icon': '⭐', 'val': '4.8',    'label': 'Rating'},
      {'icon': '🧹', 'val': '2,400+', 'label': 'Jobs done'},
      {'icon': '👷', 'val': '50+',    'label': 'Pros'},
      {'icon': '⚡',  'val': '<2hr',   'label': 'Response'},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      padding: const EdgeInsets.symmetric(
          vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14, offset: const Offset(0, 4)),
        ]),
      child: Row(children: stats.map((s) {
        final isLast = s == stats.last;
        return Expanded(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
          Text(s['icon']!,
              style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 5),
          Text(s['val']!, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w900,
              color: _ink)),
          const SizedBox(height: 2),
          Text(s['label']!, style: const TextStyle(
              fontSize: 9, color: _faint,
              fontWeight: FontWeight.w600)),
        ]));
      }).toList()),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION LABEL
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('Our Services',
              style: TextStyle(fontSize: 19,
                  fontWeight: FontWeight.w900, color: _ink)),
          Text('${_filtered.length} available',
              style: const TextStyle(fontSize: 11,
                  color: _cyan, fontWeight: FontWeight.w600)),
        ]),
        Row(children: [
          Container(width: 7, height: 7,
            decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle)),
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
                      : [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 1))]),
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
                  color: Colors.white,
                  shape: BoxShape.circle,
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
                child: ScaleTransition(
                    scale: scale, child: child)),
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

          // Image area
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
                      fontSize: 70,
                      color: accent.withValues(alpha: 0.13)))),
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

          // Info area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Text(svc['name'] as String,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800,
                        color: _ink, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
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
  // PROMO BANNER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildPromoBanner() {
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
        margin: const EdgeInsets.fromLTRB(18, 28, 18, 0),
        height: 116,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C4A6E), Color(0xFF0891B2)]),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
              color: _cyanDk.withValues(alpha: 0.30),
              blurRadius: 20, offset: const Offset(0, 8))]),
        child: Stack(children: [
          Positioned(right: 70, top: -22,
            child: Container(width: 90, height: 90,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle))),
          Positioned(right: -8, bottom: -4,
            child: Text('🧴', style: TextStyle(
                fontSize: 86,
                color: Colors.white.withValues(alpha: 0.85)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 110, 0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6)),
                child: const Text('LIMITED OFFER',
                    style: TextStyle(color: Colors.white,
                        fontSize: 8, fontWeight: FontWeight.w900,
                        letterSpacing: 1.5))),
              const SizedBox(height: 7),
              const Text('Flat 20% OFF',
                  style: TextStyle(color: Colors.white,
                      fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text('Use CLEAN20 at checkout',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 11.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('TAP TO COPY →',
                    style: TextStyle(color: Color(0xFF0891B2),
                        fontSize: 11, fontWeight: FontWeight.w900,
                        letterSpacing: 0.3))),
            ]),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WHY US
  // ═══════════════════════════════════════════════════════════════
  Widget _buildWhyUs() {
    const items = [
      {'e': '🛡️', 't': 'Fully Insured',
        's': 'All damage covered',   'c': Color(0xFFF5F3FF)},
      {'e': '⚡',  't': 'Always On Time',
        's': 'Or your money back',   'c': Color(0xFFFFFBEB)},
      {'e': '🌿', 't': 'Eco Products',
        's': 'Safe for kids & pets', 'c': Color(0xFFECFDF5)},
      {'e': '🔄', 't': 'Free Re-Clean',
        's': 'If not satisfied',     'c': Color(0xFFECFEFF)},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        const Text('Why Cleenzo?',
            style: TextStyle(fontSize: 19,
                fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 4),
        Text("Mumbai's most trusted home cleaning",
            style: const TextStyle(fontSize: 12, color: _muted)),
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
          Text(item['t'] as String,
              style: const TextStyle(color: _ink, fontSize: 11,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(item['s'] as String,
              style: const TextStyle(color: _muted, fontSize: 10)),
        ])),
      ]),
    );
  }
}

// ── Wave clipper for hero bottom edge ────────────────────────────
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 36);
    path.quadraticBezierTo(
        size.width * 0.25, size.height,
        size.width * 0.5,  size.height - 18);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 36,
        size.width,        size.height - 10);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}