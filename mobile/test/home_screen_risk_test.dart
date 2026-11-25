import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_safe/screens/home_screen.dart';
import 'package:road_safe/services/risk_api_service.dart';

void main() {
  setUp(() {
    RiskApiService.latestRisk.value = null;
  });

  tearDown(() {
    RiskApiService.latestRisk.value = null;
  });

  testWidgets('does not invent a score before assessment', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('Risk assessment not started'), findsOneWidget);
    expect(find.text('32'), findsNothing);
    expect(find.text('LOW RISK'), findsNothing);
    expect(find.text('Accidents'), findsNothing);
  });

  testWidgets('shows partial score without a risk level for incomplete assessment', (tester) async {
    RiskApiService.latestRisk.value = {
      'risk_assessment': 'incomplete',
      'risk_score': 32,
      'risk_level': 'Low',
      'risk_data_gaps': ['heavy_traffic', 'low_visibility'],
      'reasons': [],
    };

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('32'), findsOneWidget);
    expect(find.text('PARTIAL RISK SCORE'), findsOneWidget);
    expect(find.text('PARTIAL SCORE - NO RISK LEVEL'), findsOneWidget);
    expect(find.text('LOW RISK'), findsNothing);
    expect(find.text('Risk score unavailable'), findsNothing);
    expect(find.text('• heavy_traffic'), findsOneWidget);
    expect(find.text('• low_visibility'), findsOneWidget);
  });

  testWidgets('shows zero as a valid partial score', (tester) async {
    RiskApiService.latestRisk.value = {
      'risk_assessment': 'incomplete',
      'risk_score': 0.0,
      'risk_level': null,
      'risk_data_gaps': ['landslide_history'],
      'reasons': [],
    };

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('PARTIAL RISK SCORE'), findsOneWidget);
    expect(find.text('PARTIAL SCORE - NO RISK LEVEL'), findsOneWidget);
    expect(find.text('Assessment incomplete'), findsOneWidget);
    expect(find.text('LOW RISK'), findsNothing);
  });

  testWidgets('shows score when complete assessment has no risk level', (tester) async {
    RiskApiService.latestRisk.value = {
      'risk_assessment': 'complete',
      'risk_score': 24.0,
      'risk_level': null,
      'risk_data_gaps': [],
      'reasons': [],
    };

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('24'), findsOneWidget);
    expect(find.text('RISK LEVEL UNAVAILABLE'), findsOneWidget);
    expect(find.text('Assessment complete'), findsOneWidget);
    expect(find.text('LOW RISK'), findsNothing);
  });

  testWidgets('shows score and level for complete assessment', (tester) async {
    RiskApiService.latestRisk.value = {
      'risk_assessment': 'complete',
      'risk_score': 24,
      'risk_level': 'Low',
      'risk_data_gaps': [],
      'reasons': ['Low slope risk'],
    };

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('24'), findsOneWidget);
    expect(find.text('LOW RISK'), findsOneWidget);
    expect(find.text('Assessment complete'), findsOneWidget);
    expect(find.text('• Low slope risk'), findsOneWidget);
  });
}


