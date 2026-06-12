import 'package:flutter/material.dart';
import '../../utils/theme.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: AppTheme.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.8),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -20,
                      bottom: -20,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.gavel_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Legal',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Last updated: January 2025',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [
                Tab(text: 'Terms of Service'),
                Tab(text: 'Privacy Policy'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTermsContent(),
            _buildPrivacyContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.handshake_outlined,
            title: 'Agreement to Terms',
            content:
                'By accessing or using the Cleenzo app, you agree to be bound by these Terms of Service and all applicable laws and regulations. If you do not agree with any of these terms, you are prohibited from using or accessing this service.',
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '1. Use of Service',
            items: [
              'You must be at least 18 years old to use Cleenzo.',
              'You are responsible for maintaining the confidentiality of your account credentials.',
              'You agree to provide accurate, current, and complete information during registration.',
              'You must not use the service for any unlawful or prohibited purpose.',
              'One person may maintain only one active account on the platform.',
            ],
          ),
          _buildSection(
            title: '2. Booking & Cancellation',
            items: [
              'Bookings are confirmed only after successful payment processing.',
              'Cancellations made more than 24 hours before the scheduled service are eligible for a full refund.',
              'Cancellations within 24 hours may attract a cancellation fee of up to 50% of the booking amount.',
              'Cleenzo reserves the right to cancel bookings in case of worker unavailability with a full refund.',
              'No-shows by the customer will be treated as a cancellation without refund.',
            ],
          ),
          _buildSection(
            title: '3. Payment Terms',
            items: [
              'All payments are processed securely via Razorpay.',
              'Prices are listed in Indian Rupees (INR) and are inclusive of applicable taxes.',
              'Promotional codes and offers are subject to their individual terms and expiry dates.',
              'Refunds, where applicable, will be credited to the original payment method within 5–7 business days.',
              'Cleenzo is not liable for any payment gateway outages or transaction failures.',
            ],
          ),
          _buildSection(
            title: '4. Service Standards',
            items: [
              'All Cleenzo workers are background-verified and trained professionals.',
              'The service quality guarantee covers re-cleaning within 24 hours of reported dissatisfaction.',
              'Customers must ensure a safe working environment for Cleenzo workers.',
              'Any damage caused by the customer or pre-existing conditions is not Cleenzo\'s liability.',
              'Workers will not be held responsible for pre-existing damage or wear and tear.',
            ],
          ),
          _buildSection(
            title: '5. Intellectual Property',
            items: [
              'All content, trademarks, and data on this app are owned by Cleenzo.',
              'You may not reproduce or distribute any part of our service without written permission.',
              'User-generated content remains your property, but you grant Cleenzo a license to use it for service improvement.',
            ],
          ),
          _buildSection(
            title: '6. Limitation of Liability',
            items: [
              'Cleenzo shall not be liable for indirect, incidental, or consequential damages.',
              'Our liability is limited to the amount paid for the specific booking in question.',
              'We are not liable for delays or cancellations due to force majeure events.',
            ],
          ),
          _buildSection(
            title: '7. Governing Law',
            items: [
              'These terms are governed by the laws of India.',
              'Any disputes shall be subject to the exclusive jurisdiction of courts in Mumbai, Maharashtra.',
              'Disputes will first be attempted to be resolved through mediation before litigation.',
            ],
          ),
          _buildContactCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPrivacyContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.shield_outlined,
            title: 'Your Privacy Matters',
            content:
                'At Cleenzo, we take your privacy seriously. This policy describes how we collect, use, and protect your personal information when you use our services.',
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '1. Information We Collect',
            items: [
              'Personal details: name, email address, phone number, and profile photo.',
              'Address information for service delivery.',
              'Payment details (processed securely via Razorpay — we do not store card details).',
              'Usage data: app interactions, bookings, and preferences.',
              'Device information: device type, OS version, and app version for troubleshooting.',
            ],
          ),
          _buildSection(
            title: '2. How We Use Your Data',
            items: [
              'To create and manage your account and service bookings.',
              'To process payments and send booking confirmations and receipts.',
              'To match you with the best available cleaning professionals.',
              'To improve our app features, services, and user experience.',
              'To send important updates, offers, and promotional communications (with your consent).',
              'To comply with legal obligations and resolve disputes.',
            ],
          ),
          _buildSection(
            title: '3. Data Sharing',
            items: [
              'We share your contact and address with the assigned worker to complete your booking.',
              'We use Supabase for secure data storage and Razorpay for payment processing.',
              'We do not sell your personal data to third parties.',
              'We may share anonymized, aggregated data for analytics purposes.',
              'We may disclose data if required by law or to protect rights and safety.',
            ],
          ),
          _buildSection(
            title: '4. Data Security',
            items: [
              'All data is transmitted over HTTPS with end-to-end encryption.',
              'We use Supabase Row-Level Security (RLS) to ensure data access control.',
              'Passwords are hashed and never stored in plain text.',
              'We regularly audit our security practices and update protections.',
              'In the event of a data breach, we will notify affected users promptly.',
            ],
          ),
          _buildSection(
            title: '5. Your Rights',
            items: [
              'You can access, update, or delete your personal information from Account Settings.',
              'You can opt out of marketing communications at any time.',
              'You have the right to request a copy of the data we hold about you.',
              'You may request data portability in a machine-readable format.',
              'You can withdraw consent for data processing at any time (this may affect service availability).',
            ],
          ),
          _buildSection(
            title: '6. Cookies & Tracking',
            items: [
              'We use analytics tools to understand app usage patterns.',
              'No third-party advertising cookies are used in our app.',
              'You may opt out of analytics data collection in app settings.',
            ],
          ),
          _buildSection(
            title: '7. Data Retention',
            items: [
              'We retain your data for as long as your account is active.',
              'After account deletion, data is retained for 30 days before permanent removal.',
              'Booking history may be retained for up to 2 years for legal compliance.',
            ],
          ),
          _buildContactCard(isPrivacy: true),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.08),
            AppTheme.primary.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
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

  Widget _buildSection({required String title, required List<String> items}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              children: items
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 13.5,
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
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({bool isPrivacy = false}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPrivacy ? Icons.privacy_tip_outlined : Icons.contact_support_outlined,
                color: AppTheme.primary,
                size: 20,
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
          const SizedBox(height: 12),
          _buildContactRow(Icons.email_outlined, 'support@cleenzo.in'),
          const SizedBox(height: 8),
          _buildContactRow(Icons.location_on_outlined,
              'Mumbai, Maharashtra, India'),
          const SizedBox(height: 8),
          _buildContactRow(Icons.access_time_outlined,
              'Mon–Sat, 9:00 AM – 6:00 PM IST'),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }
}