import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});
  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _addresses = [];
  bool _loading  = true;
  bool _deleting = false;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _bg     = Color(0xFFF8FAFC);
  static const _red    = Color(0xFFDC2626);
  static const _redLt  = Color(0xFFFEF2F2);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _getUserId() async {
    return await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
  }

  Future<void> _load() async {
    final userId = await _getUserId();
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('addresses')
          .select('*')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('is_default', ascending: false)
          .order('created_at', ascending: true);
      debugPrint('Loaded ${(data as List).length} addresses');
      if (mounted) {
        setState(() {
          _addresses = (data).cast<Map<String, dynamic>>();
          _loading   = false;
        });
      }
    } catch (e) {
      debugPrint('LOAD ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDefault(String id) async {
    final userId = await _getUserId();
    if (userId == null) return;
    HapticFeedback.selectionClick();
    try {
      await _supabase
          .from('addresses')
          .update({'is_default': false})
          .eq('user_id', userId);
      await _supabase
          .from('addresses')
          .update({'is_default': true})
          .eq('id', id);
      _load();
      _snack('Default address updated ✓');
    } catch (e) {
      debugPrint('SET DEFAULT ERROR: $e');
      _snack('Failed to update: $e', isError: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> addr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                  color: _redLt, shape: BoxShape.circle),
              child: const Center(
                  child: Text('🗑️',
                      style: TextStyle(fontSize: 28)))),
            const SizedBox(height: 16),
            const Text('Delete Address?',
                style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 8),
            Text(
              '${addr['label'] ?? 'Address'} — '
              '${addr['area'] ?? ''}, ${addr['city'] ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14)),
                    child: const Center(
                      child: Text('Cancel',
                          style: TextStyle(color: _muted,
                              fontWeight: FontWeight.w700)))))),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(14)),
                    child: const Center(
                      child: Text('Delete',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800)))))),
            ]),
          ]),
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);
    HapticFeedback.mediumImpact();

    try {
      final id = addr['id']?.toString() ?? '';
      debugPrint('Attempting to delete address id: $id');

      if (id.isEmpty) {
        _snack('Invalid address ID', isError: true);
        setState(() => _deleting = false);
        return;
      }

      // Soft delete — preserves booking history
      final response = await _supabase
          .from('addresses')
          .update({'is_deleted': true})
          .eq('id', id)
          .select();

      debugPrint('Soft delete response: $response');

      // If deleted was default → promote next one
      if (addr['is_default'] == true) {
        final remaining = _addresses
            .where((a) => a['id'] != addr['id'])
            .toList();
        if (remaining.isNotEmpty) {
          await _supabase
              .from('addresses')
              .update({'is_default': true})
              .eq('id', remaining.first['id'].toString());
        }
      }

      _snack('Address deleted ✓');
      await _load();
    } catch (e) {
      debugPrint('DELETE ERROR: $e');
      _snack('Error: ${e.toString().split('\n').first}',
          isError: true);
    }

    if (mounted) setState(() => _deleting = false);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _red : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3)));
  }

  String _addressLine(Map<String, dynamic> addr) {
    return [
      if ((addr['flat_no'] ?? '').toString().isNotEmpty)
        addr['flat_no'],
      if ((addr['building'] ?? '').toString().isNotEmpty)
        addr['building'],
      addr['area'],
      addr['city'],
    ].where((e) => e != null && e.toString().isNotEmpty)
        .join(', ');
  }

  String _emoji(String? label) {
    switch (label?.toLowerCase()) {
      case 'home':   return '🏠';
      case 'office': return '🏢';
      default:       return '📍';
    }
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [

        // ── Header ──────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C4A6E), _cyanDk, _cyan],
            ),
          ),
          child: Stack(children: [
            Positioned(top: -30, right: -30,
              child: Container(width: 140, height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle))),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25))),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 16))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Saved Addresses',
                        style: TextStyle(color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    Text(
                      '${_addresses.length} address'
                      '${_addresses.length == 1 ? '' : 'es'} saved',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11)),
                  ])),
                  GestureDetector(
                    onTap: () => context.push('/location-gate'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30))),
                      child: const Row(children: [
                        Icon(Icons.add_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Add New',
                            style: TextStyle(color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ]))),
                ]),
              ),
            ),
          ]),
        ),

        // ── Body ────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _cyan))
              : _addresses.isEmpty
                  ? _buildEmpty()
                  : Stack(children: [
                      ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            16, 16, 16, botPad + 16),
                        itemCount: _addresses.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _buildAddressCard(_addresses[i]),
                      ),
                      if (_deleting)
                        Container(
                          color: Colors.black
                              .withValues(alpha: 0.08),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: _cyan))),
                    ]),
        ),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFECFEFF),
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFFA5F3FC), width: 2)),
            child: const Center(
                child: Text('📍',
                    style: TextStyle(fontSize: 44)))),
          const SizedBox(height: 20),
          const Text('No saved addresses',
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8),
          const Text(
            'Add your home or office address\nfor faster bookings',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13,
                height: 1.5)),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => context.push('/location-gate'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_cyan, _cyanDk]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                    color: _cyan.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5))]),
              child: const Row(mainAxisSize: MainAxisSize.min,
                  children: [
                Icon(Icons.add_location_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Add Address',
                    style: TextStyle(color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ])),
          ),
        ]),
      ),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> addr) {
    final isDefault = addr['is_default'] == true;
    final label     = addr['label'] as String? ?? 'Address';
    final emoji     = _emoji(label);
    final line      = _addressLine(addr);
    final pincode   = addr['pincode'] as String? ?? '';
    final landmark  = addr['landmark'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDefault ? _cyan : _border,
            width: isDefault ? 1.5 : 1),
        boxShadow: [BoxShadow(
            color: isDefault
                ? _cyan.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4))]),
      child: Column(children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: isDefault
                    ? const Color(0xFFECFEFF)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDefault
                        ? const Color(0xFFA5F3FC)
                        : _border)),
              child: Center(child: Text(emoji,
                  style: const TextStyle(fontSize: 22)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                if (isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFA5F3FC))),
                    child: const Text('Default',
                        style: TextStyle(color: _cyanDk,
                            fontSize: 9,
                            fontWeight: FontWeight.w800))),
                ],
              ]),
              const SizedBox(height: 3),
              Text(line,
                  style: const TextStyle(
                      color: _muted, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (landmark.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('📌 $landmark',
                    style: const TextStyle(
                        color: _faint, fontSize: 11)),
              ],
              if (pincode.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('📮 $pincode',
                    style: const TextStyle(
                        color: _faint, fontSize: 11)),
              ],
            ])),
          ]),
        ),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Divider(height: 1,
              color: Color(0xFFF3F4F6))),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [

            if (!isDefault) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => _setDefault(
                      addr['id'].toString()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFA5F3FC))),
                    child: const Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                      Icon(
                          Icons.check_circle_outline_rounded,
                          color: _cyanDk, size: 15),
                      SizedBox(width: 6),
                      Text('Set as Default',
                          style: TextStyle(color: _cyanDk,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ])),
                )),
              const SizedBox(width: 8),
            ],

            if (isDefault) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border)),
                  child: const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                    Icon(Icons.home_rounded,
                        color: _faint, size: 15),
                    SizedBox(width: 6),
                    Text('Your default address',
                        style: TextStyle(color: _faint,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ])),
              ),
              const SizedBox(width: 8),
            ],

            GestureDetector(
              onTap: () => _delete(addr),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: _redLt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _red.withValues(alpha: 0.25))),
                child: const Row(children: [
                  Icon(Icons.delete_outline_rounded,
                      color: _red, size: 15),
                  SizedBox(width: 6),
                  Text('Delete',
                      style: TextStyle(color: _red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ])),
            ),
          ]),
        ),
      ]),
    );
  }
}