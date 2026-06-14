import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' as picker;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

part 'models/app_models.dart';
part 'screens/login_page.dart';
part 'screens/home_page.dart';
part 'screens/community_contributions_page.dart';
part 'screens/top_contributors_page.dart';
part 'screens/notification_inbox_page.dart';
part 'screens/my_contributions_page.dart';
part 'screens/admin_dashboard_page.dart';
part 'screens/fuel_consumption_editor_sheet.dart';
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
part 'services/trained_price_forecast_service.dart';
part 'services/contributor_experience_service.dart';
part 'utils/geo_utils.dart';
part 'utils/auth_errors.dart';
part 'utils/formatters.dart';

const String accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

const String cloudinaryCloudName = 'dftodunis';
const String cloudinaryUploadPreset = 'pumpscout_reports';
const String firebaseRealtimeDatabaseUrl =
    'https://pumpscout-davao-default-rtdb.asia-southeast1.firebasedatabase.app';
const String demoHardwareStationId = '1ab26M1Oe1CkO02Tayee';
const int stationDemoRadiusMeters = 20000;
const double priceReportMaxDistanceMeters = 3000;
const int mapboxCacheSchemaVersion = 2;

late final Future<FirebaseApp> firebaseInitialization;

bool get isCloudinaryConfigured =>
    cloudinaryCloudName != 'YOUR_CLOUDINARY_CLOUD_NAME' &&
    cloudinaryUploadPreset != 'YOUR_UNSIGNED_UPLOAD_PRESET' &&
    cloudinaryCloudName.trim().isNotEmpty &&
    cloudinaryUploadPreset.trim().isNotEmpty;

bool requiresEmailVerification(User user) =>
    user.providerData.any((provider) => provider.providerId == 'password');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(accessToken);
  await _prepareMapboxCache();
  firebaseInitialization = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ).timeout(const Duration(seconds: 15));

  runApp(const PumpScoutApp());
}

Future<void> _prepareMapboxCache() async {
  if (accessToken.trim().isEmpty) return;

  try {
    final preferences = await SharedPreferences.getInstance();
    final cachedVersion = preferences.getInt('mapboxCacheSchemaVersion') ?? 0;
    if (cachedVersion >= mapboxCacheSchemaVersion) return;

    await MapboxMapsOptions.clearData();
    await preferences.setInt(
      'mapboxCacheSchemaVersion',
      mapboxCacheSchemaVersion,
    );
  } catch (error) {
    debugPrint('Mapbox cache preparation failed: $error');
  }
}

class PumpScoutApp extends StatefulWidget {
  const PumpScoutApp({super.key});

  @override
  State<PumpScoutApp> createState() => _PumpScoutAppState();
}

class _PumpScoutAppState extends State<PumpScoutApp> {
  bool isDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadThemeMode();
    });
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      isDarkMode = !isDarkMode;
    });

    await prefs.setBool('isDarkMode', isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = isDarkMode ? Brightness.dark : Brightness.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _psRed,
      brightness: brightness,
      surface: isDarkMode ? _psPanelBlue : Colors.white,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: isDarkMode ? _psDeepBlue : Colors.white,
        canvasColor: isDarkMode ? _psPanelBlue : Colors.white,
        cardColor: isDarkMode ? _psPanelBlue : Colors.white,
        dividerColor: isDarkMode ? _psDarkBorder : _psLightBorder,
        dialogTheme: DialogThemeData(
          backgroundColor: isDarkMode ? _psPanelBlue : Colors.white,
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: isDarkMode ? _psPanelBlue : Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: isDarkMode ? _psDeepBlue : Colors.white,
          foregroundColor: isDarkMode ? Colors.white : _psDeepBlue,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: isDarkMode ? _psPanelBlue : Colors.white,
          indicatorColor: _psRed.withValues(alpha: 0.16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDarkMode ? _psSoftPanel : _psLightSoftPanel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDarkMode ? _psDarkBorder : _psLightBorder,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDarkMode ? _psDarkBorder : _psLightBorder,
            ),
          ),
        ),
      ),
      home: FirebaseStartupGate(
        isDarkMode: isDarkMode,
        toggleTheme: toggleTheme,
      ),
    );
  }
}

class FirebaseStartupGate extends StatelessWidget {
  const FirebaseStartupGate({
    super.key,
    required this.isDarkMode,
    required this.toggleTheme,
  });

  final bool isDarkMode;
  final VoidCallback toggleTheme;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: firebaseInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const StartupLoadingScreen();
        }

        if (snapshot.hasError) {
          return StartupErrorScreen(error: snapshot.error);
        }

        return AuthGate(isDarkMode: isDarkMode, toggleTheme: toggleTheme);
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.isDarkMode,
    required this.toggleTheme,
  });

  final bool isDarkMode;
  final VoidCallback toggleTheme;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool authWaitExpired = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        authWaitExpired = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (!authWaitExpired) return const StartupLoadingScreen();
          return _buildScreenForUser(FirebaseAuth.instance.currentUser);
        }

        return _buildScreenForUser(snapshot.data);
      },
    );
  }

  Widget _buildScreenForUser(User? user) {
    if (user == null) {
      return const LoginPage();
    }

    if (requiresEmailVerification(user) && !user.emailVerified) {
      return const LoginPage();
    }

    return HomePage(
      isDarkMode: widget.isDarkMode,
      toggleTheme: widget.toggleTheme,
    );
  }
}

class StartupLoadingScreen extends StatelessWidget {
  const StartupLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFFFFF7FB),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: Color(0xFFE94B5A),
                  strokeWidth: 4,
                ),
              ),
              SizedBox(height: 18),
              Text(
                'Loading PumpScout...',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFE94B5A),
                  size: 42,
                ),
                const SizedBox(height: 14),
                const Text(
                  'PumpScout could not start',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF5F6F85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
