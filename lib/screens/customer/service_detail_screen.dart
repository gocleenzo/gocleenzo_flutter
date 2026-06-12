import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';
import '../../widgets/booking_type_sheet.dart';
import 'booking_flow_screen.dart';

class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  const ServiceDetailScreen({super.key, required this.serviceId});
  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _liked   = false;
  String _tab   = 'about';
  late AnimationController _anim;
  late Animation<double>   _fade;

  List<Map<String, dynamic>> _reviews      = [];
  Map<String, dynamic>?      _reviewStats;
  bool   _reviewsLoading = true;
  bool   _submitting     = false;

  int    _draftStars  = 0;
  final  _draftCtrl   = TextEditingController();
  String? _myReviewId;

  RealtimeChannel? _reviewChannel;

  static const _whyUs = [
    {'icon': '🛡️', 'title': 'Fully Insured',  'sub': 'Damage covered',    'bg': 0xFFF5F3FF, 'border': 0xFFDDD6FE, 'text': 0xFF6D28D9},
    {'icon': '⭐',  'title': 'Top Rated',       'sub': '4.8 / 5 stars',    'bg': 0xFFFFFBEB, 'border': 0xFFFDE68A, 'text': 0xFFB45309},
    {'icon': '💳',  'title': 'Flexible Pay',    'sub': 'UPI · Card · Cash', 'bg': 0xFFECFDF5, 'border': 0xFFA7F3D0, 'text': 0xFF065F46},
    {'icon': '🔄',  'title': 'Re-Clean',        'sub': 'If not satisfied',  'bg': 0xFFECFEFF, 'border': 0xFFA5F3FC, 'text': 0xFF155E75},
  ];

  static const _cfg = <String, Map<String, dynamic>>{
  'Bathroom Cleaning':          {'emoji': '🚿', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Kitchen Cleaning':           {'emoji': '🍳', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Kitchen Cabinet Cleaning':   {'emoji': '🗄️', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Fan Cleaning':               {'emoji': '💨', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Balcony Cleaning':           {'emoji': '🌿', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Dusting & Wiping':           {'emoji': '🧹', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Sweeping & Mopping':         {'emoji': '🧺', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Utensil Cleaning':           {'emoji': '🍽️', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Wardrobe Cleaning':          {'emoji': '👔', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Refrigerator Cleaning':      {'emoji': '❄️', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Full House Cleaning':        {'emoji': '🏠', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'Pre-Party Express Cleaning': {'emoji': '🎉', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
  'After-Party Cleanup':        {'emoji': '🧽', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490},
};

  Map<String, dynamic> _getCfg(String name) =>
      _cfg[name] ?? {'emoji': '🧹', 'c1': 0xFF06B6D4, 'c2': 0xFF0E7490};

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _load();
    _loadReviews();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _anim.dispose();
    _draftCtrl.dispose();
    _reviewChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _supabase
          .from('services')
          .select('*')
          .eq('id', widget.serviceId)
          .single();
      if (mounted) {
        setState(() { _service = data; _loading = false; });
        _anim.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadReviews() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      final results = await Future.wait([
        _supabase
            .from('reviews_with_user')
            .select('*')
            .eq('service_id', widget.serviceId)
            .order('created_at', ascending: false)
            .limit(50),
        _supabase
            .from('service_review_stats')
            .select('*')
            .eq('service_id', widget.serviceId)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      final reviewList = (results[0] as List).cast<Map<String, dynamic>>();
      final stats      = results[1] as Map<String, dynamic>?;
      final myReview   = uid != null
          ? reviewList.where((r) => r['user_id'] == uid).firstOrNull
          : null;
      setState(() {
        _reviews        = reviewList;
        _reviewStats    = stats;
        _reviewsLoading = false;
        if (myReview != null) {
          _myReviewId = myReview['id'] as String;
          _draftStars = myReview['stars'] as int;
          _draftCtrl.text = myReview['text'] as String;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  void _subscribeRealtime() {
    _reviewChannel = _supabase
        .channel('reviews:${widget.serviceId}')
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'reviews',
          filter: PostgresChangeFilter(
            type:  PostgresChangeFilterType.eq,
            column:'service_id',
            value: widget.serviceId,
          ),
          callback: (_) => _loadReviews(),
        )
        .subscribe();
  }

  Future<void> _submitReview() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) { _showSnack('Please log in to leave a review'); return; }
    if (_draftStars == 0) { _showSnack('Please select a star rating'); return; }
    if (_draftCtrl.text.trim().length < 5) { _showSnack('Review must be at least 5 characters'); return; }
    setState(() => _submitting = true);
    try {
      if (_myReviewId != null) {
        await _supabase.from('reviews').update({
          'stars': _draftStars,
          'text':  _draftCtrl.text.trim(),
        }).eq('id', _myReviewId!);
        _showSnack('✅ Review updated!');
      } else {
        await _supabase.from('reviews').insert({
          'service_id': widget.serviceId,
          'user_id':    uid,
          'stars':      _draftStars,
          'text':       _draftCtrl.text.trim(),
        });
        _showSnack('🎉 Review submitted!');
      }
      FocusScope.of(context).unfocus();
    } catch (e) {
      _showSnack('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteReview() async {
    if (_myReviewId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await _supabase.from('reviews').delete().eq('id', _myReviewId!);
    if (mounted) setState(() { _myReviewId = null; _draftStars = 0; _draftCtrl.clear(); });
    _showSnack('Review deleted');
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  void _navigate(String type) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BookingFlowScreen(mode: type, serviceId: _service!['id']),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)));

    if (_service == null) return Scaffold(
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🔍', style: TextStyle(fontSize: 50)),
        const SizedBox(height: 14),
        const Text('Service not found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 14),
        ElevatedButton.icon(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back), label: const Text('Go Back')),
      ])),
    );

    final svc   = _service!;
    final name  = svc['name'] as String;
    final cfg   = _getCfg(name);
    final c1    = Color(cfg['c1'] as int);
    final c2    = Color(cfg['c2'] as int);
    final emoji = cfg['emoji'] as String;
    final price = (svc['base_price'] as num).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: FadeTransition(
        opacity: _fade,
        child: Stack(children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildHero(svc, c1, c2, emoji),
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildSocialProof(svc, c1),
                    _buildPriceStats(svc, c1, price),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFF1F5F9), height: 1),
                    const SizedBox(height: 6),
                    _buildTabs(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: Padding(
                        key: ValueKey(_tab),
                        padding: const EdgeInsets.all(20),
                        child: _buildTabContent(svc, c1),
                      ),
                    ),
                  ]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          ),
          _buildBottomBar(svc, c1, c2, price),
        ]),
      ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────────────
  Widget _buildHero(Map<String, dynamic> svc, Color c1, Color c2, String emoji) {
    final imgUrl = svc['image_url'] as String?;

    return SliverAppBar(
      expandedHeight: 340,
      pinned: true,
      backgroundColor: c1,
      automaticallyImplyLeading: false,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.30),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              setState(() => _liked = !_liked);
              HapticFeedback.lightImpact();
            },
            child: Container(
              width: 40, height: 40, margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _liked ? Colors.red : Colors.black.withOpacity(0.30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                  _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share link copied!')));
            },
            child: Container(
              width: 40, height: 40, margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.30),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.share_outlined,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        titlePadding: EdgeInsets.zero,
        title: const SizedBox.shrink(),
        background: Stack(fit: StackFit.expand, children: [

          // ── Background: real image OR gradient ──────────────
          if (imgUrl != null)
            Image.asset(
              'assets/$imgUrl',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [c1, c2, c2.withOpacity(0.9)],
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [c1, c2, c2.withOpacity(0.9)],
                ),
              ),
            ),

          // ── Dark overlay for readability ─────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(imgUrl != null ? 0.25 : 0.0),
                  Colors.black.withOpacity(imgUrl != null ? 0.60 : 0.45),
                ],
              ),
            ),
          ),

          // ── Decorative circles (shown only when no image) ────
          if (imgUrl == null) ...[
            Positioned(top: -60, right: -60,
              child: Container(width: 260, height: 260,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    shape: BoxShape.circle))),
            Positioned(bottom: 60, left: -40,
              child: Container(width: 180, height: 180,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle))),
            Positioned(right: -20, bottom: 40,
              child: Text(emoji, style: TextStyle(
                  fontSize: 180, color: Colors.white.withOpacity(0.13)))),
            // Emoji circle (only for gradient/no-image fallback)
            Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(height: 40),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.35), width: 2),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30, spreadRadius: 5)],
                ),
                child: Center(child: Text(emoji,
                    style: const TextStyle(fontSize: 48))),
              ),
            ])),
          ],

          // ── Bottom label area (always shown) ─────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.70)],
                ),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 5, height: 5,
                        decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      (svc['category'] ?? '').toString().toUpperCase(),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.w900,
                          letterSpacing: 1.5),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(svc['name'],
                    style: const TextStyle(color: Colors.white,
                        fontSize: 24, fontWeight: FontWeight.w900,
                        height: 1.15)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _pill('⏱ ~${(svc['duration_minutes'] as num).toInt()} min'),
                  _pill('✓ Verified pros'),
                  _pill('★ 4.8 rated'),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── TABS ─────────────────────────────────────────────────────────────────
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: ['about', 'includes', 'reviews'].map((t) {
          final active = _tab == t;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _tab = t);
                HapticFeedback.selectionClick();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: active
                      ? [const BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 8, offset: Offset(0, 2))]
                      : [],
                ),
                child: Center(child: Text(
                  t[0].toUpperCase() + t.substring(1),
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                    fontSize: 13, fontWeight: FontWeight.w800,
                  ),
                )),
              ),
            ),
          );
        }).toList()),
      ),
    );
  }

  Widget _buildTabContent(Map<String, dynamic> svc, Color accent) {
    switch (_tab) {
      case 'about':    return _buildAbout(svc, accent);
      case 'includes': return _buildIncludes(svc);
      default:         return _buildReviews();
    }
  }

  // ── SOCIAL PROOF ─────────────────────────────────────────────────────────
  Widget _buildSocialProof(Map<String, dynamic> svc, Color c1) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        SizedBox(width: 72, height: 28, child: Stack(children: [
          _avatarCircle('PR', const Color(0xFF06B6D4), 0),
          _avatarCircle('RK', const Color(0xFF7C3AED), 20),
          _avatarCircle('SD', const Color(0xFFDB2777), 40),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(text: 'Priya, Rahul',
              style: TextStyle(color: c1, fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const TextSpan(text: ' and 400+ others loved this service.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        ]))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: c1.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20)),
          child: Icon(Icons.location_on_rounded, color: c1, size: 18),
        ),
      ]),
    );
  }

  // ── PRICE + STATS ─────────────────────────────────────────────────────────
  Widget _buildPriceStats(Map<String, dynamic> svc, Color c1, int price) {
    final avg = _reviewStats != null
        ? (_reviewStats!['avg_rating'] as num?)?.toDouble() ?? 4.8
        : 4.8;
    final total = _reviewStats != null
        ? (_reviewStats!['total_reviews'] as num?)?.toInt() ?? 0
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('STARTING FROM',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹$price', style: const TextStyle(fontSize: 36,
                fontWeight: FontWeight.w900, color: Color(0xFF0F172A),
                height: 1)),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(bottom: 3),
              child: Text('₹${(price * 1.4).round()}',
                  style: const TextStyle(fontSize: 14,
                      color: Color(0xFF94A3B8),
                      decoration: TextDecoration.lineThrough))),
          ]),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20)),
            child: Text('Save ₹${(price * 0.4).round()}',
                style: const TextStyle(color: Color(0xFF065F46),
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ])),
        Column(children: [
          _statChip(
            avg > 0 ? avg.toStringAsFixed(1) : '–',
            '⭐⭐⭐⭐⭐',
            total > 0 ? '$total reviews' : 'No reviews',
            const Color(0xFFFFFBEB), const Color(0xFFFDE68A),
            const Color(0xFFB45309),
          ),
          const SizedBox(height: 8),
          _statChip('2K+', '─────', 'Bookings',
              const Color(0xFFECFEFF), const Color(0xFFA5F3FC),
              AppTheme.primary),
        ]),
      ]),
    );
  }

  // ── REVIEWS ──────────────────────────────────────────────────────────────
  Widget _buildReviews() {
    if (_reviewsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(
            color: AppTheme.primary)),
      );
    }

    final stats      = _reviewStats;
    final avgRating  = stats != null
        ? (stats['avg_rating'] as num?)?.toDouble() ?? 0.0 : 0.0;
    final totalCount = stats != null
        ? (stats['total_reviews'] as num?)?.toInt() ?? 0 : 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Rating summary
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(children: [
          Column(children: [
            Text(
              avgRating > 0 ? avgRating.toStringAsFixed(1) : '–',
              style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900,
                  color: Color(0xFFB45309), height: 1),
            ),
            _stars(avgRating.round(), 13),
            const SizedBox(height: 4),
            Text('$totalCount review${totalCount == 1 ? '' : 's'}',
                style: const TextStyle(color: Color(0xFF92400E),
                    fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 20),
          Expanded(child: Column(
            children: [5, 4, 3, 2, 1].map((star) {
              final count = stats != null
                  ? (stats['${_starKey(star)}_star'] as num?)?.toInt() ?? 0
                  : 0;
              final pct = totalCount > 0 ? count / totalCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 12, child: Text('$star',
                      style: const TextStyle(color: Color(0xFFB45309),
                          fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 6),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: const Color(0xFFFDE68A),
                      valueColor: const AlwaysStoppedAnimation(
                          Color(0xFFF59E0B)),
                      minHeight: 7,
                    ),
                  )),
                  const SizedBox(width: 6),
                  SizedBox(width: 20, child: Text('$count',
                      style: const TextStyle(color: Color(0xFF92400E),
                          fontSize: 10))),
                ]),
              );
            }).toList(),
          )),
        ]),
      ),

      const SizedBox(height: 20),
      _buildWriteReviewCard(),
      const SizedBox(height: 20),

      if (_reviews.isEmpty)
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Column(children: [
            Text('💬', style: TextStyle(fontSize: 38)),
            SizedBox(height: 10),
            Text('No reviews yet — be the first!',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ]),
        ))
      else
        ..._reviews.map((r) => _buildReviewCard(r)),
    ]);
  }

  String _starKey(int star) =>
      ['zero', 'one', 'two', 'three', 'four', 'five'][star];

  Widget _buildWriteReviewCard() {
    final isLoggedIn = _supabase.auth.currentUser != null;
    final isEditing  = _myReviewId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.rate_review_rounded, size: 18,
              color: Color(0xFF0891B2)),
          const SizedBox(width: 8),
          Text(isEditing ? 'Edit your review' : 'Write a review',
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const Spacer(),
          if (isEditing)
            GestureDetector(
              onTap: _deleteReview,
              child: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: Color(0xFFEF4444)),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: List.generate(5, (i) {
          final filled = i < _draftStars;
          return GestureDetector(
            onTap: isLoggedIn
                ? () {
                    setState(() => _draftStars = i + 1);
                    HapticFeedback.lightImpact();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: filled
                    ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                size: 32,
              ),
            ),
          );
        })),
        const SizedBox(height: 12),
        TextField(
          controller:  _draftCtrl,
          enabled:     isLoggedIn,
          maxLines:    3,
          maxLength:   300,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: isLoggedIn
                ? 'Share your experience with this service...'
                : 'Log in to leave a review',
            hintStyle: const TextStyle(
                color: Color(0xFF94A3B8), fontSize: 13),
            filled:        true,
            fillColor:     Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: Color(0xFF0891B2), width: 2)),
            contentPadding: const EdgeInsets.all(12),
            counterStyle: const TextStyle(
                fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 44,
          child: ElevatedButton(
            onPressed: isLoggedIn && !_submitting ? _submitReview : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0891B2),
              disabledBackgroundColor: const Color(0xFFCBD5E1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _submitting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(
                    isEditing ? 'Update Review' : 'Submit Review',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
          ),
        ),
        if (!isLoggedIn) ...[
          const SizedBox(height: 8),
          const Center(child: Text('You must be logged in to review',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11))),
        ],
      ]),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> r) {
    final uid      = _supabase.auth.currentUser?.id;
    final isOwn    = r['user_id'] == uid;
    final fullName = (r['full_name'] as String?) ?? 'User';
    final initials = fullName.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2)
        .map((w) => w[0].toUpperCase()).join();
    final stars    = (r['stars'] as num).toInt();
    final text     = r['text'] as String;
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    final dateStr  = createdAt != null ? _formatDate(createdAt) : '';
    final colors   = [
      0xFF06B6D4, 0xFF7C3AED, 0xFFDB2777,
      0xFF059669, 0xFFD97706, 0xFFDC2626
    ];
    final avatarColor =
        Color(colors[fullName.codeUnitAt(0) % colors.length]);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOwn ? const Color(0xFFECFEFF) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwn
              ? const Color(0xFFA5F3FC) : const Color(0xFFF1F5F9),
          width: isOwn ? 1.5 : 1.0,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(11)),
            child: Center(child: Text(initials,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 11))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(fullName, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13)),
              if (isOwn) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0891B2),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('You',
                      style: TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.w900)),
                ),
              ],
            ]),
            Text(dateStr, style: const TextStyle(
                color: Color(0xFF94A3B8), fontSize: 11)),
          ])),
          _stars(stars, 12),
        ]),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(
            color: Color(0xFF64748B), fontSize: 13, height: 1.6)),
      ]),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ── ABOUT TAB ────────────────────────────────────────────────────────────
  Widget _buildAbout(Map<String, dynamic> svc, Color accent) {
    final dur  = (svc['duration_minutes'] as num).toInt();
    final desc = svc['description'] as String? ??
        'Professional cleaning by verified experts. We bring all necessary '
        'equipment and eco-friendly products — leaving your space spotless.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('About this service',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A))),
      const SizedBox(height: 8),
      Text(desc, style: const TextStyle(
          color: Color(0xFF64748B), fontSize: 14, height: 1.75)),
      const SizedBox(height: 22),
      const Text('What to expect',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A))),
      const SizedBox(height: 12),
      ...['Verified & background-checked professional',
          'All cleaning equipment provided',
          'Eco-friendly cleaning products',
          '$dur minute estimated duration']
          .map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(width: 22, height: 22,
                decoration: BoxDecoration(
                    color: accent, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 13)),
              const SizedBox(width: 12),
              Expanded(child: Text(item,
                  style: const TextStyle(color: Color(0xFF374151),
                      fontSize: 13, fontWeight: FontWeight.w500))),
            ]),
          )),
      const SizedBox(height: 20),
      const Text('Why choose us',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A))),
      const SizedBox(height: 12),
      GridView.count(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 2.8,
        children: _whyUs.map((b) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Color(b['bg'] as int),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(b['border'] as int)),
          ),
          child: Row(children: [
            Text(b['icon'] as String,
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(b['title'] as String, style: TextStyle(
                  color: Color(b['text'] as int),
                  fontSize: 11, fontWeight: FontWeight.w800)),
              Text(b['sub'] as String, style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 10)),
            ])),
          ]),
        )).toList(),
      ),
    ]);
  }

  // ── INCLUDES TAB ─────────────────────────────────────────────────────────
  Widget _buildIncludes(Map<String, dynamic> svc) {
    final inc = (svc['includes'] as List?)?.cast<String>() ?? [];
    final exc = (svc['excludes'] as List?)?.cast<String>() ?? [];
    if (inc.isEmpty && exc.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Column(children: [
          Text('📋', style: TextStyle(fontSize: 38)),
          SizedBox(height: 10),
          Text('No details yet',
              style: TextStyle(color: Color(0xFF94A3B8))),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (inc.isNotEmpty) ...[
        const Text("✅  What's Included",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        ...inc.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(children: [
            Container(width: 22, height: 22,
              decoration: const BoxDecoration(
                  color: Color(0xFF10B981), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 13)),
            const SizedBox(width: 12),
            Expanded(child: Text(item, style: const TextStyle(
                color: Color(0xFF065F46),
                fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        )),
        const SizedBox(height: 16),
      ],
      if (exc.isNotEmpty) ...[
        const Text("❌  Not Included",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        ...exc.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(children: [
            Container(width: 22, height: 22,
              decoration: const BoxDecoration(
                  color: Color(0xFFEF4444), shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 13)),
            const SizedBox(width: 12),
            Expanded(child: Text(item, style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        )),
      ],
    ]);
  }

  // ── BOTTOM BAR ───────────────────────────────────────────────────────────
  Widget _buildBottomBar(Map<String, dynamic> svc,
      Color c1, Color c2, int price) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 24, offset: const Offset(0, -6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STARTING FROM',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 0.7)),
              Text('₹$price', style: const TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w900, color: Color(0xFF0F172A),
                  height: 1.1)),
            ]),
            Row(children: [
              _stars(5, 10),
              const SizedBox(width: 4),
              const Text('4.8 · 2K+', style: TextStyle(
                  color: Color(0xFF64748B), fontSize: 11,
                  fontWeight: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => _navigate('schedule'),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c1, width: 2),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.calendar_month_rounded, color: c1, size: 17),
                  const SizedBox(width: 5),
                  Text('Schedule', style: TextStyle(
                      color: c1, fontSize: 13,
                      fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: GestureDetector(
              onTap: () => _navigate('instant'),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c1, c2]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: c1.withOpacity(0.45),
                      blurRadius: 16, offset: const Offset(0, 5))],
                ),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text('Book Instant', style: TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
          ]),
        ]),
      ),
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────────────────
  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.20),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.20)),
    ),
    child: Text(text, style: const TextStyle(
        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _avatarCircle(String initials, Color color, double left) =>
      Positioned(
        left: left,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2)),
          child: Center(child: Text(initials,
              style: const TextStyle(color: Colors.white,
                  fontSize: 9, fontWeight: FontWeight.w900))),
        ),
      );

  Widget _statChip(String val, String mid, String lbl,
      Color bg, Color border, Color col) =>
      Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.5)),
        child: Column(children: [
          Text(val, style: TextStyle(color: col, fontSize: 20,
              fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(height: 2),
          Text(mid, style: TextStyle(
              color: col.withOpacity(0.6), fontSize: 9)),
          const SizedBox(height: 2),
          Text(lbl, style: TextStyle(color: col, fontSize: 10,
              fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _stars(int n, double size) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (i) => Icon(Icons.star_rounded,
        color: i < n
            ? const Color(0xFFF59E0B) : const Color(0xFFE5E7EB),
        size: size)),
  );
}