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
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _showAddAddr = false;
  bool _addrExpanded = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // New address form
  String _addrLabel = 'Home';
  final _flatCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  String _addrCity = 'Mumbai';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _flatCtrl.dispose();
    _buildingCtrl.dispose();
    _areaCtrl.dispose();
    _pincodeCtrl.dispose();
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
      profile = await _supabase.from('users').select('*').eq('id', authUser.id).single();
    } catch (_) {}

    if (profile == null) {
      profile = {
        'id': authUser.id,
        'full_name': authUser.userMetadata?['full_name'],
        'email': authUser.email,
        'phone': authUser.phone,
      };
      try {
        await _supabase.from('users').upsert(profile!);
      } catch (_) {}
    }

    List<Map<String, dynamic>> addrs = [];
    try {
      final result = await _supabase.from('addresses').select('*').eq('user_id', authUser.id);
      addrs = (result as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _user = profile;
        _nameCtrl.text = profile?['full_name'] ?? '';
        _emailCtrl.text = profile?['email'] ?? '';
        _addresses = addrs;
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;
    setState(() => _saving = true);
    try {
      await _supabase
          .from('users')
          .update({'full_name': _nameCtrl.text, 'email': _emailCtrl.text})
          .eq('id', _user!['id']);
      setState(() {
        _user = {..._user!, 'full_name': _nameCtrl.text, 'email': _emailCtrl.text};
        _saving = false;
        _editing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addAddress() async {
    if (_user == null || _areaCtrl.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in the area field'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    try {
      final data = await _supabase.from('addresses').insert({
        'user_id': _user!['id'],
        'label': _addrLabel,
        'flat_no': _flatCtrl.text.isEmpty ? null : _flatCtrl.text,
        'building': _buildingCtrl.text.isEmpty ? null : _buildingCtrl.text,
        'area': _areaCtrl.text,
        'city': _addrCity,
        'pincode': _pincodeCtrl.text.isEmpty ? null : _pincodeCtrl.text,
        'is_default': _addresses.isEmpty,
      }).select().single();
      setState(() {
        _addresses.add(data);
        _showAddAddr = false;
        _flatCtrl.clear();
        _buildingCtrl.clear();
        _areaCtrl.clear();
        _pincodeCtrl.clear();
        _addrLabel = 'Home';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address saved!'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save address'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAddress(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Address', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final displayName = _user?['full_name'] ?? _user?['phone'] ?? 'User';
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, displayName.length >= 2 ? 2 : 1).toUpperCase()
        : 'U';
    final phone = _user?['phone'] ?? '';
    final email = _user?['email'] ?? '';
    final subtitle = phone.isNotEmpty ? phone : email.isNotEmpty ? email : '—';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Hero Header ──────────────────────────────────
            _buildHero(initials, displayName, subtitle),
            const SizedBox(height: 16),
            // ── Edit Form (conditional) ─────────────────────
            if (_editing) ...[
              _buildEditForm(),
              const SizedBox(height: 16),
            ],
            // ── Stats ───────────────────────────────────────
            _buildStats(),
            const SizedBox(height: 16),
            // ── Address Section ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildAddressSection(),
            ),
            const SizedBox(height: 16),
            // ── Quick Links ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildQuickLinks(),
            ),
            const SizedBox(height: 24),
            // ── Logout ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildLogoutButton(),
            ),
            const SizedBox(height: 24),
            Text(
              'Cleenzo v1.0 · Made with ❤️ in Mumbai',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(String initials, String displayName, String subtitle) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06B6D4), Color(0xFF0891B2), Color(0xFF0369A1)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            children: [
              // Top row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _editing = !_editing),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        Icon(
                          _editing ? Icons.close : Icons.edit_outlined,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _editing ? 'Cancel' : 'Edit',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Avatar + info row
              Row(children: [
                Stack(children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white.withOpacity(0.35), Colors.white.withOpacity(0.15)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 12),
                    ),
                  ),
                ]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: Color(0xFFBAE6FD), fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        CircleAvatar(radius: 4, backgroundColor: Color(0xFF86EFAC)),
                        SizedBox(width: 6),
                        Text('Active member', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.person_outline_rounded, color: AppTheme.primary, size: 20),
            SizedBox(width: 8),
            Text('Edit Profile', style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          _editField('👤', 'Full name', _nameCtrl),
          const SizedBox(height: 10),
          _editField('✉️', 'Email address', _emailCtrl, type: TextInputType.emailAddress),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _editing = false),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(16)),
                  child: const Center(child: Text('Cancel', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700))),
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
                    gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Center(
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _editField(String icon, String hint, TextEditingController ctrl, {TextInputType? type}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFF),
        border: Border.all(color: const Color(0xFFA5F3FC)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Padding(padding: const EdgeInsets.only(left: 16), child: Text(icon, style: const TextStyle(fontSize: 16))),
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: type,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildStats() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(child: _stat('📋', '—', 'Bookings', const Color(0xFFECFEFF))),
          _divider(),
          Expanded(child: _stat('📍', '${_addresses.length}', 'Addresses', const Color(0xFFF5F3FF))),
          _divider(),
          Expanded(child: _stat('🎟️', '0', 'Coupons', const Color(0xFFFFFBEB))),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: const Color(0xFFF3F4F6));

  Widget _stat(String icon, String val, String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(height: 6),
        Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
        Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildAddressSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)],
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _addrExpanded = !_addrExpanded),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFECFEFF), borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: Text('📍', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Saved Addresses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827))),
                    Text(
                      _addresses.isEmpty ? 'No addresses saved yet' : '${_addresses.length} address${_addresses.length == 1 ? '' : 'es'} saved',
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                  ]),
                ),
                AnimatedRotation(
                  turns: _addrExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF9CA3AF), size: 24),
                ),
              ]),
            ),
          ),
          if (_addrExpanded) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  // Add address button
                  GestureDetector(
                    onTap: () => setState(() => _showAddAddr = !_showAddAddr),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFF),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('Add new address', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                      ]),
                    ),
                  ),
                  // Add address form
                  if (_showAddAddr) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFA5F3FC)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Address type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF6B7280))),
                          const SizedBox(height: 8),
                          Row(
                            children: ['Home', 'Office', 'Other'].map((l) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: GestureDetector(
                                  onTap: () => setState(() => _addrLabel = l),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: _addrLabel == l ? AppTheme.primary : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _addrLabel == l ? AppTheme.primary : const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${l == 'Home' ? '🏠' : l == 'Office' ? '🏢' : '📍'} $l',
                                        style: TextStyle(
                                          color: _addrLabel == l ? Colors.white : const Color(0xFF6B7280),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )).toList(),
                          ),
                          const SizedBox(height: 12),
                          ...[
                            {'hint': 'Flat / Unit no.', 'ctrl': _flatCtrl},
                            {'hint': 'Building / Society name', 'ctrl': _buildingCtrl},
                            {'hint': 'Area / Locality *', 'ctrl': _areaCtrl},
                            {'hint': 'Pincode', 'ctrl': _pincodeCtrl},
                          ].map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextField(
                              controller: f['ctrl'] as TextEditingController,
                              decoration: InputDecoration(
                                hintText: f['hint'] as String,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                          )),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _showAddAddr = false),
                                child: Container(
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(child: Text('Cancel', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: _addAddress,
                                child: Container(
                                  height: 46,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.35), blurRadius: 10)],
                                  ),
                                  child: const Center(child: Text('Save address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ],
                  // Existing addresses list
                  ..._addresses.map((addr) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF0F0F0)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB))),
                          child: Center(child: Text(
                            addr['label'] == 'Home' ? '🏠' : addr['label'] == 'Office' ? '🏢' : '📍',
                            style: const TextStyle(fontSize: 18),
                          )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(addr['label'] ?? 'Address', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              if (addr['is_default'] == true) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFFECFEFF), borderRadius: BorderRadius.circular(20)),
                                  child: const Text('Default', style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              [if (addr['flat_no'] != null) addr['flat_no'], if (addr['building'] != null) addr['building'], addr['area'], addr['city']].where((e) => e != null).join(', '),
                              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                        GestureDetector(
                          onTap: () => _deleteAddress(addr['id']),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 16),
                          ),
                        ),
                      ]),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickLinks() {
    final links = [
      {
        'icon': '📋',
        'label': 'My Bookings',
        'sub': 'View all past & upcoming',
        'route': '/bookings',
        'color': const Color(0xFFECFEFF),
        'iconColor': AppTheme.primary,
      },
      {
        'icon': '🎟️',
        'label': 'Offers & Coupons',
        'sub': 'Save more on every order',
        'route': '/offers',
        'color': const Color(0xFFFFFBEB),
        'iconColor': const Color(0xFFF59E0B),
      },
      {
        'icon': '💬',
        'label': 'Help & Support',
        'sub': 'Get answers & contact us',
        'route': '/help',
        'color': const Color(0xFFECFDF5),
        'iconColor': const Color(0xFF10B981),
      },
      {
        'icon': '📜',
        'label': 'Terms & Privacy',
        'sub': 'Legal information',
        'route': '/terms',
        'color': const Color(0xFFEFF6FF),
        'iconColor': const Color(0xFF3B82F6),
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)],
      ),
      child: Column(
        children: links.asMap().entries.map((entry) {
          final i = entry.key;
          final link = entry.value;
          return GestureDetector(
            onTap: () => context.go(link['route'] as String),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: i < links.length - 1 ? const Border(bottom: BorderSide(color: Color(0xFFF5F5F7), width: 1)) : null,
              ),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: link['color'] as Color, borderRadius: BorderRadius.circular(13)),
                  child: Center(child: Text(link['icon'] as String, style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(link['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2937))),
                    Text(link['sub'] as String, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                  ]),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFD1D5DB), size: 13),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
            SizedBox(width: 10),
            Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
