import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customer/services_screen.dart';
import 'screens/customer/service_detail_screen.dart';
import 'screens/customer/booking_flow_screen.dart';
import 'screens/customer/bookings_screen.dart';
import 'screens/customer/booking_detail_screen.dart';
import 'screens/customer/account_screen.dart';
import 'screens/customer/offers_screen.dart';
import 'screens/customer/help_screen.dart';
import 'screens/customer/terms_screen.dart';
import 'screens/worker/worker_dashboard_screen.dart';
import 'screens/worker/worker_job_detail_screen.dart';
import 'screens/worker/worker_earnings_screen.dart';
import 'screens/worker/worker_history_screen.dart';
import 'screens/worker/worker_profile_screen.dart';
import 'screens/admin/admin_overview_screen.dart';
import 'screens/admin/admin_bookings_screen.dart';
import 'screens/admin/admin_workers_screen.dart';
import 'screens/admin/admin_complaints_screen.dart';
import 'screens/admin/admin_promos_screen.dart';
import 'screens/admin/admin_reports_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/worker/worker_shell.dart';
import 'screens/admin/admin_shell.dart';

final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final user   = Supabase.instance.client.auth.currentUser;
    final isAuth = ['/', '/login'].contains(state.matchedLocation);
    if (user == null && !isAuth) return '/login';
    return null;
  },
  routes: [
    GoRoute(path: '/',      builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/help',  builder: (_, __) => const HelpScreen()),

    // ── Customer Shell ──────────────────────────────────────
    ShellRoute(
      builder: (_, __, child) => CustomerShell(child: child),
      routes: [
        GoRoute(path: '/services',  builder: (_, __) => const ServicesScreen()),
        GoRoute(path: '/bookings',  builder: (_, __) => const BookingsScreen()),
        GoRoute(path: '/offers',    builder: (_, __) => const OffersScreen()),
        GoRoute(path: '/account',   builder: (_, __) => const AccountScreen()),
      ],
    ),

    // Service detail
    GoRoute(
      path: '/services/:id',
      builder: (_, state) => ServiceDetailScreen(
        serviceId: state.pathParameters['id']!,
      ),
    ),

    // Booking flow (instant or schedule)
    GoRoute(
      path: '/booking-flow',
      builder: (_, state) {
        final extra     = state.extra as Map<String, dynamic>?;
        if (extra == null) return const ServicesScreen();
        final mode      = extra['mode']      as String? ?? 'schedule';
        final serviceId = extra['serviceId'] as String?;
        final cartItems = extra['cartItems'] as List<Map<String, dynamic>>?;
        return BookingFlowScreen(
            mode: mode, serviceId: serviceId, cartItems: cartItems);
      },
    ),

    // Booking detail
    GoRoute(
      path: '/bookings/:id',
      builder: (_, state) => BookingDetailScreen(
        bookingId: state.pathParameters['id']!,
      ),
    ),

    // ── Worker Shell ────────────────────────────────────────
    ShellRoute(
      builder: (_, __, child) => WorkerShell(child: child),
      routes: [
        GoRoute(
            path: '/worker/dashboard',
            builder: (_, __) => const WorkerDashboardScreen()),
        GoRoute(
            path: '/worker/earnings',
            builder: (_, __) => const WorkerEarningsScreen()),
        GoRoute(
            path: '/worker/history',
            builder: (_, __) => const WorkerHistoryScreen()),
        GoRoute(
            path: '/worker/profile',
            builder: (_, __) => const WorkerProfileScreen()),
      ],
    ),
    GoRoute(
      path: '/worker/jobs/:id',
      builder: (_, state) =>
          WorkerJobDetailScreen(id: state.pathParameters['id']!),
    ),

    // ── Admin Shell ─────────────────────────────────────────
    ShellRoute(
      builder: (_, __, child) => AdminShell(child: child),
      routes: [
        GoRoute(
            path: '/admin-overview',
            builder: (_, __) => const AdminOverviewScreen()),
        GoRoute(
            path: '/admin-bookings',
            builder: (_, __) => const AdminBookingsScreen()),
        GoRoute(
            path: '/admin-workers',
            builder: (_, __) => const AdminWorkersScreen()),
        GoRoute(
            path: '/admin-complaints',
            builder: (_, __) => const AdminComplaintsScreen()),
        GoRoute(
            path: '/admin-promos',
            builder: (_, __) => const AdminPromosScreen()),
        GoRoute(
            path: '/admin-reports',
            builder: (_, __) => const AdminReportsScreen()),
      ],
    ),
  ],
);