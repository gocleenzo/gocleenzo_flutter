import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/supabase_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _profile;
  int  _addressCount = 0;
  int  _bookingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      _profile = await SupabaseService.getUserProfile(user.id);
    } catch (_) {}

    try {
      final addresses = await SupabaseService.getAddresses(user.id);
      _addressCount = addresses.length;
    } catch (_) {}

    try {
      final bookings = await SupabaseService.getCustomerBookings(user.id);
      _bookingCount = bookings.length;
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign out?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('You will need to log in again to book services.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out',
                style: TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseService.signOut();
    } catch (_) {}
    if (mounted) context.go('/login');
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F5F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0891B2))),
      );
    }

    final name  = (_profile?['full_name'] as String?)?.trim();
    final phone = (_profile?['phone'] as String?) ?? '';
    final displayName = (name == null || name.isEmpty) ? 'My Profile' : name;
    final initial = (name != null && name.isNotEmpty)
        ? name[0].toUpperCase()
        : '🙂';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        child: Column(children: [

          // ── Cyan gradient header ────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 16, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF06B6D4), Color(0xFF0E7490)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Profile',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(phone,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: const [
                            Icon(Icons.circle, size: 8, color: Color(0xFF4ADE80)),
                            SizedBox(width: 6),
                            Text('Active member',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
          ),

          // ── Stats row ───────────────────────────────────────
          Transform.translate(
            offset: const Offset(0, -18),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Row(children: [
                _stat('📋', _bookingCount == 0 ? '—' : '$_bookingCount', 'Bookings'),
                _divider(),
                _stat('📍', '$_addressCount', 'Addresses'),
                _divider(),
                _stat('🎟', '0', 'Coupons'),
              ]),
            ),
          ),

          // ── Menu items ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _tile(Icons.location_on_outlined, 'Saved Addresses',
                  '$_addressCount address${_addressCount == 1 ? '' : 'es'} saved',
                  () => context.go('/location-gate')),
              const SizedBox(height: 12),
              _tile(Icons.receipt_long_outlined, 'My Bookings',
                  'View all past & upcoming', () => context.go('/bookings')),
              const SizedBox(height: 12),
              _tile(Icons.local_offer_outlined, 'Offers & Coupons',
                  'Save more on every order', () => context.go('/offers')),
              const SizedBox(height: 12),
              _tile(Icons.help_outline, 'Help & Support',
                  'Get answers & contact us', () => context.push('/help')),
              const SizedBox(height: 12),
              _tile(Icons.description_outlined, 'Terms & Privacy',
                  'Legal information', () => context.push('/terms')),
              const SizedBox(height: 20),

              // Sign out
              GestureDetector(
                onTap: _signOut,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.logout, color: Color(0xFFEF4444), size: 20),
                      SizedBox(width: 8),
                      Text('Sign Out',
                          style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Cleenzo v1.0 · Made in Mumbai',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────
  Widget _stat(String emoji, String value, String label) => Expanded(
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
      );

  Widget _divider() => Container(
        width: 1, height: 36, color: const Color(0xFFE2E8F0));

  Widget _tile(IconData icon, String title, String subtitle,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F7FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF0891B2), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
          ]),
        ),
      );
}