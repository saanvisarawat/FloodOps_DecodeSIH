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

  /// 192.168.1.3 is this dev machine's LAN IP — reachable from a physical
  /// device on the same Wi-Fi, and from the host machine itself (Chrome/
  /// Windows desktop builds). Targeting the Android emulator instead
  /// needs 10.0.2.2 (it can't see the host's LAN IP or localhost) —
  /// override with --dart-define=API_BASE_URL=http://10.0.2.2:8000 in
  /// that case.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.3:8000',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://192.168.1.3:8000',
  );
}
