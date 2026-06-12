import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final _supabase  = Supabase.instance.client;
  final _promoCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<Map<String, dynamic>> _promos       = [];
  List<Map<String, dynamic>> _usedPromos   = []; // promos this user already used (with full details)
  Set<String>                _usedPromoIds = {}; // promo ids this user already used
  String? _copiedCode;
  String? _promoMsg;
  bool    _promoSuccess = false;
  bool    _loading      = true;
  bool    _applying     = false;

  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _promoCtrl.dispose(); _focusNode.dispose(); super.dispose(); }

  // ── Helpers ─────────────────────────────────────────────────
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

  // Has THIS user already used this promo?
  bool _isUsedByMe(Map<String, dynamic> p) => _usedPromoIds.contains(p['id'].toString());

  bool _isExpiringSoon(Map<String, dynamic> p) {
    if (p['valid_until'] == null) return false;
    final d = DateTime.tryParse(p['valid_until'].toString());
    return d != null && d.difference(DateTime.now()).inDays <= 3;
  }

  String _discountLabel(Map<String, dynamic> p) {
    final type  = p['discount_type'] as String? ?? 'percent';
    final value = (p['discount_value'] as num? ?? 0).toDouble();
    return type == 'percent' ? '${value.toStringAsFixed(0)}%' : '₹${value.toStringAsFixed(0)}';
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
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ── Load promos + this user's usage ─────────────────────────
  Future<void> _load() async {
    try {
      // 1. Load all active promo codes
      final promoData = await _supabase
          .from('promo_codes')
          .select('*')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final allActive = (promoData as List).cast<Map<String, dynamic>>();

      // 2. Load which promos THIS user has already used (with used_at timestamp)
      Set<String> usedIds = {};
      Map<String, String> usedAtMap = {}; // promoId → used_at
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

        // Fetch full promo details for used ones (even if expired/exhausted)
        if (usedIds.isNotEmpty) {
          final usedPromoData = await _supabase
              .from('promo_codes')
              .select('*')
              .inFilter('id', usedIds.toList());
          usedPromos = (usedPromoData as List).cast<Map<String, dynamic>>();
          // Attach used_at to each used promo for display
          for (final p in usedPromos) {
            p['_used_at'] = usedAtMap[p['id'].toString()];
          }
        }
      }

      // 3. Available = active promos NOT used by this user, not expired, not exhausted
      final available = allActive
          .where((p) =>
              !usedIds.contains(p['id'].toString()) &&
              !_isExpired(p) &&
              !_isExhausted(p) &&
              !_isNotStarted(p))
          .toList();

      if (mounted) setState(() {
        _promos       = available;
        _usedPromos   = usedPromos;
        _usedPromoIds = usedIds;
        _loading      = false;
      });
    } catch (_) {
      if (mounted) setState(() { _promos = []; _loading = false; });
    }
  }

  // ── Copy code ────────────────────────────────────────────────
  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _copiedCode = code);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedCode = null);
    });
  }

  // ── Apply promo — validates + checks per-user usage ─────────
  Future<void> _applyPromo() async {
    final input = _promoCtrl.text.trim().toUpperCase();
    if (input.isEmpty) return;
    _focusNode.unfocus();
    setState(() { _applying = true; _promoMsg = null; });

    try {
      // 1. Fetch promo from Supabase
      final result = await _supabase
          .from('promo_codes')
          .select('*')
          .eq('code', input)
          .maybeSingle();

      if (result == null) {
        _showMsg(false, '❌ Invalid promo code. Please check and try again.'); return;
      }

      // 2. Check active
      if (result['is_active'] != true) {
        _showMsg(false, '⏸ This promo code is currently paused.'); return;
      }

      // 3. Check valid_from
      if (_isNotStarted(result)) {
        final d = DateTime.parse(result['valid_from'].toString());
        _showMsg(false, '⏰ This promo starts on ${_dateLabel(d)}. Check back then!'); return;
      }

      // 4. Check expiry
      if (_isExpired(result)) {
        _showMsg(false, '⏰ This promo code has expired.'); return;
      }

      // 5. Check global usage exhausted
      if (_isExhausted(result)) {
        _showMsg(false, '✕ This promo code has been fully used up.'); return;
      }

      // 6. ✅ Check if THIS user already used it
      if (_userId != null) {
        final existing = await _supabase
            .from('promo_usage')
            .select('id')
            .eq('promo_id', result['id'].toString())
            .eq('user_id', _userId!)
            .maybeSingle();

        if (existing != null) {
          _showMsg(false,
            '🚫 You have already used this promo code.\nEach code can only be used once per account.');
          return;
        }
      }

      // 7. ✅ All checks passed — record usage + increment used_count
      if (_userId != null) {
        // record usage for this user
        await _supabase.from('promo_usage').insert({
          'promo_id': result['id'].toString(),
          'user_id':  _userId!,
        });

        // increment global used_count
        final currentUsed = (result['used_count'] as num? ?? 0).toInt();
        await _supabase
            .from('promo_codes')
            .update({ 'used_count': currentUsed + 1 })
            .eq('id', result['id'].toString());

        // mark locally as used
        setState(() => _usedPromoIds.add(result['id'].toString()));
      }

      // 8. Build success message
      final discType  = result['discount_type'] as String? ?? 'percent';
      final discValue = (result['discount_value'] as num? ?? 0).toDouble();
      final minOrder  = result['min_order_amount'] != null
          ? (result['min_order_amount'] as num).toDouble() : null;
      final maxDisc   = result['max_discount_amount'] != null
          ? (result['max_discount_amount'] as num).toDouble() : null;
      final desc      = result['description'] as String?;

      String discLabel = discType == 'percent'
          ? '${discValue.toStringAsFixed(0)}% off'
          : '₹${discValue.toStringAsFixed(0)} off';
      if (maxDisc != null && discType == 'percent')
        discLabel += ' (max ₹${maxDisc.toStringAsFixed(0)})';

      String msg = (desc != null && desc.isNotEmpty)
          ? '🎉 $desc'
          : '🎉 "$input" applied! $discLabel';
      if (minOrder != null) msg += '\n📋 Min order: ₹${minOrder.toStringAsFixed(0)}';

      _showMsg(true, msg);

      // reload to reflect updated counts
      _load();

    } catch (e) {
      _showMsg(false, '❌ Could not verify code. Check your connection.');
    }
  }

  void _showMsg(bool success, String msg) {
    if (mounted) setState(() {
      _promoSuccess = success;
      _promoMsg     = msg;
      _applying     = false;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _promoMsg = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: const Color(0xFF6366F1),
            leading: IconButton(
              icon: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF4F46E5), Color(0xFF0EA5E9)]),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('CLEENZO REWARDS',
                          style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 11,
                              fontWeight: FontWeight.w700, letterSpacing: 2)),
                        const SizedBox(height: 4),
                        const Row(children: [
                          Text('Offers & Coupons ',
                            style: TextStyle(color: Colors.white,
                                fontSize: 22, fontWeight: FontWeight.bold)),
                          Text('🎟', style: TextStyle(fontSize: 20)),
                        ]),
                        Text(
                          _loading
                              ? 'Loading offers…'
                              : '${_promos.length} offer${_promos.length == 1 ? '' : 's'} available',
                          style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Promo Input ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFEEF2FF)),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.07),
                      blurRadius: 12)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(10)),
                          child: const Center(child: Text('✍️', style: TextStyle(fontSize: 16))),
                        ),
                        const SizedBox(width: 10),
                        const Text('Have a promo code?',
                          style: TextStyle(color: Color(0xFF374151),
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _promoCtrl,
                            focusNode: _focusNode,
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _applyPromo(),
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.5,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'e.g. FIRST20',
                              hintStyle: const TextStyle(
                                color: Color(0xFFD1D5DB),
                                fontWeight: FontWeight.normal,
                                letterSpacing: 0,
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF5F3FF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFE0E7FF))),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFE0E7FF))),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                    color: Color(0xFF6366F1), width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              suffixIcon: _promoCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 18, color: Color(0xFF9CA3AF)),
                                      onPressed: () {
                                        _promoCtrl.clear();
                                        setState(() { _promoMsg = null; });
                                      })
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _applying ? null : _applyPromo,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: _applying
                                  ? const Color(0xFF818CF8)
                                  : const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.35),
                                blurRadius: 12)],
                            ),
                            child: Center(
                              child: _applying
                                  ? const SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5))
                                  : const Text('Apply',
                                      style: TextStyle(color: Colors.white,
                                          fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ),
                        ),
                      ]),

                      // result message
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: _promoMsg != null
                            ? Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _promoSuccess
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _promoSuccess
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5)),
                                ),
                                child: Text(_promoMsg!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _promoSuccess
                                        ? const Color(0xFF059669)
                                        : const Color(0xFFDC2626),
                                    height: 1.5,
                                  )),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF6366F1))))

                else if (_promos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Column(children: [
                      Text('🎟', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('No offers right now',
                        style: TextStyle(color: Color(0xFF374151),
                            fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Check back soon for exciting deals!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                    ]),
                  )

                else ..._buildPromoList(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build promo list (extracted to avoid final-in-spread error) ──
  List<Widget> _buildPromoList() {
    final widgets = <Widget>[];

    // ── Available promos ──────────────────────────────────────
    if (_promos.isNotEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.only(bottom: 12, left: 4),
        child: Text('AVAILABLE FOR YOU',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ));
      for (final p in _promos) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _PromoCard(
            promo:          p,
            discountLabel:  _discountLabel(p),
            expiryLabel:    _expiryLabel(p),
            expiringSoon:   _isExpiringSoon(p),
            effectiveLimit: _effectiveLimit(p),
            usedByMe:       false,
            usedAt:         null,
            copiedCode:     _copiedCode,
            onCopy:         _copyCode,
            onTapApply: () {
              _promoCtrl.text = p['code'] as String;
              setState(() {});
              _applyPromo();
            },
          ),
        ));
      }
    }

    // ── Already used promos ───────────────────────────────────
    if (_usedPromos.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8, left: 4),
        child: Row(children: const [
          Text('ALREADY USED',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          SizedBox(width: 8),
          Text('• One use per account',
            style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 10)),
        ]),
      ));
      for (final p in _usedPromos) {
        final usedAt = p['_used_at'] as String?;
        widgets.add(Padding(
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
              usedAt:         usedAt,
              copiedCode:     null,
              onCopy:         (_) async {},
              onTapApply:     () {},
            ),
          ),
        ));
      }
    }

    return widgets;
  }
}

