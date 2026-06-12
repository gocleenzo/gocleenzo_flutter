import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final bool isNew;

  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.isNew = false,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _booking;
  bool _loading = true;

  static const _statusColor = {
    'pending': Color(0xFFF59E0B),
    'confirmed': Color(0xFF06B6D4),
    'in_progress': Color(0xFF3B82F6),
    'completed': Color(0xFF10B981),
    'cancelled': Color(0xFFEF4444),
  };

  static const _statusLabel = {
    'pending': 'Pending',
    'confirmed': 'Confirmed',
    'in_progress': 'In Progress',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _supabase
          .from('bookings')
          .select('*, services(name, base_price), addresses(label, flat_no, building, area, city)')
          .eq('id', widget.bookingId)
          .single();
      if (mounted) setState(() { _booking = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) { return '—'; }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final m = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    } catch (_) { return '—'; }
  }

  String _formatAddress(Map<String, dynamic>? addr) {
    if (addr == null) return '—';
    return [
      if (addr['flat_no'] != null) addr['flat_no'],
      if (addr['building'] != null) addr['building'],
      addr['area'],
      addr['city'],
    ].where((e) => e != null).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_booking == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(title: const Text('Booking Details'), backgroundColor: Colors.white, foregroundColor: Color(0xFF111827), elevation: 0),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final b = _booking!;
    final svc = b['services'] as Map<String, dynamic>?;
    final addr = b['addresses'] as Map<String, dynamic>?;
    final scheduledAt = b['scheduled_at'] as String?;
    final status = b['status'] as String? ?? 'pending';
    final statusColor = _statusColor[status] ?? const Color(0xFF9CA3AF);
    final statusText = _statusLabel[status] ?? status;
    final otp = b['otp']?.toString();
    final finalAmt = b['final_amount'] ?? b['base_price'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        context.go('/bookings');
                      }
                    },
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Booking Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.3))),
                    child: Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Success banner for new bookings
                if (widget.isNew) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF6EE7B7)),
                    ),
                    child: const Row(children: [
                      Text('🎉', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Booking Confirmed!', style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w900, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Your booking has been placed successfully. We\'ll reach out soon!', style: TextStyle(color: Color(0xFF047857), fontSize: 12)),
                      ])),
                    ]),
                  ),
                ],

                // Service card
                _infoCard(
                  icon: '🧹',
                  label: 'Service',
                  value: svc?['name'] ?? '—',
                  bgColor: const Color(0xFFECFEFF),
                ),
                // Date & Time
                Row(children: [
                  Expanded(child: _infoCard(icon: '📅', label: 'Date', value: _formatDate(scheduledAt), bgColor: const Color(0xFFF0F9FF))),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(icon: '⏰', label: 'Time', value: _formatTime(scheduledAt), bgColor: const Color(0xFFF5F3FF))),
                ]),
                _infoCard(icon: '📍', label: 'Address', value: _formatAddress(addr), bgColor: const Color(0xFFFFF7ED)),

                // Price card
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Total Amount', style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 12, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Inclusive of all charges', style: TextStyle(color: Color(0xFF7DD3FC), fontSize: 11)),
                    ]),
                    Text(
                      '₹${finalAmt ?? '—'}',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                  ]),
                ),

                // OTP card
                if (otp != null && otp.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: otp));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('OTP copied!'), backgroundColor: Color(0xFF10B981)),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(14)),
                          child: const Center(child: Text('🔑', style: TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Verification OTP', style: TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text(otp, style: const TextStyle(color: Color(0xFF78350F), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4)),
                          const Text('Show this to your cleaner to verify arrival', style: TextStyle(color: Color(0xFFA16207), fontSize: 11)),
                        ])),
                        const Icon(Icons.copy_outlined, color: Color(0xFFD97706), size: 18),
                      ]),
                    ),
                  ),

                // Back to bookings button
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => context.go('/bookings'),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.receipt_long_outlined, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text('View All Bookings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({required String icon, required String label, required String value, required Color bgColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(13)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827))),
        ])),
      ]),
    );
  }
}
