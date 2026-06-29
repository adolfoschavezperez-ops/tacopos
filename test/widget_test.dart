import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/constants/app_constants.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/widgets/brand_logo_mark.dart';

void main() {
  testWidgets('renders TacoPOS brand mark', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: BrandLogoMark()),
      ),
    );

    expect(find.text(AppConstants.brandName.toUpperCase()), findsOneWidget);
    expect(find.text('TacoPOS by RenovaDev'), findsOneWidget);
  });
}
