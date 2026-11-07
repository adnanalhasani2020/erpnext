# ERPNext Mobile (Flutter)

Arabic-first Android companion app for the ERPNext instance in this repository.

## Current scope

- Arabic right-to-left login screen and configurable ERPNext server URL.
- Login through Frappe's `/api/method/login` endpoint.
- Session-cookie handling in memory only; credentials and cookies are not written to disk.
- Logged-in user verification through `/api/method/frappe.auth.get_logged_user`.
- Logout through `/api/method/logout`.
- Dashboard with separate Arabic tabs for items, stock balances, and warehouses.\n- Item and warehouse local search over records loaded from the server.\n- Read-only stock balances by warehouse from ERPNext `Bin`, including actual, reserved, projected, and calculated available quantities.

Sales, purchasing, and accounting are still placeholders. The current stock views are read-only; they do not create stock movements or modify quantities. Item and warehouse search currently filters records loaded into the app (up to 100 items and warehouses per request), not the full server catalogue.

## Requirements

- Flutter stable (Dart 3.4 or newer).
- A reachable ERPNext/Frappe site with HTTPS.
- A valid ERPNext user account.

## Run locally

```bash
cd mobile_app
flutter create --platforms=android --org com.adnanalhasani.erpnext --project-name erpnext_mobile .
flutter pub get
flutter run
```

Enter the HTTPS base URL of the ERPNext site, for example `https://erp.example.com`. Do not enter an API key or database password in the app.

For local Android emulator development only, `http://10.0.2.2` is accepted. Production connections must use HTTPS.

## Build

```bash
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## Security notes

- Never embed Supabase service-role keys, database passwords, or Frappe administrator credentials in the APK.
- The app talks to Frappe's API. It must not connect directly to PostgreSQL/Supabase.
- The current session cookie is held in memory and is cleared when the app process exits.
- A production release still needs security review, API permission testing, and a properly configured signing key.
