import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _addresses = [];
  bool _loading      = true;
  bool _editing      = false;
  bool _saving       = false;
  bool _addrExpanded = false;

  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      if (mounted) context.go('/login');
      return;
    }
    final authUser = session.user;
    Map<String, dynamic>? profile;
    try {
      profile = await _supabase
          .from('users').select('*').eq('id', authUser.id).single();
    } catch (_) {}

    if (profile == null) {
      profile = {
        'id': authUser.id,
        'full_name': authUser.userMetadata?['full_name'],
        'email': authUser.email,
        'phone': authUser.phone,
      };
      try { await _supabase.from('users').upsert(profile!); } catch (_) {}
    }

    List<Map<String, dynamic>> addrs = [];
    try {
      final result = await _supabase
          .from('addresses').select('*').eq('user_id', authUser.id)
          .order('created_at');
      addrs = (result as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _user = profile;
        _nameCtrl.text  = profile?['full_name'] ?? '';
        _emailCtrl.text = profile?['email'] ?? '';
        _addresses = addrs;
        _loading   = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;
    setState(() => _saving = true);
    try {
      await _supabase.from('users')
          .update({'full_name': _nameCtrl.text, 'email': _emailCtrl.text})
          .eq('id', _user!['id']);
      setState(() {
        _user = {..._user!, 'full_name': _nameCtrl.text, 'email': _emailCtrl.text};
        _saving  = false;
        _editing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: Color(0xFF10B981)));
      }
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteAddress(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Address',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Remove this address?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10)),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _supabase.from('addresses').delete().eq('id', id);
        setState(() => _addresses.removeWhere((a) => a['id'] == id));
      } catch (_) {}
    }
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  // ── Open Google Maps location picker ─────────────────────────
  Future<void> _openAddAddress() async {
    final result = await context.push('/location-gate');
    // Reload addresses when returning
    if (result == true || result == null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(child: CircularProgressIndicator(
            color: AppTheme.primary)),
      );
    }

    final displayName = _user?['full_name'] ?? _user?['phone'] ?? 'User';
    final initials    = displayName.isNotEmpty
        ? displayName.substring(0,
            displayName.length >= 2 ? 2 : 1).toUpperCase()
        : 'U';
    final phone    = _user?['phone'] ?? '';
    final email    = _user?['email'] ?? '';
    final subtitle = phone.isNotEmpty
        ? phone
        : email.isNotEmpty ? email : '—';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(children: [
            _buildHero(initials, displayName, subtitle),
            const SizedBox(height: 16),
            if (_editing) ...[
              _buildEditForm(),
              const SizedBox(height: 16),
            ],
            _buildStats(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildAddressSection(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildQuickLinks(),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildLogoutButton(),
            ),
            const SizedBox(height: 24),
            Text('Cleenzo v1.0 · Made with ❤️ in Mumbai',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  // ── Hero header ───────────────────────────────────────────────
  Widget _buildHero(String initials, String displayName, String subtitle) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF06B6D4), Color(0xFF0891B2), Color(0xFF0369A1)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('My Profile', style: TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.w900)),
              GestureDetector(
                onTap: () => setState(() => _editing = !_editing),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(_editing ? Icons.close : Icons.edit_outlined,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(_editing ? 'Cancel' : 'Edit',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Stack(children: [
                Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0.35),
                      Colors.white.withValues(alpha: 0.15),
                    ]),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 2),
                  ),
                  child: Center(child: Text(initials, style: const TextStyle(
                      color: Colors.white, fontSize: 26,
                      fontWeight: FontWeight.bold))),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.check, color: Colors.white, size: 12),
                  ),
                ),
              ]),
              const SizedBox(width: 16),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(displayName, style: const TextStyle(color: Colors.white,
                    fontSize: 20, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    color: Color(0xFFBAE6FD), fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 4,
                        backgroundColor: Color(0xFF86EFAC)),
                    SizedBox(width: 6),
                    Text('Active member', style: TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w500)),
                  ]),
                ),
              ])),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Edit form ─────────────────────────────────────────────────
  Widget _buildEditForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.12),
            blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.person_outline_rounded,
              color: AppTheme.primary, size: 20),
          SizedBox(width: 8),
          Text('Edit Profile', style: TextStyle(color: AppTheme.primary,
              fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 16),
        _editField('👤', 'Full name', _nameCtrl),
        const SizedBox(height: 10),
        _editField('✉️', 'Email address', _emailCtrl,
            type: TextInputType.emailAddress),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _editing = false),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(16)),
                child: const Center(child: Text('Cancel',
                    style: TextStyle(color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : _saveProfile,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Save changes',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _editField(String icon, String hint,
      TextEditingController ctrl, {TextInputType? type}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFF),
        border: Border.all(color: const Color(0xFFA5F3FC)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Padding(padding: const EdgeInsets.only(left: 16),
            child: Text(icon, style: const TextStyle(fontSize: 16))),
        Expanded(child: TextField(
          controller: ctrl, keyboardType: type,
          decoration: InputDecoration(
            hintText: hint, border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 14),
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          ),
        )),
      ]),
    );
  }

  // ── Stats bar ─────────────────────────────────────────────────
  Widget _buildStats() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Expanded(child: _stat('📋', '—', 'Bookings', const Color(0xFFECFEFF))),
        _divider(),
        Expanded(child: _stat('📍', '${_addresses.length}',
            'Addresses', const Color(0xFFF5F3FF))),
        _divider(),
        Expanded(child: _stat('🎟️', '0', 'Coupons', const Color(0xFFFFFBEB))),
      ]),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 40, color: const Color(0xFFF3F4F6));

  Widget _stat(String icon, String val, String label, Color bg) {
    return Column(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(icon,
            style: const TextStyle(fontSize: 20))),
      ),
      const SizedBox(height: 6),
      Text(val, style: const TextStyle(fontSize: 18,
          fontWeight: FontWeight.w900, color: Color(0xFF111827))),
      Text(label, style: const TextStyle(color: Color(0xFF9CA3AF),
          fontSize: 11, fontWeight: FontWeight.w500)),
    ]);
  }

  // ── Address section ───────────────────────────────────────────
  Widget _buildAddressSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: Column(children: [
        // Header — tap to expand
        GestureDetector(
          onTap: () => setState(() => _addrExpanded = !_addrExpanded),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFFECFEFF),
                    borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('📍',
                    style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Saved Addresses', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color: Color(0xFF111827))),
                Text(
                  _addresses.isEmpty
                      ? 'No addresses saved yet'
                      : '${_addresses.length} address${_addresses.length == 1 ? '' : 'es'} saved',
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF), fontSize: 12),
                ),
              ])),
              AnimatedRotation(
                turns: _addrExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF9CA3AF), size: 24),
              ),
            ]),
          ),
        ),

        if (_addrExpanded) ...[
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(children: [

              // ── Add new address button → opens Google Maps ──
              GestureDetector(
                onTap: _openAddAddress,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.35),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_location_alt_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Add New Address',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 14)),
                      ]),
                ),
              ),

              const SizedBox(height: 4),
              const Text('Powered by Google Maps',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),

              // ── Saved addresses list ────────────────────────
              ..._addresses.map((addr) => Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF0F0F0)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFEFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBAE6FD))),
                      child: Center(child: Text(
                        addr['label'] == 'Home' ? '🏠'
                            : addr['label'] == 'Office' ? '🏢' : '📍',
                        style: const TextStyle(fontSize: 20),
                      )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(addr['label'] ?? 'Address',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13,
                                color: Color(0xFF111827))),
                        if (addr['is_default'] == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFEFF),
                              borderRadius: BorderRadius.circular(20)),
                            child: const Text('Default',
                                style: TextStyle(color: AppTheme.primary,
                                    fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (addr['flat_no'] != null) addr['flat_no'],
                          if (addr['building'] != null) addr['building'],
                          addr['area'], addr['city'],
                        ].where((e) => e != null).join(', '),
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 12),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      if (addr['landmark'] != null) ...[
                        const SizedBox(height: 2),
                        Text('📌 ${addr['landmark']}',
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                      if (addr['latitude'] != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${(addr['latitude'] as double).toStringAsFixed(4)}, '
                          '${(addr['longitude'] as double).toStringAsFixed(4)}',
                          style: const TextStyle(
                              color: Color(0xFFBAE6FD), fontSize: 10),
                        ),
                      ],
                    ])),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _deleteAddress(addr['id']),
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444), size: 18),
                      ),
                    ),
                  ]),
                ),
              )),

              if (_addresses.isEmpty) ...[
                const SizedBox(height: 20),
                const Column(children: [
                  Text('📭', style: TextStyle(fontSize: 36)),
                  SizedBox(height: 8),
                  Text('No addresses yet',
                      style: TextStyle(fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B))),
                  SizedBox(height: 4),
                  Text('Tap "Add New Address" to get started',
                      style: TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 12)),
                ]),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Quick links ───────────────────────────────────────────────
  Widget _buildQuickLinks() {
    final links = [
      {'icon': '📋', 'label': 'My Bookings',
        'sub': 'View all past & upcoming', 'route': '/bookings',
        'color': const Color(0xFFECFEFF), 'iconColor': AppTheme.primary},
      {'icon': '🎟️', 'label': 'Offers & Coupons',
        'sub': 'Save more on every order', 'route': '/offers',
        'color': const Color(0xFFFFFBEB),
        'iconColor': const Color(0xFFF59E0B)},
      {'icon': '💬', 'label': 'Help & Support',
        'sub': 'Get answers & contact us', 'route': '/help',
        'color': const Color(0xFFECFDF5),
        'iconColor': const Color(0xFF10B981)},
      {'icon': '📜', 'label': 'Terms & Privacy',
        'sub': 'Legal information', 'route': '/terms',
        'color': const Color(0xFFEFF6FF),
        'iconColor': const Color(0xFF3B82F6)},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: Column(
        children: links.asMap().entries.map((entry) {
          final i    = entry.key;
          final link = entry.value;
          return GestureDetector(
            onTap: () => context.go(link['route'] as String),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: i < links.length - 1
                    ? const Border(bottom: BorderSide(
                        color: Color(0xFFF5F5F7)))
                    : null,
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                      color: link['color'] as Color,
                      borderRadius: BorderRadius.circular(13)),
                  child: Center(child: Text(link['icon'] as String,
                      style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(link['label'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 14, color: Color(0xFF1F2937))),
                  Text(link['sub'] as String,
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 12)),
                ])),
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.arrow_forward_ios_rounded,
                      color: Color(0xFFD1D5DB), size: 13),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────
  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
          SizedBox(width: 10),
          Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444),
              fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      ),
    );
  }
}