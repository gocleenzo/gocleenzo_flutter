import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen>
    with TickerProviderStateMixin {
  final _supabase  = Supabase.instance.client;

  late AnimationController _headerAnimCtrl;
  late AnimationController _shimmerCtrl;
  late Animation<double>   _headerFade;
  late Animation<Offset>   _headerSlide;
  late Animation<double>   _shimmerAnim;

  List<Map<String, dynamic>> _promos       = [];
  List<Map<String, dynamic>> _usedPromos   = [];
  Set<String>                _usedPromoIds = {};
  String? _copiedCode;
  bool    _loading      = true;

  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();

    _headerAnimCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
    _headerFade  = CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOutCubic));

    _shimmerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _shimmerAnim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    _headerAnimCtrl.forward();
    _load();
  }

  @override
  void dispose() {
    _headerAnimCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────

  int? _effectiveLimit(Map<String, dynamic> p) {
    if (p['usage_limit'] != null) return (p['usage_limit'] as num).toInt();
    if (p['max_uses']    != null) return (p['max_uses']    as num).toInt();
    return null;
  }

  bool _isExpired(Map<String, dynamic> p) {
    if (p['valid_until'] == null) return false;
    final d = DateTime.tryParse(p['valid_until'].toString());
    return d != null && d.isBefore(DateTime.now());
  }

  bool _isNotStarted(Map<String, dynamic> p) {
    if (p['valid_from'] == null) return false;
    final d = DateTime.tryParse(p['valid_from'].toString());
    return d != null && d.isAfter(DateTime.now());
  }

  bool _isExhausted(Map<String, dynamic> p) {
    final limit = _effectiveLimit(p);
    if (limit == null) return false;
    return (p['used_count'] as num? ?? 0).toInt() >= limit;
  }

  bool _isUsedByMe(Map<String, dynamic> p) =>
      _usedPromoIds.contains(p['id'].toString());

  bool _isExpiringSoon(Map<String, dynamic> p) {
    if (p['valid_until'] == null) return false;
    final d = DateTime.tryParse(p['valid_until'].toString());
    return d != null && d.difference(DateTime.now()).inDays <= 3;
  }

  String _discountLabel(Map<String, dynamic> p) {
    final type  = p['discount_type'] as String? ?? 'percent';
    final value = (p['discount_value'] as num? ?? 0).toDouble();
    return type == 'percent'
        ? '${value.toStringAsFixed(0)}%'
        : '₹${value.toStringAsFixed(0)}';
  }

  String _expiryLabel(Map<String, dynamic> p) {
    if (p['valid_until'] == null) return 'No expiry';
    final d = DateTime.tryParse(p['valid_until'].toString());
    if (d == null) return '';
    final diff = d.difference(DateTime.now()).inDays;
    if (diff == 0) return '⚡ Expires today!';
    if (diff == 1) return '⚡ Expires tomorrow!';
    if (diff <= 3) return '⚡ Expires in $diff days';
    return 'Valid till ${_dateLabel(d)}';
  }

  String _dateLabel(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ── Load ──────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final promoData = await _supabase
          .from('promo_codes')
          .select('*')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final allActive = (promoData as List).cast<Map<String, dynamic>>();

      Set<String> usedIds = {};
      Map<String, String> usedAtMap = {};
      List<Map<String, dynamic>> usedPromos = [];

      if (_userId != null) {
        final usageData = await _supabase
            .from('promo_usage')
            .select('promo_id, used_at')
            .eq('user_id', _userId!)
            .order('used_at', ascending: false);

        final usageList = (usageData as List).cast<Map<String, dynamic>>();
        usedIds = usageList.map((r) => r['promo_id'].toString()).toSet();
        for (final u in usageList) {
          usedAtMap[u['promo_id'].toString()] = u['used_at'].toString();
        }

        if (usedIds.isNotEmpty) {
          final usedPromoData = await _supabase
              .from('promo_codes')
              .select('*')
              .inFilter('id', usedIds.toList());
          usedPromos = (usedPromoData as List).cast<Map<String, dynamic>>();
          for (final p in usedPromos) {
            p['_used_at'] = usedAtMap[p['id'].toString()];
          }
        }
      }

      final available = allActive
          .where((p) =>
              !usedIds.contains(p['id'].toString()) &&
              !_isExpired(p) &&
              !_isExhausted(p) &&
              !_isNotStarted(p))
          .toList();

      if (mounted) {
        setState(() {
          _promos       = available;
          _usedPromos   = usedPromos;
          _usedPromoIds = usedIds;
          _loading      = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _promos = []; _loading = false; });
    }
  }

  // ── Copy ──────────────────────────────────────────────────────

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _copiedCode = code);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedCode = null);
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDFF),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? _buildShimmerList()
                : CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            if (_promos.isEmpty && _usedPromos.isEmpty)
                              _buildEmptyState()
                            else
                              ..._buildPromoList(),
                          ]),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader() {
    return SlideTransition(
      position: _headerSlide,
      child: FadeTransition(
        opacity: _headerFade,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0891B2), Color(0xFF06B6D4), Color(0xFF22D3EE)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      // Back button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.25), width: 1),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 16),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CLEENZO REWARDS',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                            const Row(children: [
                              Text('Offers & Coupons',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                )),
                              SizedBox(width: 6),
                              Text('🎟', style: TextStyle(fontSize: 20)),
                            ]),
                          ],
                        ),
                      ),
                      // Refresh
                      GestureDetector(
                        onTap: _load,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.25), width: 1),
                          ),
                          child: const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Stats row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    _statPill('${_promos.length}', 'Available', Icons.local_offer_outlined),
                    const SizedBox(width: 10),
                    _statPill('${_usedPromos.length}', 'Used', Icons.check_circle_outline),
                  ]),
                ),
                const SizedBox(height: 14),
                // Wave bottom
                ClipPath(
                  clipper: _WaveClipper(),
                  child: Container(height: 22, color: const Color(0xFFF0FDFF)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statPill(String count, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(count,
              style: const TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w900)),
            Text(label,
              style: TextStyle(color: Colors.white.withOpacity(0.75),
                  fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  // ── Promo List ────────────────────────────────────────────────

  List<Widget> _buildPromoList() {
    final widgets = <Widget>[];
    int delay = 0;

    if (_promos.isNotEmpty) {
      widgets.add(_sectionLabel('🎁  AVAILABLE FOR YOU'));
      for (final p in _promos) {
        widgets.add(_AnimatedCard(
          delay: Duration(milliseconds: delay),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _PromoCard(
              promo:          p,
              discountLabel:  _discountLabel(p),
              expiryLabel:    _expiryLabel(p),
              expiringSoon:   _isExpiringSoon(p),
              effectiveLimit: _effectiveLimit(p),
              usedByMe:       false,
              copiedCode:     _copiedCode,
              onCopy:         _copyCode,
            ),
          ),
        ));
        delay += 60;
      }
    }

    if (_usedPromos.isNotEmpty) {
      widgets.add(_sectionLabel('✅  ALREADY USED'));
      for (final p in _usedPromos) {
        widgets.add(_AnimatedCard(
          delay: Duration(milliseconds: delay),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Opacity(
              opacity: 0.65,
              child: _PromoCard(
                promo:          p,
                discountLabel:  _discountLabel(p),
                expiryLabel:    _expiryLabel(p),
                expiringSoon:   false,
                effectiveLimit: _effectiveLimit(p),
                usedByMe:       true,
                copiedCode:     null,
                onCopy:         (_) async {},
              ),
            ),
          ),
        ));
        delay += 60;
      }
    }

    return widgets;
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4, left: 4),
    child: Text(text,
      style: const TextStyle(
        color: Color(0xFF0891B2),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      )),
  );

  // ── Empty State ───────────────────────────────────────────────

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(children: [
      Stack(alignment: Alignment.center, children: [
        Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFFCFFAFE),
            borderRadius: BorderRadius.circular(40)),
        ),
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F7FF),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5)),
        ),
        const Text('🎟', style: TextStyle(fontSize: 40)),
      ]),
      const SizedBox(height: 20),
      const Text('No offers right now',
        style: TextStyle(
          color: Color(0xFF0E7490),
          fontSize: 18, fontWeight: FontWeight.w900,
          letterSpacing: -0.3)),
      const SizedBox(height: 8),
      const Text('Check back soon for exciting deals!',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5, height: 1.5)),
    ]),
  );

  // ── Shimmer ───────────────────────────────────────────────────

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(
            color: const Color(0xFF06B6D4).withOpacity(0.06),
            blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AnimatedBuilder(
            animation: _shimmerAnim,
            builder: (_, __) => ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0xFFE0F7FF), Color(0xFFF0FDFF),
                  Color(0xFFBAE6FD), Color(0xFFF0FDFF), Color(0xFFE0F7FF),
                ],
                stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                transform: _SlidingGradientTransform(_shimmerAnim.value),
              ).createShader(bounds),
              child: Container(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Promo Card ────────────────────────────────────────────────────────────────

class _PromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final String  discountLabel;
  final String  expiryLabel;
  final bool    expiringSoon;
  final int?    effectiveLimit;
  final bool    usedByMe;
  final String? copiedCode;
  final Future<void> Function(String) onCopy;

  const _PromoCard({
    required this.promo,
    required this.discountLabel,
    required this.expiryLabel,
    required this.expiringSoon,
    required this.effectiveLimit,
    required this.usedByMe,
    required this.copiedCode,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final code      = promo['code'] as String;
    final isCopied  = copiedCode == code;
    final isPercent = (promo['discount_type'] as String?) == 'percent';
    final desc      = promo['description'] as String? ?? '';
    final minOrder  = promo['min_order_amount'];
    final maxDisc   = promo['max_discount_amount'];
    final usedCount = (promo['used_count'] as num? ?? 0).toInt();

    // Colors based on state
    final accentColor = usedByMe
        ? const Color(0xFF94A3B8)
        : const Color(0xFF06B6D4);
    final accentDark  = usedByMe
        ? const Color(0xFF64748B)
        : const Color(0xFF0891B2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: usedByMe
              ? const Color(0xFFE2E8F0)
              : const Color(0xFFBAE6FD),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: usedByMe
                ? Colors.black.withOpacity(0.04)
                : const Color(0xFF06B6D4).withOpacity(0.09),
            blurRadius: 18, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

            // ── Left discount strip ───────────────────────────
            Container(
              width: 90,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: usedByMe
                      ? [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)]
                      : [const Color(0xFF06B6D4), const Color(0xFF0891B2)],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  bottomLeft: Radius.circular(22)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (usedByMe) ...[
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 30),
                  const SizedBox(height: 5),
                  const Text('USED',
                    style: TextStyle(color: Color(0xFFE2E8F0),
                        fontSize: 10, fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
                ] else ...[
                  Text(discountLabel,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 24, fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)),
                  const Text('OFF',
                    style: TextStyle(color: Color(0xFFBAE6FD),
                        fontSize: 10, fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
                  if (isPercent && maxDisc != null) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('max ₹$maxDisc',
                        style: const TextStyle(color: Color(0xFFE0F7FF),
                            fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ]),
            ),

            // notch divider
            Stack(clipBehavior: Clip.none, children: [
              Container(width: 1,
                color: usedByMe
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFBAE6FD)),
              Positioned(top: -10, left: -10,
                child: Container(width: 20, height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDFF), shape: BoxShape.circle))),
              Positioned(bottom: -10, left: -10,
                child: Container(width: 20, height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDFF), shape: BoxShape.circle))),
            ]),

            // ── Right content ─────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Used banner
                    if (usedByMe)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.check_circle_outline_rounded,
                            size: 12, color: Color(0xFF64748B)),
                          SizedBox(width: 5),
                          Text('Already used · one use per account',
                            style: TextStyle(color: Color(0xFF64748B),
                                fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      ),

                    // Description
                    if (desc.isNotEmpty)
                      Text(desc,
                        style: TextStyle(
                          color: usedByMe
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF0E4F5C),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),

                    const SizedBox(height: 8),

                    // Tags
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (minOrder != null)
                        _Tag('Min ₹$minOrder',
                          const Color(0xFFFFF7ED),
                          const Color(0xFFFED7AA),
                          const Color(0xFFD97706)),
                      if (effectiveLimit != null && !usedByMe)
                        _Tag('${effectiveLimit! - usedCount} left',
                          const Color(0xFFECFEFF),
                          const Color(0xFFBAE6FD),
                          const Color(0xFF0891B2)),
                      if (expiringSoon && !usedByMe)
                        _Tag('⚡ Ending soon',
                          const Color(0xFFFEF2F2),
                          const Color(0xFFFCA5A5),
                          const Color(0xFFDC2626)),
                    ]),

                    // Expiry
                    const SizedBox(height: 6),
                    Text(expiryLabel,
                      style: TextStyle(
                        color: expiringSoon && !usedByMe
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: expiringSoon && !usedByMe
                            ? FontWeight.bold : FontWeight.normal)),

                    const SizedBox(height: 10),

                    // Code chip + copy button
                    Row(children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: usedByMe
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFFECFEFF),
                            border: Border.all(
                              color: usedByMe
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFFBAE6FD)),
                            borderRadius: BorderRadius.circular(10)),
                          child: Text(code,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: usedByMe
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF0891B2),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              decoration: usedByMe
                                  ? TextDecoration.lineThrough : null)),
                        ),
                      ),
                      if (!usedByMe) ...[
                        const SizedBox(width: 6),
                        // Copy
                        GestureDetector(
                          onTap: () => onCopy(code),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isCopied
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFECFEFF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCopied
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFBAE6FD)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                isCopied
                                    ? Icons.check_rounded
                                    : Icons.copy_rounded,
                                color: isCopied
                                    ? Colors.white
                                    : const Color(0xFF0891B2),
                                size: 13),
                              const SizedBox(width: 4),
                              Text(isCopied ? 'Copied' : 'Copy',
                                style: TextStyle(
                                  color: isCopied
                                      ? Colors.white
                                      : const Color(0xFF0891B2),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),

        // ── Usage progress bar ────────────────────────────────
        if (effectiveLimit != null) ...[
          Divider(height: 1,
            color: usedByMe
                ? const Color(0xFFF1F5F9)
                : const Color(0xFFE0F7FF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$usedCount used of $effectiveLimit',
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 10)),
                Text(
                  '${((usedCount / effectiveLimit!) * 100).clamp(0, 100).toStringAsFixed(0)}% claimed',
                  style: TextStyle(
                    color: (usedCount / effectiveLimit!) > 0.8
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0891B2),
                    fontSize: 10, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (usedCount / effectiveLimit!).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE0F7FF),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    (usedCount / effectiveLimit!) > 0.8
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF06B6D4)),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Tag chip ──────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String text;
  final Color bg, border, color;
  const _Tag(this.text, this.bg, this.border, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(8)),
    child: Text(text,
      style: TextStyle(
          color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}

// ── Wave Clipper ──────────────────────────────────────────────────────────────

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, 0);
    path.quadraticBezierTo(
        size.width / 4, size.height, size.width / 2, size.height * 0.5);
    path.quadraticBezierTo(
        3 * size.width / 4, 0, size.width, size.height * 0.5);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

// ── Staggered Animated Card ───────────────────────────────────────────────────

class _AnimatedCard extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _AnimatedCard({required this.child, required this.delay});

  @override
  State<_AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<_AnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
        begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(widget.delay, () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ── Shimmer Gradient Transform ────────────────────────────────────────────────

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
}