import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _bg     = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('notifications')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications =
              (data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
      // Mark all as read
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('notifications load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeAgo(String createdAt) {
    final dt  = DateTime.tryParse(createdAt)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Map<String, dynamic> _typeConfig(String? type) {
    switch (type) {
      case 'booking_assigned':
        return {'emoji': '✅', 'color': const Color(0xFF059669),
            'bg': const Color(0xFFECFDF5)};
      case 'booking_completed':
        return {'emoji': '🎉', 'color': const Color(0xFF7C3AED),
            'bg': const Color(0xFFF5F3FF)};
      case 'booking_cancelled':
        return {'emoji': '❌', 'color': const Color(0xFFDC2626),
            'bg': const Color(0xFFFEF2F2)};
      default:
        return {'emoji': '🔔', 'color': _cyan, 'bg': const Color(0xFFECFEFF)};
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
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
                    const Text('Notifications',
                        style: TextStyle(color: Colors.white,
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(
                      '${_notifications.length} notification'
                      '${_notifications.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11)),
                  ])),
                  // Unread count badge
                  if (_notifications.any((n) => n['is_read'] == false))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30))),
                      child: Text(
                        '${_notifications.where((n) => n['is_read'] == false).length} new',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.w700))),
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
              : _notifications.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _cyan,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            16, 16, 16, botPad + 16),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _buildNotificationCard(
                                _notifications[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFFECFEFF),
            shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFFA5F3FC), width: 2)),
          child: const Center(
              child: Text('🔔',
                  style: TextStyle(fontSize: 40)))),
        const SizedBox(height: 20),
        const Text('No notifications yet',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 8),
        const Text(
          'You\'ll see booking updates\nand offers here',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13,
              height: 1.5)),
      ]),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final isRead   = n['is_read'] == true;
    final type     = n['type'] as String? ?? 'general';
    final config   = _typeConfig(type);
    final bookingId = n['booking_id'] as String?;
    final timeAgo  = _timeAgo(n['created_at'] as String);

    return GestureDetector(
      onTap: () {
        if (bookingId != null) {
          context.push('/bookings/$bookingId');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFECFEFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isRead
                  ? _border
                  : const Color(0xFFA5F3FC),
              width: isRead ? 1 : 1.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(
                  alpha: isRead ? 0.03 : 0.06),
              blurRadius: 10, offset: const Offset(0, 3))]),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Icon
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: config['bg'] as Color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: (config['color'] as Color)
                      .withValues(alpha: 0.2))),
            child: Center(child: Text(
                config['emoji'] as String,
                style: const TextStyle(fontSize: 22)))),
          const SizedBox(width: 12),

          // Content
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Expanded(
                child: Text(n['title'] as String,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: isRead
                            ? FontWeight.w700
                            : FontWeight.w900,
                        color: _ink)),
              ),
              if (!isRead)
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                      color: _cyan,
                      shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 4),
            Text(n['body'] as String,
                style: const TextStyle(
                    color: _muted, fontSize: 12,
                    height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              Text(timeAgo,
                  style: const TextStyle(
                      color: _faint, fontSize: 11,
                      fontWeight: FontWeight.w500)),
              if (bookingId != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFEFF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFA5F3FC))),
                  child: const Text('View Booking →',
                      style: TextStyle(color: _cyanDk,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}