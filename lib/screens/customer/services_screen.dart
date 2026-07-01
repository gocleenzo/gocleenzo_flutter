import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
  late final PageController _popularCtrl;
  Timer? _autoSlideTimer;
  bool _userInteractingWithSlider = false;

  late final AnimationController _intro;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  // Subtle ambient animation for shimmer + pulse
  late final AnimationController _ambientCtrl;

  // ── Cyan blue + white palette ───────────────────────────────
  static const _cyan    = Color(0xFF06B6D4);
  static const _cyanDk  = Color(0xFF0891B2);
  static const _cyanDp  = Color(0xFF0E7490);
  static const _cyanBg  = Color(0xFFECFEFF);
  static const _cyanBg2 = Color(0xFFCFFAFE);
  static const _ink     = Color(0xFF0F172A);
  static const _muted   = Color(0xFF64748B);
  static const _faint   = Color(0xFF94A3B8);
  static const _border  = Color(0xFFE8EDF2);
  static const _bg      = Color(0xFFF8FAFC);
  static const _amber   = Color(0xFFF59E0B);

  static const _offers = [
    {'title': 'Flat 20% off', 'sub': 'On your first clean',
      'code': 'CLEAN20',  'c1': _cyanDp, 'c2': _cyan},
    {'title': 'Refer & earn ₹100', 'sub': 'For every friend who books',
      'code': 'REFER100', 'c1': _cyan,   'c2': _cyanDk},
  ];

  // ── Exact service.id → local asset mapping (reliable) ─────────
  static const Map<String, String> _assetMap = {
    '6f150323-d018-44c0-bfe2-2037efa1f5c0': 'assets/services/bathroom-cleaning.png',  // Bathroom Cleaning
    '6201b258-ed2c-4c83-b8e7-bd413cc5b67b': 'assets/services/wardrobe.png',           // Wardrobe Cleaning
    '6678a63d-059c-4ca5-ad11-3781f8449bb0': 'assets/services/full-home-cleaning.png', // Full House Cleaning
    'b7e6db9d-455d-46d5-ba4d-8e993fe1255d': 'assets/services/fan-cleaning.png',       // Fan Cleaning
    '42719385-f88c-41ab-9e59-6ac4856f6112': 'assets/services/dusting-wiping.png',     // Dusting & Wiping
    '2b3bd63d-c1d5-40cf-a818-33501e9e61b4': 'assets/services/sweeping-mopping.png',   // Sweeping & Mopping
    'ab1004e9-de4e-4ab6-9d34-30d7b23913a3': 'assets/services/fridge-cleaning.png',    // Refrigerator Cleaning
    '423a1354-d995-49df-ba67-effcb43befbf': 'assets/services/kitchen-cleaning.png',   // Kitchen Cleaning
    '5af62745-c480-4579-a81a-a6a267cef2c3': 'assets/services/Utensils-cleaning.png',  // Utensil Cleaning
    '581ee014-e42b-43bf-9818-692b08a0ac53': 'assets/services/cabinet.png',            // Kitchen Cabinet Cleaning
    'ae4eac44-3444-4d45-b4a3-6387c043d5cf': 'assets/services/balcony-cleaning.png',   // Balcony Cleaning
    'c104cecf-dc59-4514-bbaa-33301da6db1e': 'assets/services/after.png',              // After-Party Cleanup
    '44a7c787-41f1-4ed9-b8e6-5066dcc009ce': 'assets/services/pre.png',                // Pre-Party Cleaning
  };

  List<Map<String, dynamic>> _services   = [];
  List<String>               _categories = ['All'];
  String _activeTab    = 'All';
  bool   _loading      = true;
  String _userName     = 'there';
  int    _popularIndex = 0;

  // Location
  String _locationArea = '';
  String _locationCity = '';
  bool   _locationLoading = true;

  @override
  void initState() {
    super.initState();
    _popularCtrl = PageController(viewportFraction: 0.88);
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _fade  = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _ambientCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _popularCtrl.dispose();
    _intro.dispose();
    _ambientCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // RESPONSIVE SCALE
  // ═══════════════════════════════════════════════════════════════
  // 375 = baseline (a "standard" small phone like iPhone SE / Pixel).
  // Clamped so text never gets too tiny on small screens or too huge
  // on large phones / tablets.
  double _scale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final factor = w / 375.0;
    return factor.clamp(0.92, 1.15);
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA
  // ═══════════════════════════════════════════════════════════════
  Future<void> _load() async {
    final userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    try {
      final results = await Future.wait([
        _supabase.from('users').select('full_name')
            .eq('id', userId).maybeSingle(),
        _supabase.from('services').select('*')
            .eq('is_active', true).order('category'),
        _supabase.from('addresses').select('area,city,is_default')
            .eq('user_id', userId).eq('is_deleted', false)
            .order('is_default', ascending: false).limit(1).maybeSingle(),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>?;
      final svcs    = results[1] as List<dynamic>;
      final addr    = results[2] as Map<String, dynamic>?;
      setState(() {
        if (profile != null) {
          _userName = (profile['full_name'] as String?)
              ?.split(' ').first ?? 'there';
        }
        _services = svcs.cast<Map<String, dynamic>>();
        final cats = _services
            .map((s) => s['category'] as String? ?? '')
            .where((c) => c.isNotEmpty).toSet().toList()..sort();
        _categories = ['All', ...cats];
        if (addr != null) {
          _locationArea = addr['area'] as String? ?? '';
          _locationCity = addr['city'] as String? ?? '';
        }
        _locationLoading = false;
        _loading    = false;
      });
      _intro.forward();
      _startAutoSlide();
    } catch (e) {
      debugPrint('Services load error: $e');
      if (mounted) setState(() {
        _loading = false;
        _locationLoading = false;
      });
    }
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _userInteractingWithSlider) return;
      if (!_popularCtrl.hasClients) return;
      final popularCount = _services.take(4).length;
      if (popularCount <= 1) return;
      final next = (_popularIndex + 1) % popularCount;
      _popularCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic);
    });
  }

  List<Map<String, dynamic>> get _filtered => _services
      .where((s) => _activeTab == 'All' || s['category'] == _activeTab)
      .toList();

  IconData _iconFor(String text) {
    final s = text.toLowerCase();
    if (s.contains('bath'))                              return Icons.bathtub_outlined;
    if (s.contains('kitchen'))                           return Icons.countertops_outlined;
    if (s.contains('sofa') || s.contains('uphol'))       return Icons.weekend_outlined;
    if (s.contains('fridge') || s.contains('appliance')) return Icons.kitchen_outlined;
    if (s.contains('window') || s.contains('glass'))     return Icons.window_outlined;
    if (s.contains('floor') || s.contains('tile'))       return Icons.grid_4x4_outlined;
    if (s.contains('party') || s.contains('event'))      return Icons.celebration_outlined;
    if (s.contains('home') || s.contains('full'))        return Icons.home_outlined;
    if (s.contains('all'))                               return Icons.apps_outlined;
    return Icons.cleaning_services_outlined;
  }

  /// Returns the local asset path for a service by exact id match.
  /// Returns null if the id isn't in the map.
  String? _assetFor(Map<String, dynamic> svc) {
    final id = svc['id'] as String?;
    if (id == null) return null;
    return _assetMap[id];
  }

  Widget _anim(Widget child) => FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: child));

  void _open(Map<String, dynamic> svc) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => ServiceDetailScreen(serviceId: svc['id'] as String)));
  }

  void _openNotifications() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(supabase: _supabase),
    );
  }

  void _openLocationPicker() {
    HapticFeedback.selectionClick();
    context.push('/saved-addresses');
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(
            color: _cyan, strokeWidth: 2.5)),
      );
    }

    final all     = _services;
    final isAll   = _activeTab == 'All';
    final popular = all.take(4).toList();
    final popIds  = popular.map((s) => s['id']).toSet();
    final grid    = isAll
        ? all.where((s) => !popIds.contains(s['id'])).toList()
        : _filtered;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Sticky top bar: location + greeting + notification + profile.
          // Stays pinned while the rest of the screen scrolls underneath.
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTopBar(
              topPad: topPad,
              child: _buildStickyBar(topPad),
            ),
          ),

          // Offers carousel now scrolls away beneath the sticky bar.
          SliverToBoxAdapter(child: _anim(Column(children: [
            _buildOffers(),
            const SizedBox(height: 12),
          ]))),

          if (all.isEmpty)
            SliverToBoxAdapter(child: _buildEmpty())
          else ...[
            if (isAll && popular.isNotEmpty) ...[
              _sliverHeader('Popular'),
              SliverToBoxAdapter(child: _anim(_buildPopularSlider(popular))),
            ],
            if (grid.isNotEmpty) ...[
              _sliverHeader(isAll ? 'Top searching' : _activeTab),
              _buildGrid(grid),
            ] else if (!isAll)
              SliverToBoxAdapter(child: _buildEmpty()),
          ],

          SliverToBoxAdapter(child: SizedBox(height: botPad + 24)),
        ],
      ),
    );
  }

  // ── Sticky top bar: gradient backdrop + location + header ──────
  Widget _buildStickyBar(double topPad) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_cyanBg, Color(0xFFF8FAFC)],
            stops: [0.0, 1.0],
          ),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildLocationBar(topPad),
          _buildHeader(),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ── Location row (nav bar label) — bold, standard weight, responsive ──
  Widget _buildLocationBar(double topPad) {
    final hasAddr = _locationArea.isNotEmpty || _locationCity.isNotEmpty;
    final label = !hasAddr
        ? (_locationLoading ? 'Locating…' : 'Set your location')
        : (_locationCity.isNotEmpty
            ? '$_locationArea, $_locationCity'
            : _locationArea);
    final s = _scale(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 0),
      child: GestureDetector(
        onTap: _openLocationPicker,
        behavior: HitTestBehavior.opaque,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: 0.14),
              shape: BoxShape.circle),
            child: const Icon(Icons.location_on_rounded,
                size: 14, color: _cyanDk)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fredoka(
                    color: _cyanDp, fontSize: 14.5 * s,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1)),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: _cyanDk),
        ]),
      ),
    );
  }

  // ── Header: big greeting + bell (with dot) + profile ──────────
  Widget _buildHeader() {
    final s = _scale(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text('Hello $_userName!',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _ink, fontSize: 29 * s,
                fontWeight: FontWeight.w800, height: 1.1,
                fontFamily: 'Gilroy'))),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _openNotifications,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                border: Border.all(color: _border),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6, offset: const Offset(0, 2))]),
              child: const Icon(Icons.notifications_none_rounded,
                  color: _ink, size: 21)),
            Positioned(top: 9, right: 11, child: AnimatedBuilder(
              animation: _ambientCtrl,
              builder: (_, __) => Transform.scale(
                scale: 1.0 + _ambientCtrl.value * 0.25,
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444), shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5))),
              ),
            )),
          ]),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => context.go('/account'),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: _cyan.withValues(alpha: 0.30),
                  blurRadius: 10, offset: const Offset(0, 4))]),
            child: Center(child: Text(
              _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 17))),
          ),
        ),
      ]),
    );
  }

  // ── Offers carousel (with subtle shimmer sweep) ────────────────
  Widget _buildOffers() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _offers.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final o = _offers[i];
            return GestureDetector(
              onTap: () => _copyPromo(o['code'] as String),
              child: Container(
                width: 270,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [o['c1'] as Color, o['c2'] as Color]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                      color: (o['c1'] as Color).withValues(alpha: 0.30),
                      blurRadius: 16, offset: const Offset(0, 7))]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(children: [
                    Positioned(right: -12, bottom: -16, child: Icon(
                        Icons.local_offer_rounded, size: 84,
                        color: Colors.white.withValues(alpha: 0.13))),
                    // Subtle shimmer sweep
                    AnimatedBuilder(
                      animation: _ambientCtrl,
                      builder: (_, __) => Positioned(
                        left: -100 + (_ambientCtrl.value * 380),
                        top: 0, bottom: 0,
                        child: Transform.rotate(
                          angle: 0.4,
                          child: Container(
                            width: 50,
                            color: Colors.white.withValues(alpha: 0.06)),
                        ),
                      ),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(o['title'] as String, style: const TextStyle(
                          color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(o['sub'] as String, style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 11.5)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(o['code'] as String, style: TextStyle(
                              color: o['c1'] as Color, fontSize: 11,
                              fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          const SizedBox(width: 5),
                          Icon(Icons.copy_rounded, size: 11,
                              color: o['c1'] as Color),
                        ])),
                    ]),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _copyPromo(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$code copied to clipboard'),
      backgroundColor: _cyanDk,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      duration: const Duration(seconds: 2)));
  }

  // ── Category circles ──────────────────────────────────────────
  Widget _buildCircles() {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          final cat    = _categories[i];
          final active = cat == _activeTab;
          return GestureDetector(
            onTap: () {
              setState(() {
                _activeTab    = cat;
                _popularIndex = 0;
              });
              HapticFeedback.selectionClick();
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 58, height: 58,
                decoration: BoxDecoration(
                  color: active ? _cyan : _cyanBg,
                  shape: BoxShape.circle,
                  boxShadow: active ? [BoxShadow(
                      color: _cyan.withValues(alpha: 0.30),
                      blurRadius: 10, offset: const Offset(0, 4))] : null),
                child: Icon(_iconFor(cat), size: 26,
                    color: active ? Colors.white : _cyanDk),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64,
                child: Text(cat, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: active ? _cyanDk : _muted,
                        fontWeight: active
                            ? FontWeight.w800 : FontWeight.w600)),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ── Popular: auto-sliding feature cards (still swipeable) ──────
  Widget _buildPopularSlider(List<Map<String, dynamic>> popular) {
    return Column(children: [
      SizedBox(
        height: 244,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notif) {
            if (notif is ScrollStartNotification &&
                notif.dragDetails != null) {
              _userInteractingWithSlider = true;
            } else if (notif is ScrollEndNotification) {
              _userInteractingWithSlider = false;
            }
            return false;
          },
          child: PageView.builder(
            controller: _popularCtrl,
            onPageChanged: (i) => setState(() => _popularIndex = i),
            itemCount: popular.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _featureCard(popular[i]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(popular.length, (i) {
        final active = i == _popularIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 6, height: 6,
          decoration: BoxDecoration(
            color: active ? _cyan : _border,
            borderRadius: BorderRadius.circular(3)),
        );
      })),
    ]);
  }

  // ── Popular feature card — plain image on top, name + price below ──
  Widget _featureCard(Map<String, dynamic> svc) {
    final name  = svc['name'] as String? ?? 'Service';
    final price = (svc['base_price'] as num?)?.toInt() ?? 0;
    final icon  = _iconFor('${svc['category'] ?? ''} $name');
    final s     = _scale(context);

    return GestureDetector(
      onTap: () => _open(svc),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14, offset: const Offset(0, 6))]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20)),
              child: Stack(fit: StackFit.expand, children: [
                _serviceImage(svc, icon),
                Positioned(top: 10, right: 10,
                    child: _ratingBadge(svc)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _ink,
                      fontSize: 16 * s, fontWeight: FontWeight.w800,
                      letterSpacing: 0.1)),
              const SizedBox(height: 4),
              Text('₹$price / visit', style: TextStyle(
                  color: _cyanDk,
                  fontSize: 13 * s, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Grid of smaller photo cards ───────────────────────────────
  Widget _buildGrid(List<Map<String, dynamic>> svcs) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   2,
          crossAxisSpacing: 14,
          mainAxisSpacing:  18,
          mainAxisExtent:   190,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => FadeTransition(
              opacity: _fade, child: _gridCard(svcs[i])),
          childCount: svcs.length,
        ),
      ),
    );
  }

  // ── Grid card — plain image on top, name + price below (like reference) ──
  Widget _gridCard(Map<String, dynamic> svc) {
    final name  = svc['name'] as String? ?? 'Service';
    final price = (svc['base_price'] as num?)?.toInt() ?? 0;
    final icon  = _iconFor('${svc['category'] ?? ''} $name');
    final s     = _scale(context);

    return GestureDetector(
      onTap: () => _open(svc),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          // Image fills whatever space is left after the text block below,
          // so it can never overflow the grid cell on any device.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(fit: StackFit.expand, children: [
                _serviceImage(svc, icon),
                Positioned(top: 8, right: 8, child: _ratingBadge(svc)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _ink,
                  fontSize: 14 * s, fontWeight: FontWeight.w800,
                  letterSpacing: 0.1)),
          const SizedBox(height: 2),
          Text('₹$price / visit', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: _cyanDk,
                  fontSize: 12 * s, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Shared pieces ─────────────────────────────────────────────
  Widget _ratingBadge(Map<String, dynamic> svc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 6, offset: const Offset(0, 2))]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 12, color: _amber),
      const SizedBox(width: 2),
      Text(_rating(svc), style: const TextStyle(fontSize: 10.5,
          fontWeight: FontWeight.w800, color: _ink)),
    ]),
  );

  String _rating(Map<String, dynamic> svc) {
    final r = svc['rating'];
    if (r is num) return r.toStringAsFixed(1);
    return '4.8';
  }

  /// Image priority:
  /// 1. Supabase `image_url` (network image) if present
  /// 2. Local asset matched by exact service.id (assets/services/...)
  /// 3. Gradient + icon placeholder
  Widget _serviceImage(Map<String, dynamic> svc, IconData icon) {
    final url = (svc['image_url'] as String?)?.trim();

    Widget placeholder() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [_cyanBg, _cyanBg2])),
      child: Center(child: Icon(icon, size: 40,
          color: _cyanDk.withValues(alpha: 0.50))),
    );

    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
        loadingBuilder: (ctx, child, prog) =>
            prog == null ? child : Container(color: const Color(0xFFF1F5F9)),
        errorBuilder: (ctx, e, s) {
          final asset = _assetFor(svc);
          if (asset != null) {
            return Image.asset(asset, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder());
          }
          return placeholder();
        });
    }

    final asset = _assetFor(svc);
    if (asset != null) {
      return Image.asset(asset, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder());
    }

    return placeholder();
  }

  SliverToBoxAdapter _sliverHeader(String title) =>
      SliverToBoxAdapter(child: _anim(_sectionHeader(title)));

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: const TextStyle(fontSize: 18,
          fontWeight: FontWeight.w900, color: _ink)),
      GestureDetector(
        onTap: () => HapticFeedback.selectionClick(),
        child: const Text('See all', style: TextStyle(
            fontSize: 12.5, color: _cyanDk, fontWeight: FontWeight.w700)),
      ),
    ]),
  );

  Widget _buildEmpty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 52),
    child: Column(children: [
      Container(width: 66, height: 66,
        decoration: const BoxDecoration(color: _cyanBg, shape: BoxShape.circle),
        child: const Icon(Icons.search_off_rounded, size: 28, color: _cyanDk)),
      const SizedBox(height: 14),
      const Text('No services found', style: TextStyle(color: _ink,
          fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Try a different category',
          style: TextStyle(color: _faint, fontSize: 13)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════
// STICKY TOP BAR DELEGATE
// ═══════════════════════════════════════════════════════════════
class _StickyTopBar extends SliverPersistentHeaderDelegate {
  final double topPad;
  final Widget child;
  _StickyTopBar({required this.topPad, required this.child});

  // status bar inset + location row (~40) + greeting row (~58) + 10 spacing,
  // with 2px slack so the fixed-height bar can never overflow.
  double get _height => topPad + 110;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset,
          bool overlapsContent) =>
      SizedBox.expand(child: child);

  @override
  bool shouldRebuild(covariant _StickyTopBar oldDelegate) =>
      oldDelegate.topPad != topPad || oldDelegate.child != child;
}

// ═══════════════════════════════════════════════════════════════
// NOTIFICATIONS SHEET
// ═══════════════════════════════════════════════════════════════
class _NotificationsSheet extends StatefulWidget {
  final SupabaseClient supabase;
  const _NotificationsSheet({required this.supabase});
  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _cyanBg = Color(0xFFECFEFF);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE8EDF2);

  bool _loading = true;
  List<_Notif> _new = [];
  List<_Notif> _earlier = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final userId = await SupabaseService.loadCachedUserId() ??
          SupabaseService.currentUserId;
      if (userId != null) {
        final rows = await widget.supabase.from('notifications')
            .select('*').eq('user_id', userId)
            .order('created_at', ascending: false).limit(50);
        final list = (rows as List).cast<Map<String, dynamic>>();
        if (list.isNotEmpty) {
          final now = DateTime.now();
          final parsed = list.map((r) {
            final created = DateTime.tryParse(
                r['created_at']?.toString() ?? '') ?? now;
            final isNew = now.difference(created).inHours < 24;
            return _Notif(
              title: r['title'] as String? ?? 'Notification',
              body: (r['body'] ?? r['message'] ?? '').toString(),
              time: _ago(created, now),
              unread: !(r['is_read'] == true || r['read'] == true),
              isNew: isNew,
            );
          }).toList();
          if (mounted) setState(() {
            _new = parsed.where((n) => n.isNew).toList();
            _earlier = parsed.where((n) => !n.isNew).toList();
            _loading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Notifications sheet load error: $e');
    }
    if (mounted) setState(() {
      _new = _sampleNew;
      _earlier = _sampleEarlier;
      _loading = false;
    });
  }

  String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1)  return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    if (d.inDays == 1)    return 'Yesterday';
    if (d.inDays < 7)     return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  static final _sampleNew = [
    _Notif(title: 'Booking confirmed',
        body: 'Your bathroom deep clean is scheduled for tomorrow, 10:00 AM.',
        time: '2h ago', unread: true, isNew: true,
        icon: Icons.event_available_rounded),
    _Notif(title: 'Offer applied',
        body: 'You saved ₹100 with code CLEAN20 on your last booking.',
        time: '5h ago', unread: true, isNew: true,
        icon: Icons.local_offer_rounded),
  ];
  static final _sampleEarlier = [
    _Notif(title: 'Your pro is on the way',
        body: 'Rahul is arriving for your kitchen deep clean.',
        time: 'Yesterday', icon: Icons.directions_car_rounded),
    _Notif(title: 'Rate your service',
        body: 'How was your sofa cleaning? Tap to leave a review.',
        time: '2d ago', icon: Icons.star_rounded),
    _Notif(title: 'Welcome to Cleenzo',
        body: 'Book your first clean and get 20% off your order.',
        time: '1w ago', icon: Icons.celebration_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72, minChildSize: 0.45, maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Notifications', style: TextStyle(fontSize: 19,
                  fontWeight: FontWeight.w900, color: _ink)),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(width: 32, height: 32,
                  decoration: const BoxDecoration(
                      color: _cyanBg, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: _cyanDk))),
            ])),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: _cyan, strokeWidth: 2.5))
            : (_new.isEmpty && _earlier.isEmpty)
              ? _empty()
              : ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    if (_new.isNotEmpty) ..._group('New', _new),
                    if (_earlier.isNotEmpty) ..._group('Earlier', _earlier),
                  ])),
        ]),
      ),
    );
  }

  List<Widget> _group(String label, List<_Notif> items) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
      child: Text(label.toUpperCase(), style: const TextStyle(
          fontSize: 11, color: _faint,
          fontWeight: FontWeight.w800, letterSpacing: 0.8))),
    ...items.map(_row),
  ];

  Widget _row(_Notif n) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: n.unread ? _cyanBg : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: n.unread ? const Color(0xFFCFFAFE) : _border)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_cyan, _cyanDk]),
          shape: BoxShape.circle),
        child: Icon(n.icon, color: Colors.white, size: 19)),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(n.title, style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink))),
          if (n.unread) Container(width: 7, height: 7,
            decoration: const BoxDecoration(
                color: _cyan, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 3),
        Text(n.body, style: const TextStyle(
            fontSize: 12, color: _muted, height: 1.35)),
        const SizedBox(height: 5),
        Text(n.time, style: const TextStyle(
            fontSize: 10.5, color: _faint, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );

  Widget _empty() => Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
    Container(width: 66, height: 66,
      decoration: const BoxDecoration(color: _cyanBg, shape: BoxShape.circle),
      child: const Icon(Icons.notifications_none_rounded,
          size: 30, color: _cyanDk)),
    const SizedBox(height: 14),
    const Text("You're all caught up", style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
    const SizedBox(height: 4),
    const Text('No notifications yet',
        style: TextStyle(fontSize: 13, color: _faint)),
  ]));
}

class _Notif {
  final String title, body, time;
  final bool unread, isNew;
  final IconData icon;
  _Notif({required this.title, required this.body, required this.time,
      this.unread = false, this.isNew = false,
      this.icon = Icons.notifications_rounded});
}