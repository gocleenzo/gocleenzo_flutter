import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';

class AddressConfirmScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String area;
  final String city;
  final String pincode;
  final String fullAddress;
  final bool   isOnboarding;

  const AddressConfirmScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.area,
    required this.city,
    required this.pincode,
    required this.fullAddress,
    this.isOnboarding = false,
  });

  @override
  State<AddressConfirmScreen> createState() => _AddressConfirmScreenState();
}

class _AddressConfirmScreenState extends State<AddressConfirmScreen> {
  final _supabase     = Supabase.instance.client;
  final _flatCtrl     = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();

  String  _label  = 'Home';
  bool    _saving = false;
  String? _error;

  // ── Allowed service areas ─────────────────────────────────────
  static const _allowedAreas = [
    'vile parle', 'vileparle', 'vile-parle',
    'andheri', 'andheri west', 'andheri east',
    'juhu', 'santacruz', 'santa cruz',
    'jogeshwari', 'khar', 'bandra',
  ];

  bool _isServiceable() {
    final combined = '${widget.area.toLowerCase()} ${widget.city.toLowerCase()}';
    return _allowedAreas.any((a) => combined.contains(a));
  }

  @override
  void dispose() {
    _flatCtrl.dispose();
    _buildingCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  void _showNotServiceable() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2), shape: BoxShape.circle),
              child: const Center(
                  child: Text('😔', style: TextStyle(fontSize: 36))),
            ),
            const SizedBox(height: 20),
            const Text('Not Available Yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A))),
            const SizedBox(height: 10),
            const Text(
              'We currently serve only Vile Parle & Andheri '
              'areas in Mumbai.\n\nWe\'re expanding soon — stay tuned!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFEFF),
                borderRadius: BorderRadius.circular(12)),
              child: const Text(
                '📍 Vile Parle · Andheri · Juhu\nSantacruz · Jogeshwari · Khar',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF0891B2), fontSize: 12,
                    fontWeight: FontWeight.w700, height: 1.6),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to map
              },
              child: Container(
                width: double.infinity, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14)),
                child: const Center(
                  child: Text('Change Location',
                      style: TextStyle(fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B), fontSize: 14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _save() async {
    // Check serviceability first
    if (!_isServiceable()) {
      _showNotServiceable();
      return;
    }

    setState(() { _saving = true; _error = null; });

    final userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final existing = await _supabase
          .from('addresses')
          .select('id')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .limit(1);

      final isFirst = (existing as List).isEmpty;

      await _supabase.from('addresses').insert({
        'user_id':      userId,
        'label':        _label,
        'flat_no':      _flatCtrl.text.trim().isEmpty ? null : _flatCtrl.text.trim(),
        'building':     _buildingCtrl.text.trim().isEmpty ? null : _buildingCtrl.text.trim(),
        'area':         widget.area,
        'city':         widget.city,
        'pincode':      widget.pincode,
        'full_address': widget.fullAddress,
        'latitude':     widget.lat,
        'longitude':    widget.lng,
        'landmark':     _landmarkCtrl.text.trim().isEmpty ? null : _landmarkCtrl.text.trim(),
        'is_default':   isFirst,
      });

      if (mounted) {
        if (widget.isOnboarding) {
          context.go('/services'); // ← go to services after onboarding
        } else {
          Navigator.pop(context, true); // ← back to account screen
        }
      }
    } catch (e) {
      debugPrint('Save address error: $e');
      setState(() {
        _error = 'Failed to save address. Try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(children: [

        // ── Header ────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Confirm Address',
                    style: TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              // Detected address card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8EDF2)),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8)],
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.location_on_rounded,
                        color: Color(0xFF06B6D4), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      widget.area.isNotEmpty ? widget.area : widget.city,
                      style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 15, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 3),
                    Text(widget.fullAddress,
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (widget.pincode.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('📮 ${widget.pincode}',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11)),
                    ],
                  ])),
                ]),
              ),

              // Label selector
              const Text('SAVE AS', style: TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              Row(
                children: ['Home', 'Office', 'Other'].map((lbl) {
                  final icons = {'Home': '🏠', 'Office': '🏢', 'Other': '📍'};
                  final active = _label == lbl;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _label = lbl),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFECFEFF) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: active
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFFE8EDF2),
                            width: active ? 1.5 : 1),
                        ),
                        child: Column(children: [
                          Text(icons[lbl]!,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(lbl, style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: active
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFF64748B),
                          )),
                        ]),
                      ),
                    ),
                  ));
                }).toList(),
              ),

              const SizedBox(height: 20),
              _field(controller: _flatCtrl,
                  label: 'FLAT / HOUSE NO.',
                  hint: 'e.g. 304, A Wing (optional)'),
              const SizedBox(height: 14),
              _field(controller: _buildingCtrl,
                  label: 'BUILDING / SOCIETY',
                  hint: 'e.g. Lotus Heights (optional)'),
              const SizedBox(height: 14),
              _field(controller: _landmarkCtrl,
                  label: 'NEARBY LANDMARK',
                  hint: 'e.g. Near SBI Bank (optional)'),
              const SizedBox(height: 24),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626),
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],

              // Save button
              GestureDetector(
                onTap: _saving ? null : _save,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.4),
                      blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 10),
                              Text('Save Address',
                                  style: TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _field({required TextEditingController controller,
      required String label, required String hint}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          color: Color(0xFF9CA3AF), fontSize: 10,
          fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8EDF2))),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8EDF2))),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
                color: Color(0xFF06B6D4), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    ]);
  }
}