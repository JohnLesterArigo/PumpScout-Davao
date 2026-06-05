import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' as picker;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'firebase_options.dart';

part 'models/app_models.dart';
part 'screens/login_page.dart';
part 'screens/home_page.dart';
part 'widgets/fuel_calculator_panel.dart';
part 'widgets/map_container.dart';
part 'widgets/price_trend_painter.dart';
part 'services/station_service.dart';
part 'services/geocoding_service.dart';
part 'services/mapbox_service.dart';
part 'services/cloudinary_service.dart';
part 'services/contribution_classifier.dart';
part 'services/regional_price_model.dart';
part 'services/price_forecast_service.dart';
part 'services/contributor_trust_service.dart';
part 'utils/geo_utils.dart';
part 'utils/auth_errors.dart';
part 'utils/formatters.dart';

const String accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

const String cloudinaryCloudName = 'dftodunis';
const String cloudinaryUploadPreset = 'pumpscout_reports';
const int stationDemoRadiusMeters = 20000;

bool get isCloudinaryConfigured =>
    cloudinaryCloudName != 'YOUR_CLOUDINARY_CLOUD_NAME' &&
    cloudinaryUploadPreset != 'YOUR_UNSIGNED_UPLOAD_PRESET' &&
    cloudinaryCloudName.trim().isNotEmpty &&
    cloudinaryUploadPreset.trim().isNotEmpty;

bool requiresEmailVerification(User user) =>
    user.providerData.any((provider) => provider.providerId == 'password');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ADD THIS

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  MapboxOptions.setAccessToken(accessToken);

  runApp(const PumpScoutApp());
}

class PumpScoutApp extends StatefulWidget {
  const PumpScoutApp({super.key});

  @override
  State<PumpScoutApp> createState() => _PumpScoutAppState();
}

class _PumpScoutAppState extends State<PumpScoutApp> {
  bool isDarkMode = false;

  void toggleTheme() {
    setState(() {
      isDarkMode = !isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDarkMode ? Brightness.dark : Brightness.light,
        useMaterial3: true,
      ),
      home: AuthGate(isDarkMode: isDarkMode, toggleTheme: toggleTheme),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.isDarkMode,
    required this.toggleTheme,
  });

  final bool isDarkMode;
  final VoidCallback toggleTheme;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        if (requiresEmailVerification(user) && !user.emailVerified) {
          return const LoginPage();
        }

        return HomePage(isDarkMode: isDarkMode, toggleTheme: toggleTheme);
      },
    );
  }
}
