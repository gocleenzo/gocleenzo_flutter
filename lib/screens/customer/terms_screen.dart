import 'package:flutter/material.dart';
import '../../utils/theme.dart';

/// ---------------------------------------------------------------------
/// DATA MODELS
/// ---------------------------------------------------------------------
/// Pulling content into models makes the UI declarative & easy to theme,
/// reorder, search, or feed from a CMS/Supabase table later if you want.

class LegalSection {
  final String title;
  final IconData icon;
  final List<String> items;

  const LegalSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

/// ---------------------------------------------------------------------
/// SCREEN
/// ---------------------------------------------------------------------

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _heroController;
  late Animation<double> _heroFade;

  // Tracks which accordion index is open per tab (-1 = none, 0 = first open by default)
  int _openTermsIndex = -1;
  int _openPrivacyIndex = -1;

  final ScrollController _termsScrollController = ScrollController();
  final ScrollController _privacyScrollController = ScrollController();
  bool _showTermsFab = false;
  bool _showPrivacyFab = false;

  // ---- CONTENT -------------------------------------------------------

  final List<LegalSection> _termsSections = const [
    LegalSection(
      title: 'Use of Service',
      icon: Icons.how_to_reg_rounded,
      items: [
        'You must be at least 18 years old to use Cleenzo.',
        'You are responsible for maintaining the confidentiality of your account credentials.',
        'You agree to provide accurate, current, and complete information during registration.',
        'You must not use the service for any unlawful or prohibited purpose.',
        'One person may maintain only one active account on the platform.',
      ],
    ),
    LegalSection(
      title: 'Booking & Cancellation',
      icon: Icons.event_available_rounded,
      items: [
        'Bookings are confirmed only after successful payment processing.',
        'Cancellations made more than 24 hours before the scheduled service are eligible for a full refund.',
        'Cancellations within 24 hours may attract a cancellation fee of up to 50% of the booking amount.',
        'Cleenzo reserves the right to cancel bookings in case of worker unavailability with a full refund.',
        'No-shows by the customer will be treated as a cancellation without refund.',
      ],
    ),
    LegalSection(
      title: 'Payment Terms',
      icon: Icons.payments_rounded,
      items: [
        'All payments are processed securely via Razorpay.',
        'Prices are listed in Indian Rupees (INR) and are inclusive of applicable taxes.',
        'Promotional codes and offers are subject to their individual terms and expiry dates.',
        'Refunds, where applicable, will be credited to the original payment method within 5–7 business days.',
        'Cleenzo is not liable for any payment gateway outages or transaction failures.',
      ],
    ),
    LegalSection(
      title: 'Service Standards',
      icon: Icons.verified_rounded,
      items: [
        'All Cleenzo workers are background-verified and trained professionals.',
        'The service quality guarantee covers re-cleaning within 24 hours of reported dissatisfaction.',
        'Customers must ensure a safe working environment for Cleenzo workers.',
        'Any damage caused by the customer or pre-existing conditions is not Cleenzo\'s liability.',
        'Workers will not be held responsible for pre-existing damage or wear and tear.',
      ],
    ),
    LegalSection(
      title: 'Intellectual Property',
      icon: Icons.copyright_rounded,
      items: [
        'All content, trademarks, and data on this app are owned by Cleenzo.',
        'You may not reproduce or distribute any part of our service without written permission.',
        'User-generated content remains your property, but you grant Cleenzo a license to use it for service improvement.',
      ],
    ),
    LegalSection(
      title: 'Limitation of Liability',
      icon: Icons.gpp_maybe_rounded,
      items: [
        'Cleenzo shall not be liable for indirect, incidental, or consequential damages.',
        'Our liability is limited to the amount paid for the specific booking in question.',
        'We are not liable for delays or cancellations due to force majeure events.',
      ],
    ),
    LegalSection(
      title: 'Governing Law',
      icon: Icons.account_balance_rounded,
      items: [
        'These terms are governed by the laws of India.',
        'Any disputes shall be subject to the exclusive jurisdiction of courts in Mumbai, Maharashtra.',
        'Disputes will first be attempted to be resolved through mediation before litigation.',
      ],
    ),
  ];

