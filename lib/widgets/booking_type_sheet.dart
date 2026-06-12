import 'package:flutter/material.dart';

/// Shows "Instant" vs "Schedule" picker bottom sheet.
/// Call [BookingTypeSheet.show] and await the result: 'instant' | 'schedule' | null.
class BookingTypeSheet extends StatelessWidget {
  final String serviceName;
  final int price;

  const BookingTypeSheet({super.key, required this.serviceName, required this.price});

  static Future<String?> show(BuildContext context, {required String serviceName, required int price}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (_) => BookingTypeSheet(serviceName: serviceName, price: price),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        Center(child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 5,
          decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)),
        )),

        const Text('How would you like it?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        const SizedBox(height: 4),
        Text('$serviceName · ₹$price',
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        const Text('Choose how your booking should be handled',
            style: TextStyle(fontSize: 11, color: Color(0xFFB0BAC9)),
            textAlign: TextAlign.center),

        const SizedBox(height: 24),

        // Instant
        _TypeTile(
          emoji: '⚡',
          title: 'Book Instant',
          subtitle: 'Pro dispatched now · arrives within 2 hrs',
          badge: 'FASTEST',
          badgeColor: const Color(0xFF059669),
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFF6EE7B7),
          accent: const Color(0xFF059669),
          onTap: () => Navigator.pop(context, 'instant'),
        ),

        const SizedBox(height: 12),

        // Schedule
        _TypeTile(
          emoji: '📅',
          title: 'Schedule for Later',
          subtitle: 'Choose your preferred date & time slot',
          badge: 'FLEXIBLE',
          badgeColor: const Color(0xFFD97706),
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFFCD34D),
          accent: const Color(0xFFD97706),
          onTap: () => Navigator.pop(context, 'schedule'),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _TypeTile extends StatelessWidget {
  final String emoji, title, subtitle, badge;
  final Color badgeColor, bg, border, accent;
  final VoidCallback onTap;

  const _TypeTile({
    required this.emoji, required this.title, required this.subtitle,
    required this.badge, required this.badgeColor,
    required this.bg, required this.border, required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 10)],
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: accent)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: accent),
        ]),
      ),
    );
  }
}