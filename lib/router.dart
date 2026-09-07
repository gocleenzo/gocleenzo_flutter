import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/customer/services_screen.dart';
import 'screens/customer/service_detail_screen.dart';
import 'screens/customer/booking_flow_screen.dart';
import 'screens/customer/bookings_screen.dart';
import 'screens/customer/booking_detail_screen.dart' hide ServiceDetailScreen;
import 'screens/customer/account_screen.dart';
import 'screens/customer/offers_screen.dart';
import 'screens/customer/help_screen.dart';
import 'screens/customer/terms_screen.dart';
import 'screens/customer/location_gate_screen.dart';
import 'screens/customer/location_search_screen.dart';
import 'screens/customer/location_picker_screen.dart';
import 'screens/customer/address_confirm_screen.dart';
import 'screens/customer/saved_addresses_screen.dart';
import 'screens/customer/notifications_screen.dart';

// ── Zoom-in page transition ─────────────────────────────────────
// Used only for the screens the splash screen can land on, so the
// destination page appears to scale in from the center — continuing
// the splash's own zoom-out motion into a single unbroken flow.
// 500ms here + the splash's 2500ms = 3000ms total, matching the
// splash screen's own animation budget.
CustomTransitionPage<void> _zoomPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final scale = Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
      );
    },
  );
}

/// Exposed so main.dart can resolve GoRouter's current location and
/// trigger navigation from the native back-button MethodChannel handler,
/// bypassing Flutter's normal (broken-on-this-device) back dispatch.
final rootNavigatorKey = GlobalKey<NavigatorState>();

// ── FIX: random/frequent logout on Android force-close ──────────
//
// ROOT CAUSE: the router's redirect() function used to read
// fb.FirebaseAuth.instance.currentUser SYNCHRONOUSLY, at whatever
// instant navigation happened to occur — with no `refreshListenable`
// tying the router to Firebase's actual auth-state stream at all.
//
// On Android specifically, when the OS fully kills the app's process
// (a genuine force-close, not just backgrounding), Firebase has to
// asynchronously restore the previously-signed-in session from disk
// the next time the app launches. `currentUser` reads `null` for a
// brief window during that restore — even though the real, valid
// session is about to become available a moment later. If the splash
// screen tried to navigate onward during that exact window, the old
// redirect logic saw `currentUser == null`, concluded "not logged in",
// and sent a perfectly legitimate, still-signed-in customer straight
// to /login — discarding their session for no real reason. This
// reproduces exactly on the "force-close, wait, reopen" pattern
// reported, since a genuine process kill is what triggers Firebase's
// disk-restore path at all (simple backgrounding never does).
//
// THE FIX, two parts:
//   1. `_AuthChangeNotifier` below listens to Firebase's own
//      `authStateChanges()` stream (not just reading `currentUser`
//      once) and tells GoRouter to re-run its redirect logic every
//      time that stream emits — including the FIRST emission after a
//      cold start, which is exactly the restored-session event this
//      bug was missing entirely.
//   2. The redirect function itself now checks `_authInitialized` and
//      returns `null` (i.e. "don't redirect anywhere yet, leave
//      whatever's currently showing alone") until that first stream
//      event has actually arrived — so the splash screen is never
//      forced into a premature "not logged in" verdict based on a
//      `currentUser` read that just hasn't caught up yet.
bool _authInitialized = false;

class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier() {
    fb.FirebaseAuth.instance.authStateChanges().listen((user) {
      _authInitialized = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ROUTER] Firebase authStateChanges emitted: '
            'uid=${user?.uid} (authInitialized=$_authInitialized)');
      }
      notifyListeners();
    });
  }
}

final _authNotifier = _AuthChangeNotifier();

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final loc = state.matchedLocation;

    final isAuth = ['/', '/login'].contains(loc);
    final isLocationFlow = [
      '/location-gate',
      '/location-search',
      '/location-picker',
      '/address-confirm',
      '/saved-addresses',
      '/notifications',
    ].contains(loc);

    // Still waiting on Firebase's first authStateChanges() emission
    // (i.e. the async session-restore-from-disk step hasn't finished
    // yet, most likely right after a cold start following a force-
    // close). Don't make ANY redirect decision yet — whatever screen
    // is currently showing (normally the splash screen) stays exactly
    // where it is until we actually know the real auth state. This is
    // the fix: previously, skipping this wait is what let a valid but
    // not-yet-restored session get misread as "logged out".
    if (!_authInitialized) {
      // ignore: avoid_print
      print('[ROUTER] loc=$loc — auth not yet initialized, holding redirect');
      return null;
    }

    final supaUser  = Supabase.instance.client.auth.currentUser;
    final fireUser  = fb.FirebaseAuth.instance.currentUser;
    final isLoggedIn = supaUser != null || fireUser != null;

    // ignore: avoid_print
    print('[ROUTER] loc=$loc supaUser=${supaUser?.id} fireUser=${fireUser?.uid} isLoggedIn=$isLoggedIn isAuth=$isAuth isLocationFlow=$isLocationFlow');

    if (!isLoggedIn && !isAuth && !isLocationFlow) {
      // ignore: avoid_print
      print('[ROUTER] REDIRECTING TO /login');
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => _zoomPage(const LoginScreen(), state),
    ),
    GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/help',  builder: (_, __) => const HelpScreen()),

    // ── Saved addresses ──────────────────────────────────────
    GoRoute(
      path: '/saved-addresses',
      builder: (_, __) => const SavedAddressesScreen(),
    ),

    // ── Notifications ────────────────────────────────────────
    GoRoute(
      path: '/notifications',
      builder: (_, __) => const NotificationsScreen(),
    ),

    // ── Location flow ─────────────────────────────────────────
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
          placeId:            e['placeId']      as String?,
          searchLabel:        e['searchLabel']  as String?,
          originalLat:        e['originalLat']  as double?,
          originalLng:        e['originalLng']  as double?,
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

    // ── Customer shell (bottom-nav tabs) ─────────────────────
    // StatefulShellRoute keeps a separate navigation stack per branch
    // and plays correctly with PopScope in CustomerShell, unlike a
    // plain ShellRoute (which replaces routes and breaks back-button
    // handling — see CustomerShell for the back-press logic).
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          CustomerShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/services',
            pageBuilder: (context, state) =>
                _zoomPage(const ServicesScreen(), state),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/offers', builder: (_, __) => const OffersScreen()),
        ]),
      ],
    ),

    // ── Account (reached outside the bottom-nav tabs) ────────
    GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),

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