# Cleenzo Flutter App

Converted from the Next.js + Supabase web app (`gocleenzo`).

## Setup

### 1. Install Flutter
https://docs.flutter.dev/get-started/install

### 2. Configure Supabase
Open `lib/main.dart` and replace:
```dart
const _supabaseUrl = 'YOUR_SUPABASE_URL';
const _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```
with the values from your `.env.local` file:
- `NEXT_PUBLIC_SUPABASE_URL` → `_supabaseUrl`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` → `_supabaseAnonKey`

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Run
```bash
flutter run
```

## Architecture

```
lib/
├── main.dart                 # App entry point, Supabase init
├── router.dart               # go_router navigation (all routes)
├── utils/
│   └── theme.dart            # AppColors, AppTheme
├── services/
│   └── supabase_service.dart # All DB/Auth calls
├── widgets/
│   └── auth_widgets.dart     # PhoneInput, OtpInputRow, CyanButton, BrandLogo
└── screens/
    ├── splash_screen.dart    # Animated splash → login or home
    ├── auth/
    │   ├── login_screen.dart  # Phone OTP login
    │   └── signup_screen.dart # Name + phone OTP signup
    ├── customer/
    │   ├── customer_shell.dart     # Bottom nav shell
    │   ├── services_screen.dart    # Service grid + cart ✅ FULLY IMPLEMENTED
    │   ├── bookings_screen.dart    # Upcoming/past bookings ✅ FULLY IMPLEMENTED
    │   ├── service_detail_screen.dart  # TODO
    │   ├── book_screen.dart            # TODO (from /book/[id] and /book/multi)
    │   ├── booking_detail_screen.dart  # TODO
    │   ├── account_screen.dart         # TODO
    │   ├── offers_screen.dart          # TODO
    │   ├── help_screen.dart            # TODO
    │   └── terms_screen.dart           # TODO
    ├── worker/
    │   ├── worker_shell.dart           # Bottom nav shell
    │   ├── worker_dashboard_screen.dart  ✅ FULLY IMPLEMENTED
    │   ├── worker_job_detail_screen.dart # TODO
    │   ├── worker_earnings_screen.dart   # TODO
    │   ├── worker_history_screen.dart    # TODO
    │   └── worker_profile_screen.dart    # TODO
    └── admin/
        ├── admin_shell.dart              # Bottom nav shell
        ├── admin_overview_screen.dart    # TODO
        ├── admin_bookings_screen.dart    # TODO
        ├── admin_workers_screen.dart     # TODO
        ├── admin_complaints_screen.dart  # TODO
        ├── admin_promos_screen.dart      # TODO
        └── admin_reports_screen.dart     # TODO
```

## Payments (Razorpay)
The `razorpay_flutter` package is included. 
Implement payment flow in `book_screen.dart` matching the 
`/app/api/payments/order/route.ts` and `/app/api/payments/verify/route.ts` logic.
Your Razorpay key is already in your `.env.local`.

## Realtime
Supabase realtime subscriptions are set up in `worker_dashboard_screen.dart`.
The same pattern works for booking status updates.

## Screens that need implementation (TODO)
Each TODO screen has the corresponding Next.js file listed below:
- `service_detail_screen.dart`  → `app/(customer)/services/[id]/page.tsx`
- `book_screen.dart`            → `app/(customer)/book/[id]/page.tsx` + `book/multi/page.tsx`
- `booking_detail_screen.dart`  → `app/(customer)/bookings/[id]/page.tsx`
- `account_screen.dart`         → `app/(customer)/account/page.tsx`
- `offers_screen.dart`          → `app/(customer)/offers/page.tsx`
- `help_screen.dart`            → `app/(customer)/help/page.tsx`
- `worker_job_detail_screen.dart` → `app/(worker)/jobs/[id]/page.tsx`
- `worker_earnings_screen.dart`   → `app/(worker)/earnings/page.tsx`
- `worker_history_screen.dart`    → `app/(worker)/history/page.tsx`
- `worker_profile_screen.dart`    → `app/(worker)/profile/page.tsx`
- `admin_overview_screen.dart`    → `app/(admin)/admin-overview/page.tsx`
- `admin_bookings_screen.dart`    → `app/(admin)/admin-bookings/page.tsx`
- `admin_workers_screen.dart`     → `app/(admin)/admin-workers/page.tsx`
- `admin_complaints_screen.dart`  → `app/(admin)/admin-complaints/page.tsx`
- `admin_promos_screen.dart`      → `app/(admin)/admin-promos/page.tsx`
- `admin_reports_screen.dart`     → `app/(admin)/admin-reports/page.tsx`
