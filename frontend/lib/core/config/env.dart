/// The single seam for pointing this app at a real backend.
///
/// Defaults to the real backend now (the FastAPI instance at
/// github.com/saanvisarawat/FloodOps_DecodeSIH, run locally via
/// `uvicorn app.main:app --host 0.0.0.0 --port 8000`), so any launch
/// config — or a plain `flutter run` with no --dart-define flags at
/// all — connects to it. Pass `--dart-define=USE_MOCK_API=true` to opt
/// back into the mock for offline demoing.
///
/// No screen imports this file directly except `providers/api_provider.dart`,
/// which is the only place the mock/real choice is made.
class Env {
  Env._();

  static const bool useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: false,
  );

  /// Defaults to the deployed Render backend, reachable from anywhere
  /// (physical devices, emulators, web/desktop builds) with no LAN/IP
  /// config needed. Override with --dart-define=API_BASE_URL=... to
  /// point at a local dev server instead (e.g. http://10.0.2.2:8000 for
  /// the Android emulator talking to a machine on the same network).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://floodops-decodesih-3mrj.onrender.com',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'wss://floodops-decodesih-3mrj.onrender.com',
  );
}
