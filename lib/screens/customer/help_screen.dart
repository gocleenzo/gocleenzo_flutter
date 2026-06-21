import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  String? _openFaq;
  String _activeCategory = 'All';
  String _searchQuery = '';
  bool _submitted = false;
  bool _loading = false;
  String? _error;
  bool _showFab = false;

  late final AnimationController _shakeController;

  static const _faqs = [
    {
      'category': 'Bookings',
      'icon': '📋',
      'items': [
        {'q': 'How do I reschedule my booking?', 'a': 'You can reschedule up to 2 hours before scheduled time. Go to My Bookings, tap the booking, and select "Reschedule".'},
        {'q': 'Can I cancel my booking?', 'a': 'Yes, cancellations are free if done 4+ hours before service. Cancellations within 4 hours may attract a small convenience fee.'},
        {'q': "What if the professional doesn't show up?", 'a': "We'll reassign another professional immediately or give you a full refund. Contact us for instant resolution."},
      ],
    },
    {
      'category': 'Payments',
      'icon': '💳',
      'items': [
        {'q': 'What payment methods are accepted?', 'a': 'We accept UPI, credit/debit cards, net banking, and cash on service. All digital payments are 100% secure via Razorpay.'},
        {'q': 'When will I get my refund?', 'a': 'Refunds are processed within 5–7 business days to the original payment method. UPI refunds may be faster.'},
        {'q': 'Is my payment information safe?', 'a': 'Absolutely. We use industry-standard encryption and never store your card details on our servers.'},
      ],
    },
    {
      'category': 'Services',
      'icon': '🧹',
      'items': [
        {'q': 'What areas do you cover in Mumbai?', 'a': 'We currently cover Andheri and Vile Parle. Enter your pincode to check availability.'},
        {'q': 'Do I need to provide cleaning supplies?', 'a': 'No, our professionals bring all necessary equipment and eco-friendly cleaning products.'},
        {'q': 'Are your professionals verified?', 'a': 'Yes, all Cleenzo professionals undergo background checks, ID verification, and training before joining.'},
      ],
    },
  ];

  List<String> get _categories => ['All', ..._faqs.map((s) => s['category'] as String)];

  List<Map<String, dynamic>> get _filteredSections {
    final q = _searchQuery.trim().toLowerCase();
    return _faqs
        .where((s) => _activeCategory == 'All' || s['category'] == _activeCategory)
        .map((s) {
          final items = (s['items'] as List<Map<String, dynamic>>)
              .where((item) =>
                  q.isEmpty ||
                  item['q']!.toLowerCase().contains(q) ||
                  item['a']!.toLowerCase().contains(q))
              .toList();
          return {...s, 'items': items};
        })
        .where((s) => (s['items'] as List).isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scrollController.addListener(() {
      final show = _scrollController.offset > 320;
      if (show != _showFab) setState(() => _showFab = show);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _msgCtrl.dispose();
    _searchCtrl.dispose(); _scrollController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _msgCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all required fields');
      _shakeController.forward(from: 0);
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final session = _supabase.auth.currentSession;
      await _supabase.from('support_queries').insert({
        'name': _nameCtrl.text,
        'email': _emailCtrl.text,
        'phone': _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text,
        'message': _msgCtrl.text,
        'user_id': session?.user.id,
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      });
      HapticFeedback.lightImpact();
      setState(() { _submitted = true; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Something went wrong. Please try again.'; _loading = false; });
      _shakeController.forward(from: 0);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildHeroAppBar(),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // FAQ Section
                    const Center(child: Text('FAQ', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 3))),
                    const SizedBox(height: 8),
                    const Center(child: Text('Frequently asked questions', style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 22, fontWeight: FontWeight.w900))),
                    const SizedBox(height: 18),

                    _buildSearchBar(),
                    const SizedBox(height: 12),
                    _buildCategoryChips(),
                    const SizedBox(height: 20),

                    if (_filteredSections.isEmpty)
                      _buildNoResults()
                    else
                      ...List.generate(_filteredSections.length, (i) {
                        return _StaggeredEntry(
                          index: i,
                          child: _buildFaqSection(_filteredSections[i]),
                        );
                      }),
                    const SizedBox(height: 32),

                    // Contact section
                    const Center(child: Text('Still need help?', style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 22, fontWeight: FontWeight.w900))),
                    const SizedBox(height: 8),
                    const Center(child: Text("Can't find what you're looking for? Send us a message — we respond within 24 hours.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.6))),
                    const SizedBox(height: 24),

                    // Info cards
                    ...List.generate(2, (i) {
                      final item = [
                        {'icon': '📧', 'label': 'Email us', 'value': 'hello@cleenzo.in', 'sub': 'We reply within 24 hours'},
                        {'icon': '📍', 'label': 'Based in', 'value': 'Mumbai, Maharashtra', 'sub': 'Serving Andheri & Vile Parle'},
                      ][i];
                      return _StaggeredEntry(
                        index: i,
                        child: _buildInfoCard(item),
                      );
                    }),
                    const SizedBox(height: 24),

                    // Contact form
                    AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        final t = _shakeController.value;
                        final dx = (t == 0 || t == 1)
                            ? 0.0
                            : (4 * (0.5 - (t * 4).abs().clamp(0, 0.5))).toDouble();
                        return Transform.translate(offset: Offset(dx, 0), child: child);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 12))],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween(begin: 0.95, end: 1.0).animate(anim),
                              child: child,
                            ),
                          ),
                          child: _submitted
                              ? _buildSuccessState(key: const ValueKey('success'))
                              : _buildForm(key: const ValueKey('form')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 20,
            child: AnimatedSlide(
              offset: _showFab ? Offset.zero : const Offset(0, 2),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _showFab ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: FloatingActionButton.small(
                  backgroundColor: AppTheme.primary,
                  elevation: 3,
                  onPressed: _scrollToTop,
                  child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------

  Widget _buildHeroAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: const Color(0xFF0C4A6E),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFECFEFF), Color(0xFFE0F7FA)]),
          ),
          child: Stack(
            children: [
              Positioned(top: -80, right: -80, child: _PulsingCircle(size: 200, color: AppTheme.primary.withOpacity(0.12))),
              Positioned(bottom: -50, left: -50, child: _PulsingCircle(size: 140, color: AppTheme.primary.withOpacity(0.08), reverse: true)),
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    // FittedBox guarantees this block can never overflow the
                    // header, no matter the device height, status-bar size,
                    // or the user's system font-scale setting — it shrinks
                    // to fit instead of clipping/erroring.
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomCenter,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          builder: (context, v, child) => Opacity(
                            opacity: v,
                            child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('HELP CENTRE', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 3)),
                              SizedBox(height: 8),
                              Text('How can we\nhelp you?', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
                              SizedBox(height: 8),
                              Text('Find answers below or send us a message', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF374151), fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SEARCH + FILTER
  // ---------------------------------------------------------------------

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search for answers...',
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 22),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF9CA3AF)),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final active = _activeCategory == cat;
          return GestureDetector(
            onTap: () {
              setState(() => _activeCategory = cat);
              HapticFeedback.selectionClick();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppTheme.primary : const Color(0xFFF0FDFE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppTheme.primary : const Color(0xFFA5F3FC),
                ),
              ),
              child: Center(
                child: Text(
                  cat,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF0E7490),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text('No matching questions',
              style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Try a different search or browse all categories',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // FAQ SECTION
  // ---------------------------------------------------------------------

  Widget _buildFaqSection(Map<String, dynamic> section) {
    final items = section['items'] as List<Map<String, dynamic>>;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(children: [
              Text(section['icon'] as String, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(section['category'] as String, style: const TextStyle(color: Color(0xFF0C4A6E), fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${items.length}',
                    style: const TextStyle(color: Color(0xFF0E7490), fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const Divider(color: Color(0xFFF3F4F6), height: 1),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final faq = entry.value;
            final key = '${section['category']}-${faq['q']}';
            final isOpen = _openFaq == key;
            return Column(children: [
              GestureDetector(
                onTap: () => setState(() => _openFaq = isOpen ? null : key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  color: isOpen ? const Color(0xFFF8FEFF) : Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Row(children: [
                    Expanded(child: Text(faq['q']!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isOpen ? AppTheme.primary : const Color(0xFF1F2937)))),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(Icons.keyboard_arrow_down, color: AppTheme.primary),
                    ),
                  ]),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Container(
                  width: double.infinity,
                  color: const Color(0xFFF8FEFF),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(faq['a']!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.7)),
                ),
                crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
                sizeCurve: Curves.easeOutCubic,
              ),
              if (i < items.length - 1) const Divider(color: Color(0xFFF3F4F6), height: 1),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Map<String, String> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA5F3FC)),
      ),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.12), blurRadius: 8)]),
          child: Center(child: Text(item['icon']!, style: const TextStyle(fontSize: 20)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['label']!, style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          Text(item['value']!, style: const TextStyle(color: Color(0xFF0C4A6E), fontSize: 15, fontWeight: FontWeight.w600)),
          Text(item['sub']!, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
        ])),
      ]),
    );
  }

  // ---------------------------------------------------------------------
  // CONTACT FORM
  // ---------------------------------------------------------------------

  Widget _buildForm({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Send us a message', style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text("We'll respond within 24 hours.", style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _formField('YOUR NAME *', _nameCtrl, hint: 'Rahul Sharma')),
          const SizedBox(width: 12),
          Expanded(child: _formField('PHONE', _phoneCtrl, hint: '+91 98765 43210', type: TextInputType.phone)),
        ]),
        const SizedBox(height: 14),
        _formField('EMAIL ADDRESS *', _emailCtrl, hint: 'rahul@example.com', type: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _formField('YOUR MESSAGE *', _msgCtrl, hint: 'Tell us how we can help...', maxLines: 5),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                    ]),
                  ),
                ),
        ),
        const SizedBox(height: 20),
        _AnimatedSubmitButton(loading: _loading, onTap: _loading ? null : _submitForm),
      ],
    );
  }

  Widget _formField(String label, TextEditingController ctrl, {String hint = '', TextInputType? type, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF374151), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primary, width: 1.6)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState({Key? key}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 550),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Message sent!', style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Thanks for reaching out, ${_nameCtrl.text.split(' ').first}!\nWe\'ll get back to you at ${_emailCtrl.text} within 24 hours.',
          textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.6)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () {
            setState(() {
              _submitted = false;
              _nameCtrl.clear(); _emailCtrl.clear(); _phoneCtrl.clear(); _msgCtrl.clear();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFE),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFA5F3FC)),
            ),
            child: const Text('Send another message', style: TextStyle(color: Color(0xFF0E7490), fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// SMALL REUSABLE WIDGETS
/// ---------------------------------------------------------------------

class _PulsingCircle extends StatefulWidget {
  final double size;
  final Color color;
  final bool reverse;
  const _PulsingCircle({required this.size, required this.color, this.reverse = false});

  @override
  State<_PulsingCircle> createState() => _PulsingCircleState();
}

class _PulsingCircleState extends State<_PulsingCircle> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.reverse ? 4200 : 3400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final scale = 1.0 + (_c.value * 0.06);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}

/// Fades + slides each list item in with a small stagger delay based on index.
class _StaggeredEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredEntry({required this.index, required this.child});

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 450), vsync: this);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _AnimatedSubmitButton extends StatefulWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _AnimatedSubmitButton({required this.loading, required this.onTap});

  @override
  State<_AnimatedSubmitButton> createState() => _AnimatedSubmitButtonState();
}

class _AnimatedSubmitButtonState extends State<_AnimatedSubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, Color(0xFF0E7490)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Send message →', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}