// ── Promo Card ──────────────────────────────────────────────────
class _PromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final String  discountLabel;
  final String  expiryLabel;
  final bool    expiringSoon;
  final int?    effectiveLimit;
  final bool    usedByMe;
  final String? usedAt;     // ISO timestamp when this user used it
  final String? copiedCode;
  final Future<void> Function(String) onCopy;
  final VoidCallback onTapApply;

  const _PromoCard({
    required this.promo,
    required this.discountLabel,
    required this.expiryLabel,
    required this.expiringSoon,
    required this.effectiveLimit,
    required this.usedByMe,
    required this.usedAt,
    required this.copiedCode,
    required this.onCopy,
    required this.onTapApply,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: usedByMe
              ? Colors.black.withOpacity(0.04)
              : const Color(0xFF6366F1).withOpacity(0.08),
          blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Left discount strip ──────────────────────────
            Container(
              width: 88,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: usedByMe
                      ? [const Color(0xFF94A3B8), const Color(0xFF64748B)]
                      : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (usedByMe) ...[
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
                  const SizedBox(height: 4),
                  const Text('USED', style: TextStyle(color: Color(0xFFE2E8F0),
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ] else ...[
                  Text(discountLabel,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 24, fontWeight: FontWeight.w900)),
                  const Text('OFF', style: TextStyle(color: Color(0xFFC7D2FE),
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  if (isPercent && maxDisc != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('max ₹$maxDisc',
                        style: const TextStyle(color: Color(0xFFE0E7FF),
                            fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ]),
            ),

            // notch divider
            Stack(clipBehavior: Clip.none, children: [
              Container(width: 1, color: const Color(0xFFE0E7FF)),
              Positioned(top: -10, left: -10,
                child: Container(width: 20, height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F4FF), shape: BoxShape.circle))),
              Positioned(bottom: -10, left: -10,
                child: Container(width: 20, height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F4FF), shape: BoxShape.circle))),
            ]),

            // ── Right content ────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // used banner
                  if (usedByMe)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.check_circle_outline_rounded,
                          size: 12, color: Color(0xFF64748B)),
                        SizedBox(width: 5),
                        Text('You\'ve already used this code',
                          style: TextStyle(color: Color(0xFF64748B),
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),

                  // description
                  if (desc.isNotEmpty)
                    Text(desc,
                      style: const TextStyle(color: Color(0xFF111827),
                          fontSize: 13, fontWeight: FontWeight.bold, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),

                  // tags
                  const SizedBox(height: 7),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (minOrder != null)
                      _Tag('Min ₹$minOrder',
                        const Color(0xFFFFF7ED), const Color(0xFFFED7AA), const Color(0xFFD97706)),
                    if (effectiveLimit != null && !usedByMe)
                      _Tag('${effectiveLimit! - usedCount} left',
                        const Color(0xFFF5F3FF), const Color(0xFFDDD6FE), const Color(0xFF7C3AED)),
                    if (expiringSoon && !usedByMe)
                      _Tag('⚡ Ending soon',
                        const Color(0xFFFEF2F2), const Color(0xFFFCA5A5), const Color(0xFFDC2626)),
                  ]),

                  // expiry
                  const SizedBox(height: 6),
                  Text(expiryLabel,
                    style: TextStyle(
                      color: expiringSoon && !usedByMe
                          ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB),
                      fontSize: 10,
                      fontWeight: expiringSoon && !usedByMe
                          ? FontWeight.bold : FontWeight.normal)),

                  const SizedBox(height: 10),

                  // code chip + buttons
                  Row(children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: usedByMe
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFFF5F3FF),
                          border: Border.all(
                            color: usedByMe
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFFC4B5FD)),
                          borderRadius: BorderRadius.circular(10)),
                        child: Text(code,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: usedByMe
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF6366F1),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            decoration: usedByMe ? TextDecoration.lineThrough : null)),
                      ),
                    ),
                    if (!usedByMe) ...[
                      const SizedBox(width: 6),
                      // copy
                      GestureDetector(
                        onTap: () => onCopy(code),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isCopied
                                ? const Color(0xFF10B981) : const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(isCopied ? Icons.check_rounded : Icons.copy_rounded,
                              color: isCopied ? Colors.white : const Color(0xFF6366F1),
                              size: 13),
                            const SizedBox(width: 4),
                            Text(isCopied ? 'Copied' : 'Copy',
                              style: TextStyle(
                                color: isCopied ? Colors.white : const Color(0xFF6366F1),
                                fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // apply
                      GestureDetector(
                        onTap: onTapApply,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.3),
                              blurRadius: 8)]),
                          child: const Text('Apply',
                            style: TextStyle(color: Colors.white,
                                fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ]),
                ]),
              ),
            ),
          ]),
        ),

        // ── Usage bar ──────────────────────────────────────────
        if (effectiveLimit != null) ...[
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$usedCount used of $effectiveLimit',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
                Text(
                  '${((usedCount / effectiveLimit!) * 100).clamp(0, 100).toStringAsFixed(0)}% claimed',
                  style: TextStyle(
                    color: (usedCount / effectiveLimit!) > 0.8
                        ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF),
                    fontSize: 10, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (usedCount / effectiveLimit!).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    (usedCount / effectiveLimit!) > 0.8
                        ? const Color(0xFFEF4444) : const Color(0xFF6366F1)),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Tag chip ────────────────────────────────────────────────────
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
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}