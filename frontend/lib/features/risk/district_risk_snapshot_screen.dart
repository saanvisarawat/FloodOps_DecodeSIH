import 'package:flutter/material.dart';

import 'risk_predictor_screen.dart';

/// Read-only wrapper around the same citizen-facing live conditions +
/// risk score view (`RiskPredictorScreen`), pushed as a standalone route
/// from the Volunteer Hub. Volunteers see the live values only — the
/// manual what-if slider tool (`ManualRiskPredictorScreen`) stays
/// official-only, reachable from the Command Center.
class DistrictRiskSnapshotScreen extends StatelessWidget {
  const DistrictRiskSnapshotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('District Risk Levels')),
      body: const RiskPredictorScreen(),
    );
  }
}
