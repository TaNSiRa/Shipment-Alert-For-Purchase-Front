# Purchase Shipment Alert — frontend

Flutter web client (RAP design system: `lib/shared/design.dart`, liquid glass).
The API is in the backend repo; see its README for database setup and Microsoft 365 sign-in.

## Run (development)
```powershell
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5340 --dart-define=API_BASE_URL=http://127.0.0.1:4340/api
```
`http://127.0.0.1:5340` must be in the backend's `FRONTEND_ORIGINS`.

## API address
- `--dart-define=API_BASE_URL=http://host:4340/api`: a fixed address.
- `--dart-define=API_BASE_URL=/api`: the server the page came from (build served by the API
  itself, or behind a reverse proxy).
- Not set: the same host as the page, port 4340.

## Production build (served by the API, with CSP)
```powershell
flutter build web --release --csp --no-web-resources-cdn --dart-define=API_BASE_URL=/api
```
Then set `WEB_ROOT=../frontend/build/web` in `backend/.env`. The API serves `build/web` with the
web app's Content-Security-Policy. Nothing is loaded from a CDN: fonts and CanvasKit are bundled.

## Sign in with Microsoft
The login page shows **Sign in with Microsoft** when `/api/health` reports `microsoftLogin: true`
(the backend has the `MS_*` settings). The API sends the browser back with `?ms_ticket=` (traded
for a session) or `?ms_error=` (shown on the login page). Both are removed from the address bar
straight away.
