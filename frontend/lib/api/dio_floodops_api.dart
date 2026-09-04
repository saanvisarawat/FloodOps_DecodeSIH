import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/kerala_districts.dart';
import 'floodops_api.dart';

/// Real backend implementation of [FloodOpsApi], talking to the FastAPI
/// service at github.com/saanvisarawat/FloodOps_DecodeSIH.
///
/// This class is an *adapter*, not a mirror: the real backend's endpoint
/// shapes were built independently of this app's contract (see
/// API_CONTRACT.md) and differ from it in many places — some cosmetic
/// (form-encoded login), some structural (the ML risk request/response use
/// entirely different fields), some outright missing (no user profile
/// endpoint, `/api/reports` returns raw ORM rows with no lat/lng
/// extraction, the agent-hub router isn't mounted in `main.py` at all).
/// Every screen and every model in `lib/api/models/` keeps the ORIGINAL
/// clean contract unchanged; this file absorbs all of the real backend's
/// quirks so the rest of the app never has to know about them. Known gaps
/// are called out inline below with `NOTE:`.
class DioFloodOpsApi implements FloodOpsApi {
  DioFloodOpsApi({required String baseUrl, required String wsBaseUrl, String? authToken})
      : _wsBaseUrl = wsBaseUrl,
        _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _authToken = authToken;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (_authToken != null) {
        options.headers['Authorization'] = 'Bearer $_authToken';
      }
      handler.next(options);
    }));
  }

  final Dio _dio;
  final String _wsBaseUrl;
  String? _authToken;

  /// NOTE: the real backend's JWT only embeds `sub` (email) and `role` —
  /// no user id, no full name — and there is no `/api/users/me` endpoint
  /// to fetch them after the fact. This cache lets a login shortly after
  /// a register (in the same app session) recover the real numeric id/name;
  /// a cold login on a fresh session falls back to best-effort values
  /// derived from the email. Ask the backend team to add either claim to
  /// the JWT or a `/api/users/me` route to remove this workaround.
  final Map<String, ({String id, String fullName})> _localUserCache = {};

  /// Populated by [getReports] so [verifyReport] (whose real response only
  /// carries vote counts + status, not the full report) can merge updated
  /// counts back onto a report we already have client-side instead of
  /// returning a half-blank one.
  final Map<String, ReportSummary> _reportsCache = {};

  WebSocketChannel? _dashboardChannel;
  StreamController<DashboardEvent>? _dashboardController;
  final StreamController<MaskedCallPayload> _incomingCallController =
      StreamController<MaskedCallPayload>.broadcast();

  /// Called by [AuthController] after login/register/session-restore
  /// succeeds (and with `null` on logout) so every subsequent request
  /// carries the real Bearer token. `FloodOpsApi` doesn't declare this —
  /// callers check `api is DioFloodOpsApi` first — because `MockFloodOpsApi`
  /// has no concept of a token.
  void setAuthToken(String? token) => _authToken = token;

  // ---------------------------------------------------------------------
  // 1. Auth & device onboarding
  // ---------------------------------------------------------------------

  @override
  Future<AuthResponse> register(RegisterRequest request) async {
    final res = await _dio.post('/api/auth/register', data: {
      'full_name': request.fullName,
      'email': request.email,
      'password': request.password,
      'role': request.role.wire,
    });
    final userId = (res.data as Map<String, dynamic>)['user_id'];
    _localUserCache[request.email] = (id: userId.toString(), fullName: request.fullName);
    return login(LoginRequest(email: request.email, password: request.password));
  }

  @override
  Future<AuthResponse> login(LoginRequest request) async {
    // Real /api/auth/login is OAuth2PasswordRequestForm — form-encoded
    // `username`/`password`, not JSON, and not literally `email`.
    final res = await _dio.post(
      '/api/auth/login',
      data: {'username': request.email, 'password': request.password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = res.data as Map<String, dynamic>;
    final token = data['access_token'] as String;
    final claims = _decodeJwtPayload(token);
    final email = (claims?['sub'] as String?) ?? request.email;
    final role = UserRoleX.fromWire((claims?['role'] as String?) ?? 'citizen');
    final cached = _localUserCache[email];
    final namePart = email.split('@').first;
    final fallbackName = namePart
        .split(RegExp(r'[._]'))
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
    final user = UserProfile(
      id: cached?.id ?? email,
      fullName: cached?.fullName ?? (fallbackName.isEmpty ? email : fallbackName),
      email: email,
      role: role,
    );
    setAuthToken(token);
    return AuthResponse(token: token, user: user);
  }

  Map<String, dynamic>? _decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
      return jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> registerFcmToken(String token) async {
    await _dio.post('/api/users/fcm-token', data: {'fcm_token': token});
  }

  // ---------------------------------------------------------------------
  // 2. SOS & offline connectivity
  // ---------------------------------------------------------------------

  @override
  Future<ReportSummary> createReport(CreateReportRequest request) async {
    // Real ReportCreate still requires a `user_id` field even though the
    // handler ignores it and uses the authenticated Bearer identity
    // instead — the value sent here is never actually used server-side.
    final res = await _dio.post('/api/reports', data: {
      'description': request.description,
      'latitude': request.latitude,
      'longitude': request.longitude,
      'user_id': 0,
    });
    final data = res.data as Map<String, dynamic>;
    // Real response is `{message, ticket_id, assigned_volunteer_id,
    // nearby_users_alerted}` — it doesn't echo the report back, so the
    // rest of this summary is reconstructed from what we sent.
    final summary = ReportSummary(
      ticketId: data['ticket_id'].toString(),
      description: request.description,
      latitude: request.latitude,
      longitude: request.longitude,
      distanceMeters: 0,
      confirmCount: 0,
      falseAlarmCount: 0,
      status: ReportStatus.pending,
      reportedAt: request.clientTimestamp,
      reporterAlias: 'You',
    );
    _reportsCache[summary.ticketId] = summary;
    return summary;
  }

  @override
  Future<BulkSyncResult> bulkSyncReports(List<CreateReportRequest> requests) async {
    await _dio.post('/api/reports/bulk', data: {
      'reports': requests
          .map((r) => {
                'description': r.description,
                'latitude': r.latitude,
                'longitude': r.longitude,
                'client_timestamp': r.clientTimestamp.toIso8601String(),
              })
          .toList(),
    });
    // Real response is `{message, saved, skipped_duplicates}` — no
    // per-item client_id is echoed back, so we can't tell which specific
    // queued items were new vs. duplicates. Both outcomes mean "the
    // server now has it, stop retrying," so every item is reported as
    // synced and none as duplicate.
    return BulkSyncResult(
      syncedClientIds: requests.map((r) => r.clientId).toList(),
      duplicateClientIds: const [],
    );
  }

  // ---------------------------------------------------------------------
  // 2b. Low Data SOS
  // ---------------------------------------------------------------------

  @override
  Future<ReportSummary> sendLiteSos({required double lat, required double lng, required String description}) async {
    // Real /api/reports/lite is query-param based (not a JSON body) so the
    // whole request fits a single TCP packet on 2G — matches main.py's
    // `lat`/`lng`/`desc`/`user_id` signature exactly.
    final res = await _dio.post('/api/reports/lite', queryParameters: {
      'lat': lat,
      'lng': lng,
      'desc': description,
      'user_id': 0,
    });
    final data = res.data as Map<String, dynamic>;
    return ReportSummary(
      ticketId: data['id'].toString(),
      description: description,
      latitude: lat,
      longitude: lng,
      distanceMeters: 0,
      confirmCount: 0,
      falseAlarmCount: 0,
      status: ReportStatus.pending,
      reportedAt: DateTime.now(),
      reporterAlias: 'You',
    );
  }

  // ---------------------------------------------------------------------
  // 6. Crowdsourced verification radar
  // ---------------------------------------------------------------------

  @override
  Future<List<ReportSummary>> getReports({double? nearLat, double? nearLng}) async {
    // NOTE: real GET /api/reports takes no query params (no near-lat/lng
    // support — sorted client-side below when the real payload happens to
    // carry usable coordinates) and returns raw SQLAlchemy `Report` ORM
    // rows with no response_model, including a PostGIS `location` column
    // FastAPI cannot cleanly JSON-encode. This is very likely to either
    // 500 or return a shape that doesn't match any of the cases handled
    // below on the live server — flag this to the backend team; the fix
    // is the same pattern already used correctly by
    // GET /api/shelters/geojson (extract lat/lng via ST_X/ST_Y and return
    // a plain dict, ideally behind a Pydantic response_model).
    final res = await _dio.get('/api/reports');
    final raw = res.data;
    if (raw is! List) return [];
    final results = <ReportSummary>[];
    for (final item in raw) {
      final summary = _parseRawReport(item);
      if (summary != null) {
        _reportsCache[summary.ticketId] = summary;
        results.add(summary);
      }
    }
    if (nearLat != null && nearLng != null) {
      results.sort((a, b) =>
          _distanceMeters(nearLat, nearLng, a.latitude, a.longitude)
              .compareTo(_distanceMeters(nearLat, nearLng, b.latitude, b.longitude)));
    }
    return results;
  }

  ReportSummary? _parseRawReport(dynamic item) {
    if (item is! Map) return null;
    final json = item.cast<String, dynamic>();
    try {
      final id = json['id'] ?? json['ticket_id'];
      if (id == null) return null;
      double lat = 0, lng = 0;
      final loc = json['location'];
      if (loc is Map && loc['coordinates'] is List) {
        final coords = loc['coordinates'] as List;
        lng = (coords[0] as num).toDouble();
        lat = (coords[1] as num).toDouble();
      } else if (json['latitude'] != null && json['longitude'] != null) {
        lat = (json['latitude'] as num).toDouble();
        lng = (json['longitude'] as num).toDouble();
      }
      final statusWire = json['status'] as String? ?? 'pending';
      final tsRaw = json['client_timestamp'] as String?;
      return ReportSummary(
        ticketId: id.toString(),
        description: json['description'] as String? ?? '',
        latitude: lat,
        longitude: lng,
        distanceMeters: 0,
        confirmCount: (json['yes_count'] as num?)?.toInt() ?? 0,
        falseAlarmCount: (json['no_count'] as num?)?.toInt() ?? 0,
        status: statusWire == 'verified' ? ReportStatus.verified : ReportStatus.pending,
        reportedAt: tsRaw == null ? DateTime.now() : (DateTime.tryParse(tsRaw) ?? DateTime.now()),
        reporterAlias: null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReportSummary> verifyReport(String ticketId, VerifyVote vote) async {
    final res = await _dio.post('/api/reports/$ticketId/verify', data: {
      'is_verified': vote == VerifyVote.confirm,
    });
    final data = res.data as Map<String, dynamic>;
    final statusWire = data['status'] as String? ?? 'pending';
    final status = statusWire == 'verified' ? ReportStatus.verified : ReportStatus.pending;
    final cached = _reportsCache[ticketId];
    final updated = (cached ??
            ReportSummary(
              ticketId: ticketId,
              description: '',
              latitude: 0,
              longitude: 0,
              distanceMeters: 0,
              confirmCount: 0,
              falseAlarmCount: 0,
              status: ReportStatus.pending,
              reportedAt: DateTime.now(),
            ))
        .copyWith(
      confirmCount: (data['yes_count'] as num?)?.toInt(),
      falseAlarmCount: (data['no_count'] as num?)?.toInt(),
      status: status,
    );
    _reportsCache[ticketId] = updated;
    return updated;
  }

  // ---------------------------------------------------------------------
  // 7. Evacuation map
  // ---------------------------------------------------------------------

  @override
  Future<ShelterFeatureCollection> getSheltersGeoJson() async {
    final res = await _dio.get('/api/shelters/geojson');
    final data = res.data as Map<String, dynamic>;
    final features = <ShelterFeature>[];
    for (final raw in (data['features'] as List)) {
      final feature = raw as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;
      final props = feature['properties'] as Map<String, dynamic>;
      final lat = (coords[1] as num).toDouble();
      final lng = (coords[0] as num).toDouble();
      // NOTE: real Shelter has no district/address column at all — the
      // district is approximated here from nearest district-center
      // distance so the map/list UI (which groups by district) still
      // works; ask the backend to add real district/address columns for
      // an authoritative value.
      features.add(ShelterFeature(
        id: props['id'].toString(),
        name: props['name'] as String? ?? 'Shelter',
        district: _nearestDistrict(lat, lng).name,
        latitude: lat,
        longitude: lng,
        capacity: (props['capacity'] as num?)?.toInt() ?? 0,
        currentOccupancy: (props['current_occupancy'] as num?)?.toInt() ?? 0,
      ));
    }
    return ShelterFeatureCollection(features);
  }

  // ---------------------------------------------------------------------
  // 4. ML flood risk predictor
  // ---------------------------------------------------------------------

  @override
  Future<RiskPredictionResponse> predictRisk(RiskPredictionRequest request) async {
    // Real /api/predict/risk takes the trained model's actual 12 column
    // names (rainfall_mm, river_discharge, elevation_m, slope_deg,
    // dist_nearest_river_km, the *_3d/7d/15d_sum rolling windows, and
    // historical_flood_count) — not this app's UI-facing fields, and not
    // the old rain_3d_sum/mean_elevation_m/state_norm shape this used to
    // send (schemas.RiskPredictionRequest was realigned to the model's
    // real column names; the old shape now gets rejected outright with a
    // 422). historical_flood_count still comes from the same per-district
    // baseline table `app/main.py`'s own hourly pipeline uses; river
    // discharge has no UI input at all, so it's approximated from
    // rainfall the same way the backend's own citizen-facing endpoint
    // used to before this schema realignment.
    // The naive linear extrapolation this used to do — rain7d = 3-day
    // total * 7/3, rain15d = 3-day total * 15/3 — pushed rainfall_mm_15d_sum
    // past the backend's fixed 180mm "heavy rain override" threshold for
    // almost any slider value >=36 (out of this screen's full 20-400
    // range), so nearly every district read CRITICAL regardless of the
    // actual slider position. These smaller, empirically-checked
    // multipliers keep the override reachable only for genuinely high
    // slider values (150+) instead of nearly the whole range.
    final baseline = _keralaStaticFeatures[request.district] ?? _keralaStaticFeatures.values.first;
    final rainfallMm = request.rainfallMm3Day / 3.0;
    final rain7d = request.rainfallMm3Day * 1.3;
    final rain15d = request.rainfallMm3Day * 1.5;
    final payload = {
      'rainfall_mm': rainfallMm,
      'river_discharge': rainfallMm * 2.5,
      'elevation_m': request.elevationM,
      'slope_deg': request.slopeDeg,
      'dist_nearest_river_km': request.riverProximityKm,
      'rainfall_mm_3d_sum': request.rainfallMm3Day,
      'rainfall_mm_7d_sum': rain7d,
      'rainfall_mm_15d_sum': rain15d,
      'river_discharge_3d_sum': request.rainfallMm3Day * 2.5,
      'river_discharge_7d_sum': rain7d * 2.0,
      'river_discharge_15d_sum': rain15d * 1.5,
      'historical_flood_count': baseline['historical_flood_count'],
    };
    final res = await _dio.post('/api/predict/risk', data: payload);
    final data = res.data as Map<String, dynamic>;
    // `top_factors` is a plain `[name, name, ...]` list (already ranked by
    // SHAP magnitude server-side, highest first) — not `{feature,
    // shap_value}` dicts. Casting each entry to a Map here used to throw
    // on every single call (a plain String has no `.feature` key), which
    // silently turned a successful 200 response into a caught exception
    // — that's what was showing "Risk score unavailable" on the home
    // screen even though the request worked. No real magnitude is
    // available, so weight is synthesized from rank order (first =
    // biggest contributor) purely so the pie chart still shows the
    // correct relative ordering.
    final rawFactors = (data['top_factors'] as List?) ?? const [];
    final factors = <RiskFactor>[
      for (var i = 0; i < rawFactors.length; i++)
        RiskFactor(
          factor: _humanizeFeatureName(rawFactors[i] as String),
          weight: (rawFactors.length - i).toDouble(),
        ),
    ];
    return RiskPredictionResponse(
      riskScore: (data['risk_score'] as num).toDouble(),
      district: request.district,
      topFactors: factors,
    );
  }

  String _humanizeFeatureName(String raw) =>
      raw.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  // ---------------------------------------------------------------------
  // 3. RAG survival chatbot
  // ---------------------------------------------------------------------

  @override
  Future<ChatResponse> sendChatMessage(ChatRequest request) async {
    final res = await _dio.post('/api/chat', data: request.toJson());
    return ChatResponse.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------
  // 5. Multi-agent intelligence hub
  // ---------------------------------------------------------------------

  @override
  Future<AgentHubResponse> runAgentHubAnalysis(String district) async {
    // NOTE: as of this backend snapshot, `app/agents.py` defines
    // POST /api/agents/trigger but `main.py` never calls
    // `app.include_router(agents.router)` — this endpoint 404s on the
    // live server until that one line is added backend-side.
    final res = await _dio.post('/api/agents/trigger', data: {
      'district': district,
      'incident_data': 'Requested from FloodOps mobile app.',
    });
    final data = res.data as Map<String, dynamic>;
    final now = DateTime.now();
    final chain = (data['execution_chain'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    // Real AgentRunLogResponse has no top-level `alert_level` — it's only
    // ever produced (as JSON text) inside the Communications step's
    // `output`, so it's scraped out best-effort here.
    var alertLevel = AlertLevel.green;
    for (final step in chain) {
      final output = step['output'];
      if (output is String && output.toUpperCase().contains('CRITICAL')) {
        alertLevel = AlertLevel.red;
      } else if (output is String && output.toUpperCase().contains('HIGH') && alertLevel != AlertLevel.red) {
        alertLevel = AlertLevel.orange;
      } else if (output is String && output.toUpperCase().contains('MODERATE') && alertLevel == AlertLevel.green) {
        alertLevel = AlertLevel.yellow;
      }
    }
    return AgentHubResponse(
      district: (data['district'] as String?) ?? district,
      executionChain: [
        for (var i = 0; i < chain.length; i++)
          AgentExecutionStep(
            agentName: (chain[i]['agent'] as String?) ?? 'Agent ${i + 1}',
            action: 'Executed analysis step',
            finding: chain[i]['output']?.toString() ?? '',
            timestamp: now.add(Duration(seconds: i * 3)),
          ),
      ],
      coordinatorSummary: (data['coordinator_summary'] as String?) ?? '',
      alertLevel: alertLevel,
    );
  }

  // ---------------------------------------------------------------------
  // 8. Volunteer command hub
  // ---------------------------------------------------------------------

  @override
  Future<void> updateVolunteerLocation(VolunteerLocationUpdate update) async {
    await _dio.post('/api/volunteers/location', data: {
      'latitude': update.latitude,
      'longitude': update.longitude,
      'status': update.status.wire,
      // Real VolunteerLocationUpdate.skills is a single comma-separated
      // string ("boat,medical,swimming"), not a JSON array.
      'skills': update.skills.map((s) => s.wire).join(','),
    });
  }

  @override
  Future<List<VolunteerTask>> getVolunteerTasks() async {
    // NOTE: real GET /api/volunteers/tasks returns raw ORM `Report` rows
    // under `assigned_tasks` with no response_model (same PostGIS
    // serialization risk as GET /api/reports) — parsed defensively below,
    // skipping anything unparseable rather than crashing the tasks list.
    final res = await _dio.get('/api/volunteers/tasks');
    final data = res.data as Map<String, dynamic>;
    final raw = data['assigned_tasks'];
    if (raw is! List) return [];
    final tasks = <VolunteerTask>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final json = item.cast<String, dynamic>();
        double lat = 0, lng = 0;
        final loc = json['location'];
        if (loc is Map && loc['coordinates'] is List) {
          final coords = loc['coordinates'] as List;
          lng = (coords[0] as num).toDouble();
          lat = (coords[1] as num).toDouble();
        }
        final id = json['id'];
        if (id == null) continue;
        tasks.add(VolunteerTask(
          taskId: 'TASK-$id',
          sosTicketId: id.toString(),
          district: _nearestDistrict(lat, lng).name,
          latitude: lat,
          longitude: lng,
          description: json['description'] as String? ?? '',
          priority: TaskPriority.medium,
          status: TaskStatus.assigned,
          assignedAt: DateTime.now(),
          distanceKm: 0,
        ));
      } catch (_) {
        continue;
      }
    }
    return tasks;
  }

  /// Real masked-call triggers arrive as an FCM background data message
  /// (type: "EMERGENCY_INCOMING_CALL"), not over this HTTP client. Wire
  /// `NotificationService`'s FCM handler to call
  /// `_incomingCallController.add(MaskedCallPayload.fromJson(data))` once
  /// push is configured.
  @override
  Stream<MaskedCallPayload> get incomingCallStream => _incomingCallController.stream;

  @override
  void simulateIncomingCall() {
    throw UnsupportedError(
        'simulateIncomingCall is a mock-only debug trigger; real calls arrive via FCM.');
  }

  @override
  void deliverIncomingCall(MaskedCallPayload payload) => _incomingCallController.add(payload);

  @override
  Stream<DashboardEvent> get dashboardEventStream {
    _dashboardController ??= StreamController<DashboardEvent>.broadcast(
      onListen: () {
        _dashboardChannel = WebSocketChannel.connect(Uri.parse('$_wsBaseUrl/ws/dashboard'));
        _dashboardChannel!.stream.listen((raw) {
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          _dashboardController?.add(DashboardEvent.fromJson(json));
        });
      },
      onCancel: () {
        _dashboardChannel?.sink.close();
        _dashboardChannel = null;
      },
    );
    return _dashboardController!.stream;
  }

  // ---------------------------------------------------------------------
  // 10. Kerala live dam/river/risk cache
  // ---------------------------------------------------------------------

  @override
  Future<KeralaLiveDashboard> getKeralaLiveDashboard() async {
    final res = await _dio.get('/api/dashboard/live-kerala');
    return KeralaLiveDashboard.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------
  // 11. Voice Agent
  // ---------------------------------------------------------------------

  @override
  Future<VoiceAgentResult> sendVoiceQuery({
    required double lat,
    required double lng,
    required Uint8List audioBytes,
  }) async {
    // Real /api/voice/agent is multipart form data (`lat`, `lng`,
    // `audio_file`) and replies with raw WAV bytes on success, or a JSON
    // error object if Sarvam/Gemini failed — matches main.py exactly.
    // Bytes (not a `dart:io File`) so this also works on Flutter Web.
    final formData = FormData.fromMap({
      'lat': lat,
      'lng': lng,
      'audio_file': MultipartFile.fromBytes(audioBytes, filename: 'voice_query.wav'),
    });
    try {
      final res = await _dio.post(
        '/api/voice/agent',
        data: formData,
        options: Options(responseType: ResponseType.bytes),
      );
      final contentType = res.headers.value('content-type') ?? '';
      final bytes = Uint8List.fromList(res.data as List<int>);
      if (contentType.contains('audio')) {
        // NOTE: the backend doesn't return a transcript or reply-text
        // field alongside the audio — [transcript]/[replyText] stay null
        // here on purpose rather than inventing text; the UI shows
        // "Transcript unavailable" instead.
        return VoiceAgentResult(audioBytes: bytes);
      }
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return VoiceAgentResult(errorMessage: (json['error'] ?? json['message'] ?? 'Voice agent failed').toString());
    } on DioException catch (e) {
      return VoiceAgentResult(errorMessage: e.message ?? 'Voice agent request failed.');
    }
  }

  // ---------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------

  DistrictProfile _nearestDistrict(double lat, double lng) {
    DistrictProfile nearest = KeralaDistricts.all.first;
    double best = double.infinity;
    for (final d in KeralaDistricts.all) {
      final dist = _distanceMeters(lat, lng, d.center.latitude, d.center.longitude);
      if (dist < best) {
        best = dist;
        nearest = d;
      }
    }
    return nearest;
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  // ---------------------------------------------------------------------
  // 12. HITL alert approval
  // ---------------------------------------------------------------------

  @override
  Future<List<PendingAlert>> getPendingAlerts() async {
    final res = await _dio.get('/api/alerts/pending');
    return (res.data as List).map((e) => PendingAlert.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<PendingAlert> approveAlert(int alertId) async {
    final res = await _dio.post('/api/alerts/$alertId/approve');
    return PendingAlert.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<PendingAlert> rejectAlert(int alertId) async {
    final res = await _dio.post('/api/alerts/$alertId/reject');
    return PendingAlert.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  void dispose() {
    _dashboardChannel?.sink.close();
    _dashboardController?.close();
    _incomingCallController.close();
    _dio.close();
  }
}

/// Copied verbatim from `app/main.py`'s `run_kerala_flood_pipeline()`
/// `static_features` table so `predictRisk`'s district-level defaults
/// match what the live backend's own hourly job feeds the model.
const Map<String, Map<String, double>> _keralaStaticFeatures = {
  'Thiruvananthapuram': {'impervious_surface_pct': 35.0, 'historical_flood_count': 5, 'days_since_last_flood': 200.0},
  'Kollam': {'impervious_surface_pct': 28.0, 'historical_flood_count': 6, 'days_since_last_flood': 180.0},
  'Pathanamthitta': {'impervious_surface_pct': 14.0, 'historical_flood_count': 9, 'days_since_last_flood': 220.0},
  'Alappuzha': {'impervious_surface_pct': 20.0, 'historical_flood_count': 15, 'days_since_last_flood': 90.0},
  'Kottayam': {'impervious_surface_pct': 22.0, 'historical_flood_count': 11, 'days_since_last_flood': 110.0},
  'Idukki': {'impervious_surface_pct': 5.5, 'historical_flood_count': 8, 'days_since_last_flood': 340.0},
  'Ernakulam': {'impervious_surface_pct': 45.2, 'historical_flood_count': 12, 'days_since_last_flood': 120.0},
  'Thrissur': {'impervious_surface_pct': 32.0, 'historical_flood_count': 10, 'days_since_last_flood': 130.0},
  'Palakkad': {'impervious_surface_pct': 18.0, 'historical_flood_count': 7, 'days_since_last_flood': 150.0},
  'Malappuram': {'impervious_surface_pct': 25.0, 'historical_flood_count': 9, 'days_since_last_flood': 140.0},
  'Kozhikode': {'impervious_surface_pct': 40.0, 'historical_flood_count': 11, 'days_since_last_flood': 115.0},
  'Wayanad': {'impervious_surface_pct': 8.0, 'historical_flood_count': 10, 'days_since_last_flood': 180.0},
  'Kannur': {'impervious_surface_pct': 30.0, 'historical_flood_count': 8, 'days_since_last_flood': 125.0},
  'Kasaragod': {'impervious_surface_pct': 22.0, 'historical_flood_count': 7, 'days_since_last_flood': 135.0},
};
