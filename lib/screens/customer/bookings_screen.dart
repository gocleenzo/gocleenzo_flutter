import 'dart:math';
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
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  late AnimationController _headerAnimController;
  late AnimationController _shimmerController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _shimmerAnim;

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _past = [];
  bool _loading = true;

  // Status config
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

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _headerFade = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOut,
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOutCubic,
    ));

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _headerAnimController.forward();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _headerAnimController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
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
        if (status == 'completed' ||
            status == 'cancelled' ||
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
      backgroundColor: const Color(0xFFF0FDFF),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? _buildShimmerList()
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

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return SlideTransition(
      position: _headerSlide,
      child: FadeTransition(
        opacity: _headerFade,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0891B2), Color(0xFF06B6D4), Color(0xFF22D3EE)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      // Icon avatar
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.3), width: 1),
                        ),
                        child: const Center(
                          child:
                              Text('🧹', style: TextStyle(fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'My Bookings',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'Track & manage your services',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Refresh button
                      GestureDetector(
                        onTap: _load,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 1),
                          ),
                          child: const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Stats row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _statPill('${_upcoming.length}', 'Upcoming',
                          Icons.upcoming_outlined),
                      const SizedBox(width: 10),
                      _statPill(
                          '${_past.length}', 'Completed', Icons.check_circle_outline),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Tab bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(4),
                      labelColor: const Color(0xFF0891B2),
                      unselectedLabelColor: Colors.white.withOpacity(0.85),
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Upcoming'),
                              if (_upcoming.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF06B6D4),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_upcoming.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Tab(text: 'Past'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Curved bottom clip
                ClipPath(
                  clipper: _WaveClipper(),
                  child: Container(
                    height: 22,
                    color: const Color(0xFFF0FDFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statPill(String count, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withOpacity(0.22), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(count,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── List ──────────────────────────────────────────────────────────────────

  Widget _buildList(List<Map<String, dynamic>> bookings,
      {required bool isUpcoming}) {
    if (bookings.isEmpty) return _buildEmptyState(isUpcoming);

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF06B6D4),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        itemCount: bookings.length,
        itemBuilder: (_, i) => _AnimatedCard(
          delay: Duration(milliseconds: 60 * i),
          child: _bookingCard(bookings[i]),
        ),
      ),
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isUpcoming) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Layered blob + emoji
            SizedBox(
              width: 130,
              height: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCFFAFE),
                      borderRadius: BorderRadius.circular(44),
                    ),
                  ),
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F7FF),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: const Color(0xFFBAE6FD), width: 1.5),
                    ),
                  ),
                  Text(
                    isUpcoming ? '📅' : '🧾',
                    style: const TextStyle(fontSize: 42),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isUpcoming ? 'Nothing scheduled yet' : 'No history yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0E7490),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isUpcoming
                  ? 'Book a cleaning and it will show up here.'
                  : 'Your completed and cancelled bookings will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (isUpcoming) ...[
              const SizedBox(height: 28),
              _PulseButton(
                onTap: () => context.go('/services'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Book a Service',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Shimmer Loading ──────────────────────────────────────────────────────

  Widget _buildShimmerList() {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, __) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          itemCount: 4,
          itemBuilder: (_, i) => _shimmerCard(),
        );
      },
    );
  }

  Widget _shimmerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06B6D4).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AnimatedBuilder(
          animation: _shimmerAnim,
          builder: (_, __) {
            return ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0xFFE0F7FF),
                  Color(0xFFF0FDFF),
                  Color(0xFFBAE6FD),
                  Color(0xFFF0FDFF),
                  Color(0xFFE0F7FF),
                ],
                stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                transform: _SlidingGradientTransform(_shimmerAnim.value),
              ).createShader(bounds),
              child: Container(color: Colors.white),
            );
          },
        ),
      ),
    );
  }

  // ─── Booking Card ─────────────────────────────────────────────────────────

  Widget _bookingCard(Map<String, dynamic> booking) {
    final service = booking['services'] as Map<String, dynamic>?;
    final name = service?['name'] as String? ?? 'Cleaning Service';
    final status = booking['status'] as String? ?? 'pending';
    final scheduledRaw = booking['scheduled_at'] as String?;
    final scheduled =
        scheduledRaw != null ? DateTime.tryParse(scheduledRaw) : null;
    final finalAmt = booking['final_amount'] ?? booking['base_price'];

    final statusColor = _statusColor[status] ?? const Color(0xFF9CA3AF);
    final statusText = _statusLabel[status] ?? status;
    final statusEmoji = _statusEmoji[status] ?? '•';

    String formattedDate = '—';
    String formattedTime = '—';
    if (scheduled != null) {
      final local = scheduled.toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      formattedDate = '${local.day} ${months[local.month - 1]}';
      final h = local.hour > 12
          ? local.hour - 12
          : (local.hour == 0 ? 12 : local.hour);
      final m = local.minute.toString().padLeft(2, '0');
      final ampm = local.hour >= 12 ? 'PM' : 'AM';
      formattedTime = '$h:$m $ampm';
    }

    return GestureDetector(
      onTap: () => context.push('/bookings/${booking['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFE0F7FF),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF06B6D4).withOpacity(0.07),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.8),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Left accent bar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      statusColor,
                      statusColor.withOpacity(0.4),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                  ),
                ),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF06B6D4).withOpacity(0.15),
                          const Color(0xFF22D3EE).withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFBAE6FD),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: Text('🧹', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Main content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Color(0xFF0E4F5C),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: statusColor.withOpacity(0.25),
                                    width: 1),
                              ),
                              child: Text(
                                '$statusEmoji $statusText',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _chip(Icons.calendar_today_outlined, formattedDate),
                            const SizedBox(width: 8),
                            _chip(Icons.access_time_outlined, formattedTime),
                            const Spacer(),
                            // Price
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${finalAmt ?? '—'}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0891B2),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFECFEFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBAE6FD), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: const Color(0xFF0891B2)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0E7490),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Wave Clipper ─────────────────────────────────────────────────────────────

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, 0);
    path.quadraticBezierTo(size.width / 4, size.height,
        size.width / 2, size.height * 0.5);
    path.quadraticBezierTo(
        3 * size.width / 4, 0, size.width, size.height * 0.5);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

// ─── Staggered Animated Card ──────────────────────────────────────────────────

class _AnimatedCard extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _AnimatedCard({required this.child, required this.delay});

  @override
  State<_AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<_AnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
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

// ─── Pulse Button ─────────────────────────────────────────────────────────────

class _PulseButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PulseButton({required this.child, required this.onTap});

  @override
  State<_PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<_PulseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06B6D4).withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ─── Shimmer Gradient Transform ───────────────────────────────────────────────

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}