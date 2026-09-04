import 'dart:typed_data';

import 'models/auth_models.dart';
import 'models/report_models.dart';
import 'models/shelter_models.dart';
import 'models/risk_models.dart';
import 'models/chat_models.dart';
import 'models/agent_hub_models.dart';
import 'models/volunteer_models.dart';
import 'models/dashboard_event_models.dart';
import 'models/kerala_live_models.dart';
import 'models/voice_models.dart';
import 'models/alert_models.dart';

export 'models/auth_models.dart';
export 'models/report_models.dart';
export 'models/shelter_models.dart';
export 'models/risk_models.dart';
export 'models/chat_models.dart';
export 'models/agent_hub_models.dart';
export 'models/volunteer_models.dart';
export 'models/dashboard_event_models.dart';
export 'models/kerala_live_models.dart';
export 'models/voice_models.dart';
export 'models/alert_models.dart';

/// The single contract every screen in this app talks to. Every mocked
/// endpoint here mirrors a real FastAPI route documented in
/// API_CONTRACT.md — swapping [MockFloodOpsApi] for a real
/// `DioFloodOpsApi` in providers/api_provider.dart is the only change
/// needed to go live.
abstract class FloodOpsApi {
  // 1. Auth & device onboarding
  Future<AuthResponse> register(RegisterRequest request);
  Future<AuthResponse> login(LoginRequest request);
  Future<void> registerFcmToken(String token);

  // 2. SOS & offline connectivity
  Future<ReportSummary> createReport(CreateReportRequest request);
  Future<BulkSyncResult> bulkSyncReports(List<CreateReportRequest> requests);

  // 2b. Low Data SOS — a single-packet fallback for edge/2G connectivity
  // (POST /api/reports/lite), distinct from the richer createReport flow.
  Future<ReportSummary> sendLiteSos({required double lat, required double lng, required String description});

  // 6. Crowdsourced verification radar
  Future<List<ReportSummary>> getReports({double? nearLat, double? nearLng});
  Future<ReportSummary> verifyReport(String ticketId, VerifyVote vote);

  // 7. Evacuation map
  Future<ShelterFeatureCollection> getSheltersGeoJson();

  // 4. ML flood risk predictor
  Future<RiskPredictionResponse> predictRisk(RiskPredictionRequest request);

  // 3. RAG survival chatbot
  Future<ChatResponse> sendChatMessage(ChatRequest request);

  // 5. Multi-agent intelligence hub
  Future<AgentHubResponse> runAgentHubAnalysis(String district);

  // 8. Volunteer command hub
  Future<void> updateVolunteerLocation(VolunteerLocationUpdate update);
  Future<List<VolunteerTask>> getVolunteerTasks();

  // 8. Masked calling — real trigger is a background FCM data message
  // (type: "EMERGENCY_INCOMING_CALL") from POST
  // /api/emergency/trigger-masked-call. In this build
  // MockFloodOpsApi.simulateIncomingCall() is invoked by a debug button
  // instead; deliverIncomingCall() is what a real FCM handler calls once
  // Firebase is configured (see services/fcm_service.dart) — both feed
  // the same stream, so MaskedCallScreen needs no changes either way.
  Stream<MaskedCallPayload> get incomingCallStream;
  void simulateIncomingCall();
  void deliverIncomingCall(MaskedCallPayload payload);

  // 9. Real-time command center stream
  Stream<DashboardEvent> get dashboardEventStream;

  // 10. Kerala live dam/river/risk cache (GET /api/dashboard/live-kerala)
  Future<KeralaLiveDashboard> getKeralaLiveDashboard();

  // 11. Voice Agent (POST /api/voice/agent) — Sarvam STT/TTS + Gemini.
  // Takes raw WAV bytes rather than a `dart:io File` so this works
  // identically on web (where there is no real filesystem path to open).
  Future<VoiceAgentResult> sendVoiceQuery({
    required double lat,
    required double lng,
    required Uint8List audioBytes,
  });

  // 12. HITL alert approval — a model-detected high-risk transition
  // creates a pending alert (see run_kerala_flood_pipeline); the citizen-
  // facing high_risk_alert push only fires once a volunteer/official
  // approves it here. Both roles may approve/reject.
  Future<List<PendingAlert>> getPendingAlerts();
  Future<PendingAlert> approveAlert(int alertId);
  Future<PendingAlert> rejectAlert(int alertId);

  void dispose();
}
