import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';
import 'service_detail_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _supabase  = Supabase.instance.client;
  final _pageCtrl  = PageController();

  int    _slide      = 0;
  Timer? _slideTimer;

  static const _slides = [
    {
      'emoji': '🛋️',
      'title': 'Home Cleaning',
      'sub': 'Make your home sparkling clean',
      'c1': Color(0xFF0EA5E9), 'c2': Color(0xFF0369A1),
      'tag': 'MOST POPULAR',
    },
    {
      'emoji': '🍳',
      'title': 'Kitchen Cleaning',
      'sub': 'Grease-free, hygienic kitchen',
      'c1': Color(0xFF10B981), 'c2': Color(0xFF047857),
      'tag': 'BESTSELLER',
    },
    {
      'emoji': '🚿',
      'title': 'Bathroom Cleaning',
      'sub': 'Spotless, Fresh. Germ-free.',
      'c1': Color(0xFF8B5CF6), 'c2': Color(0xFF5B21B6),
      'tag': 'HYGIENE FIRST',
    },
    {
      'emoji': '🧹',
      'title': 'Deep Cleaning',
      'sub': 'Top to bottom thorough cleaning',
      'c1': Color(0xFFF59E0B), 'c2': Color(0xFFB45309),
      'tag': 'DEEP CLEAN',
    },
  ];

  static const List<Color> _cardBg = [
    Color(0xFFE8F4FD), Color(0xFFE8F8F0), Color(0xFFF0F0FD), Color(0xFFFDF5E8),
    Color(0xFFFDE8EC), Color(0xFFE8FDF8), Color(0xFFF5E8FD), Color(0xFFFDF0E8),
  ];
  static const List<Color> _cardAccent = [
    Color(0xFF0891B2), Color(0xFF059669), Color(0xFF7C3AED), Color(0xFFD97706),
    Color(0xFFDC2626), Color(0xFF0D9488), Color(0xFF9333EA), Color(0xFFEA580C),
  ];
  static const List<String> _emojis = [
    '🛋️','🍳','🚿','🧹','🪴','❄️','👔','🧽',
    '🏠','🎉','🪟','🧴','🪣','🫧','✨','🧼',
  ];

  List<Map<String, dynamic>> _services   = [];
  List<String>               _categories = ['All'];
  String  _activeTab = 'All';
  bool    _loading   = true;
  String  _userName  = 'User';
  String  _userArea  = 'Mumbai';
  String  _userCity  = '';

  @override
  void initState() {
    super.initState();
    _load();
    _slideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final next = (_slide + 1) % _slides.length;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
      setState(() => _slide = next);
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) { if (mounted) context.go('/login'); return; }
    try {
      final results = await Future.wait([
        _supabase.from('users').select('full_name').eq('id', user.id).maybeSingle(),
        _supabase.from('addresses').select('area,city').eq('user_id', user.id).limit(1).maybeSingle(),
        _supabase.from('services').select('*').eq('is_active', true).order('category'),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>?;
      final addr    = results[1] as Map<String, dynamic>?;
      final svcs    = results[2] as List<dynamic>;
      setState(() {
        if (profile != null)
          _userName = (profile['full_name'] as String?)?.split(' ').first ?? 'User';
        if (addr != null) {
          _userArea = addr['area'] ?? 'Mumbai';
          _userCity = addr['city'] ?? '';
        }
        _services = svcs.cast<Map<String, dynamic>>();
        final cats = _services
            .map((s) => s['category'] as String? ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()..sort();
        _categories = ['All', ...cats];
        _loading    = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered => _services.where((s) {
    return _activeTab == 'All' || s['category'] == _activeTab;
  }).toList();

  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0891B2))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            collapsedHeight: 80,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: _buildFlexibleHero(),
          ),
          SliverToBoxAdapter(child: _buildCategories()),
          SliverToBoxAdapter(child: _buildSectionLabel()),
          _buildGrid(),
          SliverToBoxAdapter(child: _buildBanner()),
          SliverToBoxAdapter(child: _buildWhyUs()),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  // ── FLEXIBLE HERO ────────────────────────────────────────────────────────
  Widget _buildFlexibleHero() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final maxH      = 300.0;
      final minH      = 80.0;
      final expandPct = ((constraints.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0);
      final collapsed = expandPct < 0.3;
      final s = _slides[_slide];

      return Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _slide = i),
            itemCount: _slides.length,
            itemBuilder: (_, i) {
              final sl = _slides[i];
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [sl['c1'] as Color, sl['c2'] as Color],
                  ),
                ),
                child: Stack(children: [
                  Positioned(top: -60, right: -60,
                    child: Container(width: 240, height: 240,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          shape: BoxShape.circle))),
                  Positioned(bottom: -30, left: -30,
                    child: Container(width: 150, height: 150,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle))),
                  Positioned(right: -10, bottom: -10,
                    child: Text(sl['emoji'] as String,
                      style: TextStyle(fontSize: 160,
                          color: Colors.white.withOpacity(0.12)))),
                  Positioned(
                    right: 30,
                    bottom: 50 + (expandPct * 20),
                    child: Transform.scale(
                      scale: 0.7 + expandPct * 0.6,
                      child: Text(sl['emoji'] as String,
                          style: const TextStyle(fontSize: 80)),
                    ),
                  ),
                ]),
              );
            },
          ),
          Positioned(left: 0, right: 0, bottom: 0,
            child: Container(height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent,
                    const Color(0xFFF8FAFC).withOpacity(0.85)])))),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => context.go('/account'),
                      child: Row(children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Your Location',
                              style: TextStyle(color: Colors.white70,
                                  fontSize: 9, fontWeight: FontWeight.w500)),
                          Text(
                            _userCity.isNotEmpty
                                ? '$_userArea, $_userCity' : _userArea,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 13, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/account'),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.55), width: 2),
                        ),
                        child: Center(child: Text(
                          _userName.isNotEmpty
                              ? _userName[0].toUpperCase() : 'A',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w900, fontSize: 16),
                        )),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedOpacity(
                        opacity: expandPct,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            (s['tag'] as String),
                            style: const TextStyle(color: Colors.white,
                                fontSize: 9, fontWeight: FontWeight.w900,
                                letterSpacing: 1.2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedOpacity(
                        opacity: expandPct,
                        duration: const Duration(milliseconds: 150),
                        child: Text(s['title'] as String,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22 + expandPct * 4,
                              fontWeight: FontWeight.w900, height: 1.2)),
                      ),
                      const SizedBox(height: 4),
                      AnimatedOpacity(
                        opacity: expandPct,
                        duration: const Duration(milliseconds: 150),
                        child: Text(s['sub'] as String,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 12)),
                      ),
                      const SizedBox(height: 12),
                      Row(children: List.generate(
                        _slides.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          margin: const EdgeInsets.only(right: 5),
                          width: i == _slide ? 18 : 5, height: 5,
                          decoration: BoxDecoration(
                            color: i == _slide
                                ? Colors.white
                                : Colors.white.withOpacity(0.38),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      )),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
            ]),
          ),
        ],
      );
    });
  }

  // ── CATEGORY CHIPS ───────────────────────────────────────────────────────
  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
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
              onTap: () => setState(() => _activeTab = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF0891B2) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF0891B2) : const Color(0xFFDDE3EB),
                    width: 1.5),
                  boxShadow: active
                      ? [BoxShadow(
                          color: const Color(0xFF0891B2).withOpacity(0.30),
                          blurRadius: 10, offset: const Offset(0, 2))]
                      : [],
                ),
                child: Text(cat,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFF64748B),
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── SECTION LABEL ────────────────────────────────────────────────────────
  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Our Services',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A))),
        Text('${_filtered.length} available',
            style: const TextStyle(fontSize: 11, color: Color(0xFF0891B2),
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── 2 × N GRID ───────────────────────────────────────────────────────────
  Widget _buildGrid() {
    final svcs = _filtered;
    if (svcs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 50),
          child: Center(child: Column(children: [
            Text('🔍', style: TextStyle(fontSize: 42)),
            SizedBox(height: 10),
            Text('No services found',
                style: TextStyle(color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold)),
          ])),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, row) {
            final a = row * 2;
            final b = a + 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildCard(svcs[a], a)),
                const SizedBox(width: 14),
                b < svcs.length
                    ? Expanded(child: _buildCard(svcs[b], b))
                    : const Expanded(child: SizedBox()),
              ]),
            );
          },
          childCount: (svcs.length / 2).ceil(),
        ),
      ),
    );
  }

  // ── SERVICE CARD ─────────────────────────────────────────────────────────
  Widget _buildCard(Map<String, dynamic> svc, int i) {
    final bg      = _cardBg[i % _cardBg.length];
    final accent  = _cardAccent[i % _cardAccent.length];
    final emoji   = _emojis[i % _emojis.length];
    final price   = (svc['base_price']       as num).toInt();
    final dur     = (svc['duration_minutes'] as num).toInt();
    final imgPath = svc['image_url'] != null
        ? 'assets/${svc['image_url']}'
        : null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => ServiceDetailScreen(serviceId: svc['id'])));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EDF2), width: 1.0),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── Name ────────────────────────────────────────────
              Text(svc['name'],
                  style: const TextStyle(fontSize: 13.5,
                      fontWeight: FontWeight.w800, color: Color(0xFF0F172A),
                      height: 1.3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),

              // ── Duration (cyan) ──────────────────────────────────
              Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 10, color: Color(0xFF06B6D4)),
                const SizedBox(width: 3),
                Text('${dur}m', style: const TextStyle(fontSize: 10,
                    color: Color(0xFF06B6D4), fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),

              // ── Image / Emoji fallback ───────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 96, width: double.infinity, color: bg,
                  child: imgPath != null
                      ? Image.asset(imgPath, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _emojiPlaceholder(emoji, accent))
                      : _emojiPlaceholder(emoji, accent),
                ),
              ),
              const SizedBox(height: 10),

              // ── Price (black) — no Book button ───────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('₹$price', style: const TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A))),          // ← black
                    const Text('per visit',
                        style: TextStyle(fontSize: 9,
                            color: Color(0xFF94A3B8))),
                  ]),
                  // "View details" hint so card feels tappable
                  const Row(children: [
                    Text('View details',
                        style: TextStyle(fontSize: 10,
                            color: Color(0xFF06B6D4),
                            fontWeight: FontWeight.w600)),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 9, color: Color(0xFF06B6D4)),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Emoji fallback placeholder ────────────────────────────────────────────
  Widget _emojiPlaceholder(String emoji, Color accent) {
    return Stack(children: [
      Positioned(
        bottom: -14, right: -14,
        child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.09),
            shape: BoxShape.circle,
          ),
        ),
      ),
      Center(child: Text(emoji, style: const TextStyle(fontSize: 50))),
    ]);
  }

  // ── PROMO BANNER ─────────────────────────────────────────────────────────
  Widget _buildBanner() {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(const ClipboardData(text: 'CLEAN20'));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎉 CLEAN20 copied!'),
            duration: Duration(seconds: 2)));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 24, 18, 0),
        height: 108,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(children: [
          Positioned(right: 14, bottom: 0,
            child: Text('🧴', style: TextStyle(
                fontSize: 80, color: Colors.white.withOpacity(0.88)))),
          Positioned(right: 80, top: -22,
            child: Container(width: 100, height: 100,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle))),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 110, 0),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Flat 20% OFF',
                  style: TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              const Text('on your first booking',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('BOOK NOW',
                    style: TextStyle(color: Color(0xFF0891B2),
                        fontSize: 11, fontWeight: FontWeight.w900,
                        letterSpacing: 0.8)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── WHY CHOOSE US ────────────────────────────────────────────────────────
  Widget _buildWhyUs() {
    const items = [
      {'icon': Icons.person_outline_rounded,     'label': 'Expert\nProfessionals'},
      {'icon': Icons.verified_user_outlined,      'label': 'Background\nVerified'},
      {'icon': Icons.sentiment_satisfied_rounded, 'label': 'Satisfaction\nGuaranteed'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Why Choose Cleenzo?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A))),
        const SizedBox(height: 14),
        Row(children: items.map((b) => Expanded(
          child: Column(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0F7FA),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(b['icon'] as IconData,
                  color: const Color(0xFF0891B2), size: 26),
            ),
            const SizedBox(height: 7),
            Text(b['label'] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: Color(0xFF334155),
                    height: 1.3)),
          ]),
        )).toList()),
      ]),
    );
  }
}