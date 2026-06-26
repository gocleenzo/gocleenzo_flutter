import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/customer/services_screen.dart';
import 'screens/customer/service_detail_screen.dart';
import 'screens/customer/booking_flow_screen.dart';
import 'screens/customer/bookings_screen.dart';
import 'screens/customer/booking_detail_screen.dart';
import 'screens/customer/account_screen.dart';
import 'screens/customer/offers_screen.dart';
import 'screens/customer/help_screen.dart';
import 'screens/customer/terms_screen.dart';
import 'screens/customer/location_gate_screen.dart';
import 'screens/customer/location_search_screen.dart';
import 'screens/customer/location_picker_screen.dart';
import 'screens/customer/address_confirm_screen.dart';
import 'screens/customer/saved_addresses_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final user = Supabase.instance.client.auth.currentUser;
    final loc  = state.matchedLocation;

    final isAuth = ['/', '/login'].contains(loc);
    final isLocationFlow = [
      '/location-gate',
      '/location-search',
      '/location-picker',
      '/address-confirm',
      '/saved-addresses',
    ].contains(loc);

    if (user == null && !isAuth && !isLocationFlow) return '/login';
    return null;
  },
  routes: [
    GoRoute(path: '/',      builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/help',  builder: (_, __) => const HelpScreen()),

    // ── Saved addresses ─────────────────────────────────────
    GoRoute(
      path: '/saved-addresses',
      builder: (_, __) => const SavedAddressesScreen(),
    ),

    // ── Location flow ────────────────────────────────────────
    GoRoute(
      path: '/location-gate',
      builder: (_, __) => const LocationGateScreen(),
    ),
    GoRoute(
      path: '/location-search',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return LocationSearchScreen(
          isOnboarding: extra['isOnboarding'] as bool? ?? false,
        );
      },
    ),
    GoRoute(
      path: '/location-picker',
      builder: (_, state) {
        final e = state.extra as Map<String, dynamic>? ?? {};
        return LocationPickerScreen(
          initialLat:         e['lat']          as double?,
          initialLng:         e['lng']          as double?,
          initialArea:        e['area']         as String?,
          initialCity:        e['city']         as String?,
          initialPincode:     e['pincode']      as String?,
          initialFullAddress: e['full_address'] as String?,
          isOnboarding:       e['isOnboarding'] as bool? ?? false,
        );
      },
    ),
    GoRoute(
      path: '/address-confirm',
      builder: (_, state) {
        final e = state.extra as Map<String, dynamic>;
        return AddressConfirmScreen(
          lat:          e['lat']          as double,
          lng:          e['lng']          as double,
          area:         e['area']         as String,
          city:         e['city']         as String,
          pincode:      e['pincode']      as String,
          fullAddress:  e['full_address'] as String,
          isOnboarding: e['isOnboarding'] as bool? ?? false,
        );
      },
    ),

    // ── Customer shell ───────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          CustomerShell(child: child),
      routes: [
        GoRoute(path: '/services', builder: (_, __) => const ServicesScreen()),
        GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen()),
        GoRoute(path: '/offers',   builder: (_, __) => const OffersScreen()),
        GoRoute(path: '/account',  builder: (_, __) => const AccountScreen()),
      ],
    ),

    // ── Service detail ───────────────────────────────────────
    GoRoute(
      path: '/services/:id',
      builder: (_, state) => ServiceDetailScreen(
          serviceId: state.pathParameters['id']!),
    ),

    // ── Booking flow ─────────────────────────────────────────
    GoRoute(
      path: '/booking-flow',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null) return const ServicesScreen();
        return BookingFlowScreen(
          mode:      extra['mode']      as String? ?? 'schedule',
          serviceId: extra['serviceId'] as String?,
          cartItems: extra['cartItems'] as List<Map<String, dynamic>>?,
        );
      },
    ),

    // ── Booking detail ───────────────────────────────────────
    GoRoute(
      path: '/bookings/:id',
      builder: (_, state) => BookingDetailScreen(
          bookingId: state.pathParameters['id']!),
    ),
  ],
);