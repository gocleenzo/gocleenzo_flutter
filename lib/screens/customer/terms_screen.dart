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
  // Sourced from the official Cleenzo Terms & Conditions
  // (Cubicle Ventures Private Limited), last updated July 1, 2026.

  final List<LegalSection> _termsSections = const [
    LegalSection(
      title: 'Services & Pro Services',
      icon: Icons.cleaning_services_rounded,
      items: [
        'Cleenzo is a technology platform that lets you discover, book, and avail home cleaning and related services ("Professional Services") from independent third-party Professionals. We facilitate discovery, booking, and payment — we do not perform or control the execution of Professional Services ourselves.',
        'Instant Booking is available between 7:00 AM and 7:00 PM IST on the day of booking, subject to Professional availability.',
        'Scheduled Booking lets you book in advance for a preferred date and time slot, subject to availability.',
        'Professionals are independent service providers — not agents, partners, or representatives of Cleenzo.',
        'The Platform is for your personal, non-commercial use only.',
        'We reserve the right to decline any booking at our sole discretion (safety, compliance, or operational reasons) and do not guarantee Professional availability for any service, slot, or location.',
        'We may update, modify, suspend, or discontinue any Service or feature at any time without prior notice.',
      ],
    ),
    LegalSection(
      title: 'Eligibility',
      icon: Icons.how_to_reg_rounded,
      items: [
        'You must be at least 18 years old and have the legal capacity to enter into a binding agreement under Indian law.',
        'You agree to use the Services only in compliance with these Terms and all applicable laws and regulations of India.',
      ],
    ),
    LegalSection(
      title: 'Account Creation',
      icon: Icons.badge_rounded,
      items: [
        'You must create an Account with accurate details, including your name, phone number, and address.',
        'You must keep your Account information accurate and complete, and update it promptly if it changes.',
        'You are solely responsible for keeping your Account credentials confidential and for all activity under your Account.',
        'You must notify us immediately of any unauthorized use of your Account or any security breach.',
        'Cleenzo is not liable for loss or damage from unauthorized Account access, unless it results directly from our gross negligence or willful misconduct.',
      ],
    ),
    LegalSection(
      title: 'Bookings',
      icon: Icons.event_available_rounded,
      items: [
        'Bookings are placed based on availability shown at the time of booking, and are subject to Professional availability and time-slot capacity.',
        'Instant bookings are first-come, first-served. A slot is confirmed only once your booking is successfully placed — availability is never guaranteed.',
        'Once confirmed, you\'ll receive an App and/or SMS notification with your booking details and OTP for service verification.',
        'If your assigned Professional becomes unavailable, we may arrange a replacement or help you reschedule where possible — this isn\'t guaranteed.',
        'You agree to: ensure timely access to the service location; tell us in advance about anything that could affect service (pets, restricted areas, safety hazards); and avoid undue delays on-site.',
        'Failure to meet the above may cause delays, prevent the service from being performed, or lead to cancellation — Cleenzo and Professionals aren\'t liable for non-performance caused by such conditions.',
        'Time estimates and service durations shown on the Platform are indicative only, not a guaranteed completion time.',
        'Professionals do not carry their own cleaning equipment or supplies — please make sure everything needed is available at your address before the service begins.',
      ],
    ),
    LegalSection(
      title: 'Payment Terms',
      icon: Icons.payments_rounded,
      items: [
        'All payments for Professional Services are currently Cash on Delivery (COD), paid directly to the Professional once the service is complete.',
        'The total amount payable ("Fees") is clearly shown before you confirm a booking, and may include the service fee, a platform fee, a surge fee (where enabled), and any other disclosed charges.',
        'All Fees are inclusive of or subject to applicable taxes.',
        'Promo codes and discounts follow their own terms and validity periods, and can\'t be combined unless explicitly stated.',
        'We may change Fees at any time at our discretion — this won\'t affect bookings already confirmed before the change.',
        'We may introduce additional payment methods (UPI, cards, net banking) on the Platform in future.',
        'Please don\'t pay Professionals outside the Platform — Cleenzo isn\'t liable for disputes, losses, or damages from payments made directly to Professionals off-platform.',
      ],
    ),
    LegalSection(
      title: 'OTP Verification',
      icon: Icons.lock_rounded,
      items: [
        'An OTP (One-Time Password) verifies the start of your service. You must give this OTP to your assigned Professional at your service location to begin the job.',
        'Never share your OTP with anyone other than the verified Professional physically present at your address.',
        'The OTP window opens 30 minutes before your scheduled service start time.',
      ],
    ),
    LegalSection(
      title: 'Cancellations',
      icon: Icons.event_busy_rounded,
      items: [
        'You may cancel a booking at no charge before a Professional has been assigned.',
        'Once a Professional is assigned, cancellations may not be permitted, or may attract a cancellation fee as shown on the Platform at the time of booking.',
        'We reserve the right to cancel any booking due to Professional unavailability, safety concerns, or other operational or regulatory reasons.',
      ],
    ),
    LegalSection(
      title: 'Customer Conduct',
      icon: Icons.diversity_3_rounded,
      items: [
        'Please treat all Professionals with courtesy, dignity, and respect, and provide a safe, appropriate environment for the service.',
        'Professionals may refuse to work if conditions at your location are unsafe or unsanitary, or if your conduct is abusive, disrespectful, threatening, or otherwise inappropriate.',
        'Discrimination against Professionals based on race, religion, caste, national origin, disability, sexual orientation, gender, age, or any other protected characteristic is strictly prohibited.',
        'Please don\'t solicit or encourage a Professional to work with you outside the Platform — doing so may result in suspension or termination of your access.',
        'Secure your valuables, fragile items, and sensitive equipment before the service begins — Cleenzo and Professionals aren\'t responsible for loss or damage to such items.',
        'Cleenzo isn\'t responsible for pre-existing defects, damage, or wear and tear at your service location.',
        'If a Professional behaves abusively, inappropriately, or unlawfully, please report it to gocleenzo@gmail.com within 48 hours.',
      ],
    ),
    LegalSection(
      title: 'Intellectual Property',
      icon: Icons.copyright_rounded,
      items: [
        'All rights, title, and interest in the Services — including the Platform, App, logos, content, and software — belong to or are validly licensed to Cleenzo.',
        'You\'re granted a limited, non-exclusive, non-transferable, revocable licence to access and use the Services under these Terms.',
        'You may not reproduce, modify, distribute, or create derivative works from any Platform content without our prior written consent.',
      ],
    ),
    LegalSection(
      title: 'Indemnity',
      icon: Icons.shield_rounded,
      items: [
        'You agree to indemnify, defend, and hold harmless Cleenzo, its officers, directors, employees, agents, and representatives from any claims, losses, liabilities, damages, and expenses (including reasonable legal fees) arising from your use of the Services, your violation of these Terms, or unauthorized use of your Account.',
      ],
    ),
    LegalSection(
      title: 'Liability & Disclaimers',
      icon: Icons.gpp_maybe_rounded,
      items: [
        'To the maximum extent permitted by law, Cleenzo is not liable for indirect, incidental, special, consequential, punitive, or exemplary damages relating to these Terms or the Services.',
        'Our total liability arising from these Terms or the Services is capped at the Fees you paid for the specific booking the claim relates to.',
        'Cleenzo operates a technology platform and doesn\'t perform Professional Services itself — we\'re not liable for the acts, omissions, or quality of work of Professionals.',
        'The Services are provided "as is" and "as available," without warranties of merchantability, fitness for a particular purpose, or non-infringement.',
        'We don\'t guarantee any specific outcome, result, or satisfaction level from Professional Services.',
        'We\'re not responsible for property damage arising from Professional Services, except where required by law.',
      ],
    ),
    LegalSection(
      title: 'Term, Termination & Governing Law',
      icon: Icons.account_balance_rounded,
      items: [
        'These Terms remain in effect until terminated by either party.',
        'We may restrict, suspend, or terminate your access at any time — with or without notice — for violations of these Terms, ineligibility, or legitimate business, legal, or regulatory reasons.',
        'You may close your Account anytime by emailing gocleenzo@gmail.com.',
        'Clauses covering intellectual property, liability, indemnity, governing law, and dispute resolution survive termination of these Terms.',
        'These Terms are governed by the laws of India. Courts in Maharashtra have exclusive jurisdiction over any disputes.',
        'Disputes are resolved by arbitration in Maharashtra under the Arbitration and Conciliation Act, 1996, before a single Company-appointed arbitrator, conducted in English. The arbitrator\'s decision is final and binding.',
      ],
    ),
    LegalSection(
      title: 'Grievance Redressal',
      icon: Icons.support_agent_rounded,
      items: [
        'For any booking-related issues, reach us through the Help section in the App or the channels below.',
        'Email: gocleenzo@gmail.com',
        'Available in-app via the Help section, Monday – Saturday, 9:00 AM to 7:00 PM IST.',
      ],
    ),
    LegalSection(
      title: 'Miscellaneous',
      icon: Icons.rule_folder_rounded,
      items: [
        'We may update these Terms from time to time — continuing to use the Platform after an update means you accept the revised Terms.',
        'If any provision of these Terms is found invalid or unenforceable, the rest remain in full effect.',
        'You may not assign your rights or obligations under these Terms without our prior written consent. We may freely assign these Terms to an affiliate, successor, or third party in a merger, acquisition, or business transfer.',
        'Any delay or failure by us to enforce a right under these Terms doesn\'t waive that right.',
        'We\'re not liable for delays or failures caused by events beyond our reasonable control — acts of God, strikes, pandemic, war, government orders, or third-party service failures.',
        'These Terms, together with the Privacy Policy and any Additional Terms, form the entire agreement between you and Cleenzo, superseding all prior agreements.',
        'Nothing in these Terms creates a partnership, employment, joint venture, or agency relationship between Cleenzo and any Customer or Professional.',
      ],
    ),
  ];

  final List<LegalSection> _privacySections = const [
    LegalSection(
      title: 'Information We Collect',
      icon: Icons.badge_rounded,
      items: [
        'Personal details: name, email address, phone number, and profile photo.',
        'Address information, needed to deliver Professional Services to you.',
        'Usage data: app interactions, bookings, and preferences.',
        'Device information: device type, OS version, and app version, for troubleshooting.',
        'We do not currently process online payments through the Platform — all payments are Cash on Delivery, paid directly to the Professional, so we do not collect or store your card or bank details.',
      ],
    ),
    LegalSection(
      title: 'How We Use Your Data',
      icon: Icons.tune_rounded,
      items: [
        'To create and manage your Account and service bookings.',
        'To send booking confirmations, OTPs, and service-related updates.',
        'To match you with an available cleaning Professional.',
        'To improve our app features, services, and user experience.',
        'To send important updates, offers, and promotional communications (with your consent).',
        'To comply with legal obligations and resolve disputes.',
      ],
    ),
    LegalSection(
      title: 'Data Sharing',
      icon: Icons.share_rounded,
      items: [
        'We share your contact details and address with the Professional assigned to your booking, so they can complete the service.',
        'We use Supabase for secure data storage.',
        'We do not sell your personal data to third parties.',
        'We may share anonymized, aggregated data for analytics purposes.',
        'We may disclose your data to law enforcement or government bodies pursuant to a lawful request.',
      ],
    ),
    LegalSection(
      title: 'Data Security',
      icon: Icons.lock_rounded,
      items: [
        'All data is transmitted over HTTPS.',
        'We use Supabase Row-Level Security (RLS) to control access to your data.',
        'We regularly review and update our security practices.',
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
        'You can withdraw consent for data processing at any time (this may affect service availability).',
      ],
    ),
    LegalSection(
      title: 'Data Retention',
      icon: Icons.history_rounded,
      items: [
        'We retain your data for as long as your Account is active.',
        'After Account deletion, data is retained for a limited period before permanent removal, unless a longer period is required for legal or regulatory compliance.',
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
                            label: 'Updated Jul 1, 2026',
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
                      ? 'This policy describes how Cubicle Ventures Private Limited ("Cleenzo") collects, uses, and protects your personal information when you use the app.'
                      : 'By accessing or using Cleenzo, you enter into a legally binding agreement with Cubicle Ventures Private Limited and agree to be bound by these Terms.',
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
                ? 'For privacy-related queries or data requests, contact us at:'
                : 'If you have any questions about these Terms, please contact us:',
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _ContactRow(icon: Icons.email_outlined, text: 'gocleenzo@gmail.com'),
          const SizedBox(height: 10),
          _ContactRow(
              icon: Icons.location_on_outlined,
              text: 'Yavatmal, Maharashtra, India'),
          const SizedBox(height: 10),
          _ContactRow(
              icon: Icons.access_time_outlined,
              text: 'Monday – Saturday, 9:00 AM – 7:00 PM IST'),
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