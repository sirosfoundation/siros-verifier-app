import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:siros/main.dart';

void main() {
  group('MyApp', () {
    testWidgets('renders MaterialApp with correct title', (tester) async {
      await tester.pumpWidget(const MyApp());
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, equals('Siros Verifier'));
      // Drain the splash screen navigation timer
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('uses Material 3', (tester) async {
      await tester.pumpWidget(const MyApp());
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme?.useMaterial3, isTrue);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('hides debug banner', (tester) async {
      await tester.pumpWidget(const MyApp());
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.debugShowCheckedModeBanner, isFalse);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('starts with SplashScreen', (tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('SplashScreen', () {
    testWidgets('shows SIROS branding text', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      expect(find.text('SIROS'), findsOneWidget);
      expect(find.text('VERIFIER'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('shows progress indicator', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('has dark background', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, equals(const Color(0xFF0A2540)));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('displays verified_user icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('navigates to HomeScreen after delay', (tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('HomeScreen', () {
    testWidgets('shows header with SIROS VERIFIER', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.text('SIROS VERIFIER'), findsOneWidget);
    });

    testWidgets('shows ISO 18013-5 mDL subtitle', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.text('ISO 18013-5 mDL'), findsOneWidget);
    });

    testWidgets('shows main call-to-action text', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.text('Verify a driving licence'), findsOneWidget);
    });

    testWidgets('has Scan QR Code button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows QR code scanner icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
    });

    testWidgets('shows footer tagline', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(
        find.text('Secure · Privacy-preserving · ISO compliant'),
        findsOneWidget,
      );
    });

    testWidgets('has light background', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, equals(const Color(0xFFF5F7FA)));
    });
  });

  group('ResultScreen', () {
    testWidgets('displays credential fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            fields: const {
              'given_name': 'Alice',
              'family_name': 'Smith',
              'birth_date': '1990-01-15',
            },
          ),
        ),
      );

      expect(find.text('Given name'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Family name'), findsOneWidget);
      expect(find.text('Smith'), findsOneWidget);
      expect(find.text('Date of birth'), findsOneWidget);
      expect(find.text('1990-01-15'), findsOneWidget);
    });

    testWidgets('shows verification status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );

      expect(find.text('Credential Verified'), findsOneWidget);
      expect(find.text('ISO 18013-5 mDL · Proximity'), findsOneWidget);
    });

    testWidgets('shows Verification Result header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );

      expect(find.text('Verification Result'), findsOneWidget);
      expect(find.text('Mobile Driving Licence'), findsOneWidget);
    });

    testWidgets('has Done button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('filters out portrait and null fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            fields: const {
              'given_name': 'Test',
              'portrait': 'base64data',
              'empty_field': '',
              'null_field': 'null',
            },
          ),
        ),
      );

      expect(find.text('Test'), findsOneWidget);
      expect(find.text('base64data'), findsNothing);
    });

    testWidgets('uses label mapping for known fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            fields: const {
              'document_number': 'DL-12345',
              'issuing_country': 'SE',
              'expiry_date': '2030-12-31',
            },
          ),
        ),
      );

      expect(find.text('Document number'), findsOneWidget);
      expect(find.text('DL-12345'), findsOneWidget);
      expect(find.text('Issuing country'), findsOneWidget);
      expect(find.text('SE'), findsOneWidget);
      expect(find.text('Expiry date'), findsOneWidget);
      expect(find.text('2030-12-31'), findsOneWidget);
    });

    testWidgets('handles unknown field keys gracefully', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(fields: const {'some_custom_field': 'value123'}),
        ),
      );

      expect(find.text('some custom field'), findsOneWidget);
      expect(find.text('value123'), findsOneWidget);
    });

    testWidgets('shows check_circle icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('shows timestamp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );
      expect(find.textContaining('Verified at'), findsOneWidget);
    });

    testWidgets('Done button navigates to HomeScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('back button navigates to HomeScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ResultScreen(fields: const {'given_name': 'Test'})),
      );
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
