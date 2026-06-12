import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _supabase = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  String? _openFaq;
  bool _submitted = false;
  bool _loading = false;
  String? _error;

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

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _msgCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all required fields');
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
      setState(() { _submitted = true; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Something went wrong. Please try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
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
                    Positioned(top: -80, right: -80, child: Container(width: 200, height: 200, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.12), shape: BoxShape.circle))),
                    SafeArea(child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('HELP CENTRE', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 3)),
                          const SizedBox(height: 8),
                          const Text('How can we\nhelp you?', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
                          const SizedBox(height: 8),
                          const Text('Find answers below or send us a message', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF374151), fontSize: 14)),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // FAQ Section
                const Center(child: Text('FAQ', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 3))),
                const SizedBox(height: 8),
                const Center(child: Text('Frequently asked questions', style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 22, fontWeight: FontWeight.w900))),
                const SizedBox(height: 24),
                ..._faqs.map((section) => _buildFaqSection(section)).toList(),
                const SizedBox(height: 32),

                // Contact section
                const Center(child: Text('Still need help?', style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 22, fontWeight: FontWeight.w900))),
                const SizedBox(height: 8),
                const Center(child: Text("Can't find what you're looking for? Send us a message — we respond within 24 hours.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.6))),
                const SizedBox(height: 24),

                // Info cards
                ...[
                  {'icon': '📧', 'label': 'Email us', 'value': 'hello@cleenzo.in', 'sub': 'We reply within 24 hours'},
                  {'icon': '📍', 'label': 'Based in', 'value': 'Mumbai, Maharashtra', 'sub': 'Serving Andheri & Vile Parle'},
                ].map((item) => Container(
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
                )),
                const SizedBox(height: 24),

                // Contact form
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 12))],
                  ),
                  child: _submitted ? _buildSuccessState() : _buildForm(),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

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
            ]),
          ),
          const Divider(color: Color(0xFFF3F4F6), height: 1),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final faq = entry.value;
            final key = '${section['category']}-$i';
            final isOpen = _openFaq == key;
            return Column(children: [
              GestureDetector(
                onTap: () => setState(() => _openFaq = isOpen ? null : key),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Row(children: [
                    Expanded(child: Text(faq['q']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)))),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(Icons.keyboard_arrow_down, color: AppTheme.primary),
                    ),
                  ]),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(faq['a']!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.7)),
                ),
                crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
              if (i < items.length - 1) const Divider(color: Color(0xFFF3F4F6), height: 1),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Text('⚠️ '),
              Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _loading ? null : _submitForm,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Center(
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Text('Send message →', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
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
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppTheme.primary.withOpacity(0.5))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✅', style: TextStyle(fontSize: 56)),
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