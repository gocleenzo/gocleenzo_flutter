import 'package:flutter/material.dart';

/// Central design tokens for the Worker app.
/// Swap these for your Cleenzo brand colors if you want a different look —
/// every worker screen reads from here, so changing one value re-themes all.
class WC {
  WC._();

  // Brand
  static const Color primary = Color(0xFF0D9488); // teal-600
  static const Color primaryDark = Color(0xFF0F766E); // teal-700
  static const Color primaryLight = Color(0xFF14B8A6); // teal-500
  static const Color primarySoft = Color(0xFFE6FBF7); // tinted bg

  // Surfaces
  static const Color bg = Color(0xFFF5F7F8);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE6EAED);

  // Text
  static const Color text = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color faint = Color(0xFF94A3B8);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFE7F8EE);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3E2);
  static const Color info = Color(0xFF2563EB);
  static const Color infoSoft = Color(0xFFE8F0FE);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFDECEC);

  // Shadows
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  // Radii
  static const double r = 18;
  static const double rSm = 12;
}

/// Maps a booking status string to a label + colors for badges.
class StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const StatusStyle(this.label, this.fg, this.bg);

  static StatusStyle of(String? status) {
    switch (status) {
      case 'pending':
        return const StatusStyle('Pending', WC.muted, Color(0xFFEFF2F5));
      case 'accepted':
        return const StatusStyle('Assigned', WC.warning, WC.warningSoft);
      case 'in_progress':
        return const StatusStyle('In progress', WC.info, WC.infoSoft);
      case 'completed':
        return const StatusStyle('Completed', WC.success, WC.successSoft);
      case 'cancelled':
        return const StatusStyle('Cancelled', WC.danger, WC.dangerSoft);
      default:
        return StatusStyle(status ?? '—', WC.muted, const Color(0xFFEFF2F5));
    }
  }
}