  final List<LegalSection> _privacySections = const [
    LegalSection(
      title: 'Information We Collect',
      icon: Icons.badge_rounded,
      items: [
        'Personal details: name, email address, phone number, and profile photo.',
        'Address information for service delivery.',
        'Payment details (processed securely via Razorpay — we do not store card details).',
        'Usage data: app interactions, bookings, and preferences.',
        'Device information: device type, OS version, and app version for troubleshooting.',
      ],
    ),
    LegalSection(
      title: 'How We Use Your Data',
      icon: Icons.tune_rounded,
      items: [
        'To create and manage your account and service bookings.',
        'To process payments and send booking confirmations and receipts.',
        'To match you with the best available cleaning professionals.',
        'To improve our app features, services, and user experience.',
        'To send important updates, offers, and promotional communications (with your consent).',
        'To comply with legal obligations and resolve disputes.',
      ],
    ),
    LegalSection(
      title: 'Data Sharing',
      icon: Icons.share_rounded,
      items: [
        'We share your contact and address with the assigned worker to complete your booking.',
        'We use Supabase for secure data storage and Razorpay for payment processing.',
        'We do not sell your personal data to third parties.',
        'We may share anonymized, aggregated data for analytics purposes.',
        'We may disclose data if required by law or to protect rights and safety.',
      ],
    ),
    LegalSection(
      title: 'Data Security',
      icon: Icons.lock_rounded,
      items: [
        'All data is transmitted over HTTPS with end-to-end encryption.',
        'We use Supabase Row-Level Security (RLS) to ensure data access control.',
        'Passwords are hashed and never stored in plain text.',
        'We regularly audit our security practices and update protections.',
        'In the event of a data breach, we will notify affected users promptly.',
      ],
    ),
    LegalSection(
      title: 'Your Rights',
      icon: Icons.fact_check_rounded,
      items: [
        'You can access, update, or delete your personal information from Account Settings.',
        'You can opt out of marketing communications at any time.',
        'You have the right to request a copy of the data we hold about you.',
        'You may request data portability in a machine-readable format.',
        'You can withdraw consent for data processing at any time (this may affect service availability).',
      ],
    ),
    LegalSection(
      title: 'Cookies & Tracking',
      icon: Icons.cookie_rounded,
      items: [
        'We use analytics tools to understand app usage patterns.',
        'No third-party advertising cookies are used in our app.',
        'You may opt out of analytics data collection in app settings.',
      ],
    ),
    LegalSection(
      title: 'Data Retention',
      icon: Icons.history_rounded,
      items: [
        'We retain your data for as long as your account is active.',
        'After account deletion, data is retained for 30 days before permanent removal.',
        'Booking history may be retained for up to 2 years for legal compliance.',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _heroController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _heroFade = CurvedAnimation(parent: _heroController, curve: Curves.easeOut);
    _heroController.forward();

    _termsScrollController.addListener(() {
      final show = _termsScrollController.offset > 280;
      if (show != _showTermsFab) setState(() => _showTermsFab = show);
    });
    _privacyScrollController.addListener(() {
      final show = _privacyScrollController.offset > 280;
      if (show != _showPrivacyFab) setState(() => _showPrivacyFab = show);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _heroController.dispose();
    _termsScrollController.dispose();
    _privacyScrollController.dispose();
    super.dispose();
  }

  void _scrollToTop(ScrollController c) {
    c.animateTo(0,
        duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildHeroAppBar(),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLegalTab(
              sections: _termsSections,
              scrollController: _termsScrollController,
              openIndex: _openTermsIndex,
              onToggle: (i) => setState(
                  () => _openTermsIndex = _openTermsIndex == i ? -1 : i),
              showFab: _showTermsFab,
              isPrivacy: false,
            ),
            _buildLegalTab(
              sections: _privacySections,
              scrollController: _privacyScrollController,
              openIndex: _openPrivacyIndex,
              onToggle: (i) => setState(
                  () => _openPrivacyIndex = _openPrivacyIndex == i ? -1 : i),
              showFab: _showPrivacyFab,
              isPrivacy: true,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HERO / APP BAR
  // ---------------------------------------------------------------------

  Widget _buildHeroAppBar() {
    return SliverAppBar(
      expandedHeight: 188,
      floating: false,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: AppTheme.primary,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Animated gradient backdrop
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withOpacity(0.85),
                    AppTheme.primary.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            // Decorative floating circles
            Positioned(
              right: -40,
              top: -40,
              child: _FloatingCircle(size: 180, opacity: 0.08),
            ),
            Positioned(
              left: -30,
              bottom: 30,
              child: _FloatingCircle(size: 110, opacity: 0.07),
            ),
            Positioned(
              right: 60,
              bottom: -10,
              child: _FloatingCircle(size: 60, opacity: 0.1),
            ),
            // Subtle dotted pattern overlay
            Positioned.fill(
              child: CustomPaint(painter: _DotPatternPainter()),
            ),
            SafeArea(
              child: FadeTransition(
                opacity: _heroFade,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 44, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.25)),
                            ),
                            child: const Icon(
                              Icons.gavel_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Legal Center',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _Pill(
                            icon: Icons.update_rounded,
                            label: 'Updated Jan 2025',
                          ),
                          const SizedBox(width: 8),
                          _Pill(
                            icon: Icons.touch_app_rounded,
                            label: 'Tap to expand',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppTheme.primary,
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(4),
              dividerColor: Colors.transparent,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Colors.white,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              tabs: const [
                Tab(text: 'Terms of Service'),
                Tab(text: 'Privacy Policy'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // TAB BODY
  // ---------------------------------------------------------------------

  Widget _buildLegalTab({
    required List<LegalSection> sections,
    required ScrollController scrollController,
    required int openIndex,
    required ValueChanged<int> onToggle,
    required bool showFab,
    required bool isPrivacy,
  }) {
    return Stack(
      children: [
        ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _IntroCard(isPrivacy: isPrivacy),
            const SizedBox(height: 18),
            ...List.generate(sections.length, (i) {
              return _StaggeredEntry(
                index: i,
                child: _AccordionCard(
                  number: i + 1,
                  section: sections[i],
                  isOpen: openIndex == i,
                  onTap: () => onToggle(i),
                ),
              );
            }),
            const SizedBox(height: 4),
            _ContactCard(isPrivacy: isPrivacy),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 16,
          child: AnimatedSlide(
            offset: showFab ? Offset.zero : const Offset(0, 2),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: showFab ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: FloatingActionButton.small(
                heroTag: isPrivacy ? 'privacy_fab' : 'terms_fab',
                backgroundColor: AppTheme.primary,
                elevation: 3,
                onPressed: () => _scrollToTop(scrollController),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// SMALL DECORATIVE WIDGETS
/// ---------------------------------------------------------------------

class _FloatingCircle extends StatelessWidget {
  final double size;
  final double opacity;
  const _FloatingCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    const spacing = 18.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height * 0.6; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

class _StaggeredEntryState extends State<_StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
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

class _IntroCard extends StatelessWidget {
  final bool isPrivacy;
  const _IntroCard({required this.isPrivacy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.10),
            AppTheme.primary.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPrivacy ? Icons.shield_outlined : Icons.handshake_outlined,
              color: AppTheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPrivacy ? 'Your Privacy Matters' : 'Agreement to Terms',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isPrivacy
                      ? 'This policy describes how we collect, use, and protect your personal information when you use Cleenzo.'
                      : 'By accessing or using Cleenzo, you agree to be bound by these Terms of Service and all applicable laws.',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Expand/collapse card replacing the old static section block.
class _AccordionCard extends StatelessWidget {
  final int number;
  final LegalSection section;
  final bool isOpen;
  final VoidCallback onTap;

  const _AccordionCard({
    required this.number,
    required this.section,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOpen
              ? AppTheme.primary.withOpacity(0.35)
              : const Color(0xFFE7EBF0),
          width: isOpen ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isOpen
                ? AppTheme.primary.withOpacity(0.10)
                : Colors.black.withOpacity(0.035),
            blurRadius: isOpen ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? AppTheme.primary
                            : AppTheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        section.icon,
                        size: 19,
                        color: isOpen ? Colors.white : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${number.toString().padLeft(2, '0')}  ·  ${section.title}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 280),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: isOpen
                            ? AppTheme.primary
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: isOpen
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12, left: 50),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: section.items
                                .map((item) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 6),
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: const TextStyle(
                                                fontSize: 13.3,
                                                color: Color(0xFF475569),
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final bool isPrivacy;
  const _ContactCard({this.isPrivacy = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPrivacy
                      ? Icons.privacy_tip_outlined
                      : Icons.contact_support_outlined,
                  color: AppTheme.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isPrivacy ? 'Privacy Questions?' : 'Questions?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isPrivacy
                ? 'For privacy-related queries or data requests, contact our Data Protection Officer:'
                : 'If you have any questions about these Terms, please contact us:',
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _ContactRow(icon: Icons.email_outlined, text: 'support@cleenzo.in'),
          const SizedBox(height: 10),
          _ContactRow(
              icon: Icons.location_on_outlined,
              text: 'Mumbai, Maharashtra, India'),
          const SizedBox(height: 10),
          _ContactRow(
              icon: Icons.access_time_outlined,
              text: 'Mon–Sat, 9:00 AM – 6:00 PM IST'),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}