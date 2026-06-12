import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../utils/theme.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _past = [];
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

  static const _statusEmoji = {
    'pending': '⏳',
    'confirmed': '✅',
    'in_progress': '🧹',
    'completed': '🎉',
    'cancelled': '❌',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from('bookings')
          .select('*, services(name, base_price)')
          .eq('customer_id', userId)
          .order('scheduled_at', ascending: false);

      final now = DateTime.now();
      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];

      for (final b in data) {
        final scheduled = DateTime.tryParse(b['scheduled_at'] ?? '');
        final status = b['status'] as String? ?? '';
        if (status == 'completed' || status == 'cancelled' ||
            (scheduled != null && scheduled.isBefore(now))) {
          past.add(b);
        } else {
          upcoming.add(b);
        }
      }

      if (mounted) {
        setState(() {
          _upcoming = upcoming;
          _past = past;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('My Bookings', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                            Text('Track your cleaning services', style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 13)),
                          ]),
                        ),
                        GestureDetector(
                          onTap: _load,
                          child: Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(3),
                      labelColor: AppTheme.primary,
                      unselectedLabelColor: Colors.white.withOpacity(0.8),
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      tabs: [
                        Tab(
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('Upcoming'),
                            if (_upcoming.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                                child: Text('${_upcoming.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ]),
                        ),
                        const Tab(text: 'Past'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(_upcoming, isUpcoming: true),
                      _buildList(_past, isUpcoming: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> bookings, {required bool isUpcoming}) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: const Color(0xFFECFEFF), borderRadius: BorderRadius.circular(24)),
              child: Center(child: Text(isUpcoming ? '📅' : '🧾', style: const TextStyle(fontSize: 40))),
            ),
            const SizedBox(height: 20),
            Text(
              isUpcoming ? 'No upcoming bookings' : 'No past bookings',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your bookings will appear here.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            if (isUpcoming) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => context.go('/services'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 5))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cleaning_services_outlined, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Book a Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  ]),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: bookings.length,
        itemBuilder: (_, i) => _bookingCard(bookings[i]),
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> booking) {
    final service = booking['services'] as Map<String, dynamic>?;
    final name = service?['name'] as String? ?? 'Cleaning Service';
    final status = booking['status'] as String? ?? 'pending';
    final scheduledRaw = booking['scheduled_at'] as String?;
    final scheduled = scheduledRaw != null ? DateTime.tryParse(scheduledRaw) : null;
    final finalAmt = booking['final_amount'] ?? booking['base_price'];

    final statusColor = _statusColor[status] ?? const Color(0xFF9CA3AF);
    final statusText = _statusLabel[status] ?? status;
    final statusEmoji = _statusEmoji[status] ?? '•';

    String formattedDate = '—';
    String formattedTime = '—';
    if (scheduled != null) {
      final local = scheduled.toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      formattedDate = '${local.day} ${months[local.month - 1]}';
      final h = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
      final m = local.minute.toString().padLeft(2, '0');
      final ampm = local.hour >= 12 ? 'PM' : 'AM';
      formattedTime = '$h:$m $ampm';
    }

    return GestureDetector(
      onTap: () => context.push('/bookings/${booking['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            // Top bar with status color
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF111827)),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          '$statusEmoji $statusText',
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _chip(Icons.calendar_today_outlined, formattedDate),
                      const SizedBox(width: 10),
                      _chip(Icons.access_time_outlined, formattedTime),
                      const Spacer(),
                      Text(
                        '₹${finalAmt ?? '—'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
