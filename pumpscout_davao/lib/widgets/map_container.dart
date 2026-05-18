part of '../main.dart';

class MapContainer extends StatefulWidget {
  final bool isDarkMode;

  const MapContainer({super.key, required this.isDarkMode});

  @override
  State<MapContainer> createState() => _MapContainerState();
}

class _MapContainerState extends State<MapContainer> {
  static const String routeSourceId = 'active-route-source';
  static const String routeLayerId = 'active-route-layer';
  static const String terrainSourceId = 'mapbox-dem';
  static const String buildingsLayerId = '3d-buildings';
  static const bool enableDetailed3D = false;

  MapboxMap? mapboxMap;
  CircleAnnotationManager? stationAnnotationManager;
  PointAnnotationManager? stationLabelManager;
  StreamSubscription<geo.Position>? locationSubscription;
  geo.Position? currentLocation;
  List<dynamic>? cachedStations;
  List<StationPrice> firestoreStations = [];
  List<StationMarkerDetails> nearbyStationDetails = [];
  final Map<String, StationMarkerDetails> stationDetailsByAnnotationId = {};
  final Set<String> favoriteStationKeys = {};
  final Map<String, StationMarkerDetails> savedStationDetailsByKey = {};
  StationMarkerDetails? activeRouteDestination;
  _RouteDashboardData? activeRouteDashboard;
  bool isRouteActive = false;
  int stationLoadId = 0;

  String get mapStyleUri =>
      widget.isDarkMode ? MapboxStyles.DARK : MapboxStyles.MAPBOX_STREETS;

  @override
  void initState() {
    super.initState();
    loadSavedStationKeys();
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadSavedStationKeys() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final savedKeys = data?['savedStationKeys'];
      final savedStations = data?['savedStations'];
      if (savedKeys is! List && savedStations is! List) return;

      final keys = savedKeys is List
          ? savedKeys.whereType<String>().toSet()
          : <String>{};
      final detailsByKey = <String, StationMarkerDetails>{};
      if (savedStations is List) {
        for (final item in savedStations) {
          if (item is! Map) continue;
          final data = Map<String, dynamic>.from(item);
          final details = _savedStationFromMap(data);
          final key = _stringField(data, 'key');
          if (key.isEmpty || details == null) continue;
          keys.add(key);
          detailsByKey[key] = details;
        }
      }

      if (!mounted) return;
      setState(() {
        favoriteStationKeys
          ..clear()
          ..addAll(keys);
        savedStationDetailsByKey
          ..clear()
          ..addAll(detailsByKey);
      });
    } catch (error) {
      debugPrint('Saved stations load failed: $error');
    }
  }

  Future<void> saveStationKeys() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'savedStationKeys': favoriteStationKeys.toList()..sort(),
      'savedStations': _savedStationMaps(),
      'savedStationKeysUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleSavedStation(StationMarkerDetails details) async {
    final key = _stationFavoriteKey(details);
    setState(() {
      if (!favoriteStationKeys.add(key)) {
        favoriteStationKeys.remove(key);
        savedStationDetailsByKey.remove(key);
      } else {
        savedStationDetailsByKey[key] = details;
      }
    });

    try {
      await saveStationKeys();
    } catch (error) {
      debugPrint('Saved stations update failed: $error');
    }
  }

  Future<void> removeSavedStation(StationMarkerDetails details) async {
    final key = _stationFavoriteKey(details);
    setState(() {
      favoriteStationKeys.remove(key);
      savedStationDetailsByKey.remove(key);
    });

    try {
      await saveStationKeys();
    } catch (error) {
      debugPrint('Saved stations remove failed: $error');
    }
  }

  List<Map<String, Object?>> _savedStationMaps() {
    final maps = <Map<String, Object?>>[];
    for (final key in favoriteStationKeys) {
      final details =
          savedStationDetailsByKey[key] ?? _nearbyStationForKey(key);
      if (details == null) continue;
      maps.add(_savedStationToMap(key, details));
    }
    return maps;
  }

  StationMarkerDetails? _nearbyStationForKey(String key) {
    for (final station in nearbyStationDetails) {
      if (_stationFavoriteKey(station) == key) return station;
    }
    return null;
  }

  Map<String, Object?> _savedStationToMap(
    String key,
    StationMarkerDetails details,
  ) {
    final price = details.price;
    return {
      'key': key,
      'name': details.name,
      'brand': details.brand,
      'lat': details.lat,
      'lng': details.lng,
      'priceId': price?.id,
      'priceName': price?.name,
      'priceBrand': price?.brand,
      'gasoline': price?.gasoline,
      'diesel': price?.diesel,
      'premium': price?.premium,
      'priceUpdatedAt': price?.updatedAt == null
          ? null
          : Timestamp.fromDate(price!.updatedAt!),
    };
  }

  StationMarkerDetails? _savedStationFromMap(Map<String, dynamic> data) {
    final lat = _doubleField(data, 'lat');
    final lng = _doubleField(data, 'lng');
    if (lat == null || lng == null) return null;

    final priceId = _stringField(data, 'priceId');
    final price = priceId.isEmpty
        ? null
        : StationPrice(
            id: priceId,
            name: _stringField(
              data,
              'priceName',
              fallback: _stringField(data, 'name', fallback: 'Fuel station'),
            ),
            brand: _stringField(
              data,
              'priceBrand',
              fallback: _stringField(data, 'brand'),
            ),
            lat: lat,
            lng: lng,
            gasoline: _doubleField(data, 'gasoline'),
            diesel: _doubleField(data, 'diesel'),
            premium: _doubleField(data, 'premium'),
            updatedAt: _dateTimeField(data, 'priceUpdatedAt'),
          );

    return StationMarkerDetails(
      name: _stringField(data, 'name', fallback: 'Fuel station'),
      brand: _stringField(data, 'brand'),
      lat: lat,
      lng: lng,
      distanceMeters: _distanceFromCurrentLocation(lat, lng),
      price: price,
    );
  }

  double? _distanceFromCurrentLocation(double lat, double lng) {
    final location = currentLocation;
    if (location == null) return null;
    return geo.Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      lat,
      lng,
    );
  }

  Future<void> moveToCurrentLocation() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await geo.Geolocator.requestPermission();
    if (permission == geo.LocationPermission.denied) return;
    if (permission == geo.LocationPermission.deniedForever) return;

    final location = await geo.Geolocator.getCurrentPosition();
    await refreshForLocation(location, moveCamera: true, useCache: true);
  }

  Future<void> startLocationUpdates() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await geo.Geolocator.requestPermission();
    if (permission == geo.LocationPermission.denied) return;
    if (permission == geo.LocationPermission.deniedForever) return;

    await locationSubscription?.cancel();
    locationSubscription =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 1200,
          ),
        ).listen((location) {
          refreshForLocation(location, moveCamera: false, useCache: true);
        });
  }

  Future<void> refreshForLocation(
    geo.Position location, {
    required bool moveCamera,
    required bool useCache,
  }) async {
    final loadId = ++stationLoadId;
    if (!mounted || loadId != stationLoadId) return;
    currentLocation = location;

    if (isRouteActive && activeRouteDestination != null) {
      final destination = activeRouteDestination!;
      final distanceToDestination = geo.Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        destination.lat,
        destination.lng,
      );

      if (distanceToDestination <= 50) {
        await cancelRoute();
        return;
      }

      await focusRouteFromCurrentLocation(destination);
      return;
    }

    if (moveCamera) {
      await mapboxMap?.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(location.longitude, location.latitude),
          ),
          zoom: 15,
          pitch: 55,
          bearing: -20,
        ),
      );
    }

    if (useCache && cachedStations != null) {
      await drawStationMarkers(cachedStations!, loadId);
      return;
    }

    await addStationsFromAPI(location.latitude, location.longitude, loadId);
  }

  Future<void> addStationsFromAPI(double lat, double lng, int loadId) async {
    if (mapboxMap == null) return;

    firestoreStations = await fetchStationPrices();
    final pricedStations = _firestoreStationMapsNear(lat, lng);
    if (pricedStations.isNotEmpty && cachedStations == null) {
      cachedStations = pricedStations;
      await drawStationMarkers(pricedStations, loadId);
    }

    final liveStations = await fetchGasStations(lat, lng);
    final stations = _mergeStationSources(liveStations, pricedStations);
    debugPrint(
      'Overpass returned ${liveStations.length} raw fuel station results',
    );
    debugPrint('Firestore returned ${firestoreStations.length} price records');
    debugPrint('Drawing ${stations.length} merged station markers');
    if (!mounted || loadId != stationLoadId || mapboxMap == null) return;
    if (liveStations.isEmpty && cachedStations != null) {
      debugPrint('Keeping cached station markers because refresh was empty');
      return;
    }

    cachedStations = stations;
    await drawStationMarkers(stations, loadId);
  }

  List<dynamic> _firestoreStationMapsNear(double lat, double lng) {
    return firestoreStations
        .where((station) {
          if (station.lat == 0 || station.lng == 0) return false;
          final distance = geo.Geolocator.distanceBetween(
            lat,
            lng,
            station.lat,
            station.lng,
          );
          return distance <= 12000;
        })
        .map(
          (station) => {
            'lat': station.lat,
            'lon': station.lng,
            'tags': {
              'name': station.name,
              'brand': station.brand.isNotEmpty ? station.brand : station.name,
              'operator': station.brand,
            },
          },
        )
        .toList();
  }

  List<dynamic> _mergeStationSources(
    List<dynamic> liveStations,
    List<dynamic> pricedStations,
  ) {
    final merged = <dynamic>[...liveStations];

    for (final pricedStation in pricedStations) {
      final pricedLat = _stationLatitude(pricedStation);
      final pricedLng = _stationLongitude(pricedStation);
      if (pricedLat == null || pricedLng == null) continue;

      final alreadyIncluded = merged.any((liveStation) {
        final liveLat = _stationLatitude(liveStation);
        final liveLng = _stationLongitude(liveStation);
        if (liveLat == null || liveLng == null) return false;

        final distance = geo.Geolocator.distanceBetween(
          pricedLat,
          pricedLng,
          liveLat,
          liveLng,
        );
        return distance <= 35;
      });

      if (!alreadyIncluded) {
        merged.add(pricedStation);
      }
    }

    return merged;
  }

  Future<void> drawStationMarkers(List<dynamic> stations, int loadId) async {
    stationAnnotationManager ??= await mapboxMap!.annotations
        .createCircleAnnotationManager();
    await stationAnnotationManager!.deleteAll();
    stationDetailsByAnnotationId.clear();
    nearbyStationDetails = [];

    var markerCount = 0;
    final sortedStations = _stationsSortedByDistance(stations).take(80);

    for (var station in sortedStations) {
      final stationLat = _stationLatitude(station);
      final stationLng = _stationLongitude(station);
      if (stationLat == null || stationLng == null) continue;
      final liveName = _stationName(station);
      final price = _nearestPriceFor(stationLat, stationLng, liveName);
      final hasLiveName = liveName != 'Fuel';
      final name = hasLiveName ? liveName : price?.name ?? liveName;
      final brand = hasLiveName
          ? liveName
          : price?.brand.isNotEmpty == true
          ? price!.brand
          : name;
      final distanceMeters = currentLocation == null
          ? null
          : geo.Geolocator.distanceBetween(
              currentLocation!.latitude,
              currentLocation!.longitude,
              stationLat,
              stationLng,
            );
      final details = StationMarkerDetails(
        name: name,
        brand: brand,
        lat: stationLat,
        lng: stationLng,
        distanceMeters: distanceMeters,
        price: price,
      );
      nearbyStationDetails.add(details);

      try {
        final annotation = await stationAnnotationManager!.create(
          CircleAnnotationOptions(
            geometry: Point(coordinates: Position(stationLng, stationLat)),
            circleColor: price == null
                ? const Color(0xFF9CA3AF).toARGB32()
                : const Color(0xFF00C853).toARGB32(),
            circleRadius: 7,
            circleStrokeColor: Colors.white.toARGB32(),
            circleStrokeWidth: 2,
            circleOpacity: 0.95,
            customData: {'stationIndex': markerCount},
          ),
        );
        stationDetailsByAnnotationId[annotation.id] = details;
        markerCount++;
      } catch (error) {
        debugPrint('Station marker draw failed for $name: $error');
      }
    }

    stationAnnotationManager!.tapEvents(onTap: showStationPriceSheet);
    debugPrint('Loaded $markerCount nearby fuel station markers');
  }

  List<dynamic> _stationsSortedByDistance(List<dynamic> stations) {
    final origin = currentLocation;
    if (origin == null) return stations;

    final sorted = [...stations];
    sorted.sort((a, b) {
      final aLat = _stationLatitude(a);
      final aLng = _stationLongitude(a);
      final bLat = _stationLatitude(b);
      final bLng = _stationLongitude(b);
      if (aLat == null || aLng == null) return 1;
      if (bLat == null || bLng == null) return -1;

      final aDistance = geo.Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        aLat,
        aLng,
      );
      final bDistance = geo.Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        bLat,
        bLng,
      );
      return aDistance.compareTo(bDistance);
    });
    return sorted;
  }

  StationPrice? _nearestPriceFor(double lat, double lng, String liveName) {
    StationPrice? nearest;
    var nearestDistance = double.infinity;
    final hasLiveName = liveName != 'Fuel';

    for (final station in firestoreStations) {
      if (station.lat == 0 || station.lng == 0) continue;

      final distance = geo.Geolocator.distanceBetween(
        lat,
        lng,
        station.lat,
        station.lng,
      );

      if (hasLiveName && !_stationNamesMatch(liveName, station)) {
        continue;
      }

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }

    final maxDistance = hasLiveName ? 80 : 30;
    return nearestDistance <= maxDistance ? nearest : null;
  }

  bool _stationNamesMatch(String liveName, StationPrice station) {
    final live = _normalizedStationName(liveName);
    final firestoreName = _normalizedStationName(station.name);
    final firestoreBrand = _normalizedStationName(station.brand);
    final compactLive = live.replaceAll(' ', '');
    final compactFirestoreName = firestoreName.replaceAll(' ', '');
    final compactFirestoreBrand = firestoreBrand.replaceAll(' ', '');

    if (live.isEmpty) return false;
    if (firestoreName.isNotEmpty &&
        (live == firestoreName ||
            compactLive == compactFirestoreName ||
            live.contains(firestoreName) ||
            firestoreName.contains(live))) {
      return true;
    }

    if (firestoreBrand.isNotEmpty &&
        (live == firestoreBrand ||
            compactLive == compactFirestoreBrand ||
            live.contains(firestoreBrand) ||
            firestoreBrand.contains(live))) {
      return true;
    }

    return false;
  }

  String _normalizedStationName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .where((word) {
          return word.isNotEmpty &&
              word != 'gas' &&
              word != 'gasoline' &&
              word != 'fuel' &&
              word != 'station' &&
              word != 'service' &&
              word != 'sevice' &&
              word != 'petroleum' &&
              word != 'inc' &&
              word != 'corp' &&
              word != 'corporation';
        })
        .join(' ');
  }

  void showStationPriceSheet(CircleAnnotation annotation) {
    final details = stationDetailsByAnnotationId[annotation.id];
    if (details == null) {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Text(
              'Station details are not available.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          );
        },
      );
      return;
    }

    showStationDetailSheet(details);
  }

  void showStationDetailSheet(StationMarkerDetails details) {
    final price = details.price;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 28 + bottomPadding),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            details.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            details.brand,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (details.distanceMeters != null) ...[
                            const SizedBox(height: 4),
                            Text(_formatDistance(details.distanceMeters!)),
                          ],
                        ],
                      ),
                    ),
                    StatefulBuilder(
                      builder: (context, setActionState) {
                        final isFavorite = favoriteStationKeys.contains(
                          _stationFavoriteKey(details),
                        );

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: isFavorite
                                  ? 'Remove favorite'
                                  : 'Favorite station',
                              onPressed: () async {
                                await toggleSavedStation(details);
                                if (!context.mounted) return;
                                setActionState(() {});
                              },
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                color: Colors.amber.shade700,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Show route',
                              onPressed: () => showInAppRoute(details),
                              icon: const Icon(Icons.navigation),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => showInAppRoute(details),
                    icon: const Icon(Icons.route),
                    label: const Text('Show route in app'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _canReportPrice(details)
                        ? () => showPriceReportSheet(details)
                        : null,
                    icon: const Icon(Icons.edit_location_alt),
                    label: const Text('Report updated prices'),
                  ),
                ),
                if (!_canReportPrice(details)) ...[
                  const SizedBox(height: 6),
                  Text(
                    'You must be within 3 km of this station to report prices.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Current Prices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (price?.updatedAt != null) ...[
                  const SizedBox(height: 4),
                  _priceFreshnessBadge(price!.updatedAt!),
                ],
                const SizedBox(height: 8),
                if (price == null)
                  const Text('No price data yet for this station.')
                else
                  ..._fuelDisplayItems(
                    details,
                  ).map((item) => _priceRow(item.label, item.price)),
                const SizedBox(height: 10),
                _priceDisclaimer(),
                const SizedBox(height: 16),
                Text(
                  'Gasoline Trend',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<PriceReport>>(
                  future: fetchPriceReports(details),
                  builder: (context, snapshot) {
                    final reports = snapshot.data ?? const <PriceReport>[];
                    final values = reports
                        .map((report) => report.gasoline)
                        .whereType<double>()
                        .toList();

                    if (values.length < 2) {
                      return const Text('No weekly trend yet.');
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 92,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: PriceTrendPainter(values),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_trendLabel(values)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showNearbyStationsPanel() {
    final stations = _nearbyStationsWithin3Km();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sortedStations = _nearbyStationsWithin3Km();

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby Stations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Within 3 km • Sorted by distance',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (stations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No nearby stations within 3 km yet.'),
                    )
                  else
                    SizedBox(
                      height: math.min(
                        MediaQuery.of(context).size.height * 0.45,
                        sortedStations.length * 92.0,
                      ),
                      child: ListView.separated(
                        itemCount: sortedStations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final details = sortedStations[index];
                          final isFavorite = favoriteStationKeys.contains(
                            _stationFavoriteKey(details),
                          );

                          return _nearbyStationTile(
                            details: details,
                            isFavorite: isFavorite,
                            onFavoritePressed: () async {
                              await toggleSavedStation(details);
                              if (!context.mounted) return;
                              setSheetState(() {});
                            },
                            onOpen: () {
                              Navigator.of(context).pop();
                              showStationDetailSheet(details);
                            },
                            onNavigate: () => showInAppRoute(details),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void showCheapestStationsPanel() {
    var selectedRangeKm = 3;
    var selectedFuel = 'gasoline';

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.66,
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final stations = _cheapestStations(
              rangeKm: selectedRangeKm,
              fuelType: selectedFuel,
            );

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cheapest Stations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sorted by lowest ${_fuelLabel(selectedFuel)} price',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedRangeKm,
                          decoration: const InputDecoration(
                            labelText: 'Range',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 km')),
                            DropdownMenuItem(value: 8, child: Text('8 km')),
                            DropdownMenuItem(value: 10, child: Text('10 km')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() {
                              selectedRangeKm = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedFuel,
                          decoration: const InputDecoration(
                            labelText: 'Fuel',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'gasoline',
                              child: Text('Gasoline'),
                            ),
                            DropdownMenuItem(
                              value: 'diesel',
                              child: Text('Diesel'),
                            ),
                            DropdownMenuItem(
                              value: 'premium',
                              child: Text('Premium'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() {
                              selectedFuel = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (stations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No ${_fuelLabel(selectedFuel).toLowerCase()} prices found within $selectedRangeKm km.',
                      ),
                    )
                  else
                    SizedBox(
                      height: math.min(
                        MediaQuery.of(context).size.height * 0.45,
                        stations.length * 88.0,
                      ),
                      child: ListView.separated(
                        itemCount: stations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final details = stations[index];
                          return _cheapestStationTile(
                            details: details,
                            fuelType: selectedFuel,
                            rank: index + 1,
                            isFavorite: favoriteStationKeys.contains(
                              _stationFavoriteKey(details),
                            ),
                            onFavoritePressed: () async {
                              await toggleSavedStation(details);
                              if (!context.mounted) return;
                              setSheetState(() {});
                            },
                            onOpen: () {
                              Navigator.of(context).pop();
                              showStationDetailSheet(details);
                            },
                            onNavigate: () => showInAppRoute(details),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void showSavedStationsPanel() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final stations = _savedStations();

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved Stations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Stations starred from Nearby',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (stations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No saved stations yet. Star stations from Nearby first.',
                      ),
                    )
                  else
                    SizedBox(
                      height: math.min(
                        MediaQuery.of(context).size.height * 0.45,
                        stations.length * 92.0,
                      ),
                      child: ListView.separated(
                        itemCount: stations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final details = stations[index];

                          return _nearbyStationTile(
                            details: details,
                            isFavorite: true,
                            onFavoritePressed: () async {
                              await removeSavedStation(details);
                              setSheetState(() {});
                            },
                            onOpen: () {
                              Navigator.of(context).pop();
                              showStationDetailSheet(details);
                            },
                            onNavigate: () => showInAppRoute(details),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<StationMarkerDetails> _nearbyStationsWithin3Km() {
    final stations = nearbyStationDetails.where((details) {
      final distance = details.distanceMeters;
      return distance != null && distance <= 3000;
    }).toList();

    stations.sort((a, b) {
      final aFavorite = favoriteStationKeys.contains(_stationFavoriteKey(a));
      final bFavorite = favoriteStationKeys.contains(_stationFavoriteKey(b));
      if (aFavorite != bFavorite) return aFavorite ? -1 : 1;

      final aDistance = a.distanceMeters ?? double.infinity;
      final bDistance = b.distanceMeters ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });

    return stations;
  }

  List<StationMarkerDetails> _savedStations() {
    final stationsByKey = <String, StationMarkerDetails>{
      ...savedStationDetailsByKey,
    };

    for (final details in nearbyStationDetails) {
      final key = _stationFavoriteKey(details);
      if (favoriteStationKeys.contains(key)) {
        stationsByKey[key] = details;
        savedStationDetailsByKey[key] = details;
      }
    }

    final stations = [
      for (final key in favoriteStationKeys)
        if (stationsByKey[key] != null) stationsByKey[key]!,
    ];

    stations.sort((a, b) {
      final aDistance = a.distanceMeters ?? double.infinity;
      final bDistance = b.distanceMeters ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });

    return stations;
  }

  List<StationMarkerDetails> _cheapestStations({
    required int rangeKm,
    required String fuelType,
  }) {
    final maxDistanceMeters = rangeKm * 1000;
    final stations = nearbyStationDetails.where((details) {
      final distance = details.distanceMeters;
      return distance != null &&
          distance <= maxDistanceMeters &&
          _fuelPrice(details.price, fuelType) != null;
    }).toList();

    stations.sort((a, b) {
      final aPrice = _fuelPrice(a.price, fuelType) ?? double.infinity;
      final bPrice = _fuelPrice(b.price, fuelType) ?? double.infinity;
      final priceCompare = aPrice.compareTo(bPrice);
      if (priceCompare != 0) return priceCompare;

      final aDistance = a.distanceMeters ?? double.infinity;
      final bDistance = b.distanceMeters ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });

    return stations;
  }

  Widget _cheapestStationTile({
    required StationMarkerDetails details,
    required String fuelType,
    required int rank,
    required bool isFavorite,
    required VoidCallback onFavoritePressed,
    required VoidCallback onOpen,
    required VoidCallback onNavigate,
  }) {
    final price = _fuelPrice(details.price, fuelType);

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE8F5E9),
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Color(0xFF00A152),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stationTitle(details),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (details.distanceMeters != null)
                        _formatCompactDistance(details.distanceMeters!),
                      _freshnessLabel(details.price?.updatedAt),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fuelLabelForStation(details, fuelType),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  price == null ? 'No data' : 'PHP ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00A152),
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: isFavorite ? 'Remove favorite' : 'Favorite station',
              onPressed: onFavoritePressed,
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: Colors.amber.shade700,
              ),
            ),
            IconButton(
              tooltip: 'Show route',
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nearbyStationTile({
    required StationMarkerDetails details,
    required bool isFavorite,
    required VoidCallback onFavoritePressed,
    required VoidCallback onOpen,
    required VoidCallback onNavigate,
  }) {
    final price = details.price;
    final primaryPrice = _primaryStationPrice(details);

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEFF4F1),
              child: Icon(
                Icons.local_gas_station,
                color: price == null
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF00A152),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stationTitle(details),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      primaryPrice ?? 'No price data',
                      if (details.distanceMeters != null)
                        _formatCompactDistance(details.distanceMeters!),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _freshnessLabel(price?.updatedAt),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _nearbyPriceSummary(details),
            IconButton(
              tooltip: isFavorite ? 'Remove favorite' : 'Favorite station',
              onPressed: onFavoritePressed,
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: Colors.amber.shade700,
              ),
            ),
            IconButton(
              tooltip: 'Show route',
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nearbyPriceSummary(StationMarkerDetails details) {
    final lines = <String>[];
    final price = details.price;
    if (price != null) {
      for (final item in _fuelDisplayItems(details)) {
        if (item.price != null) {
          lines.add(
            '${item.shortLabel}: PHP ${item.price!.toStringAsFixed(2)}',
          );
        }
      }
    }

    if (lines.isEmpty) {
      return const SizedBox(width: 96);
    }

    return SizedBox(
      width: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: lines
            .take(3)
            .map(
              (line) => Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _priceRow(String label, double? price) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(
            price == null ? 'No data' : 'PHP ${price.toStringAsFixed(2)} / L',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _priceDisclaimer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fuel prices are approximate and may come from user reports or estimates. Please confirm the actual pump price at the station before refueling.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canReportPrice(StationMarkerDetails details) {
    final distance = details.distanceMeters;
    return distance != null && distance <= 3000;
  }

  void showPriceReportSheet(StationMarkerDetails details) {
    final gasolineController = TextEditingController(
      text: details.price?.gasoline?.toStringAsFixed(2) ?? '',
    );
    final dieselController = TextEditingController(
      text: details.price?.diesel?.toStringAsFixed(2) ?? '',
    );
    final premiumController = TextEditingController(
      text: details.price?.premium?.toStringAsFixed(2) ?? '',
    );
    picker.XFile? selectedImage;
    var isSubmitting = false;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomPadding),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report prices',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(details.name),
                    const SizedBox(height: 16),
                    _reportPriceField(
                      controller: gasolineController,
                      label: _fuelLabelForStation(details, 'gasoline'),
                    ),
                    _reportPriceField(
                      controller: dieselController,
                      label: _fuelLabelForStation(details, 'diesel'),
                    ),
                    _reportPriceField(
                      controller: premiumController,
                      label: _fuelLabelForStation(details, 'premium'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final image = await picker.ImagePicker()
                                  .pickImage(
                                    source: picker.ImageSource.camera,
                                    imageQuality: 75,
                                  );
                              if (image == null) return;
                              setSheetState(() {
                                selectedImage = image;
                              });
                            },
                      icon: const Icon(Icons.photo_camera),
                      label: Text(
                        selectedImage == null
                            ? 'Attach price board photo'
                            : 'Photo attached',
                      ),
                    ),
                    if (!isCloudinaryConfigured) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Photo upload needs Cloudinary setup. Price reports still save.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setSheetState(() {
                                  isSubmitting = true;
                                });
                                final success = await submitPriceReport(
                                  details: details,
                                  gasoline: _parsePrice(
                                    gasolineController.text,
                                  ),
                                  diesel: _parsePrice(dieselController.text),
                                  premium: _parsePrice(premiumController.text),
                                  image: selectedImage,
                                );
                                if (!mounted) return;
                                Navigator.of(this.context).pop();
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? 'Price report submitted for verification.'
                                          : 'Price report failed.',
                                    ),
                                  ),
                                );
                              },
                        child: Text(isSubmitting ? 'Submitting...' : 'Submit'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _reportPriceField({
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'PHP ',
          suffixText: '/ L',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<bool> submitPriceReport({
    required StationMarkerDetails details,
    required double? gasoline,
    required double? diesel,
    required double? premium,
    required picker.XFile? image,
  }) async {
    if (!_canReportPrice(details)) return false;
    if (gasoline == null && diesel == null && premium == null) return false;

    try {
      final now = DateTime.now();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final stationRef = details.price == null
          ? FirebaseFirestore.instance.collection('stations').doc()
          : FirebaseFirestore.instance
                .collection('stations')
                .doc(details.price!.id);
      final stationKey = _stationReportKey(details);
      final existingPendingReport = await _pendingReportForStation(
        user.uid,
        stationKey,
      );
      final shouldUpdateExisting = existingPendingReport == null
          ? false
          : await _confirmPendingReportUpdate(details);
      if (existingPendingReport != null && !shouldUpdateExisting) {
        return false;
      }

      String? photoUrl;
      String? photoPublicId;

      if (image != null) {
        final upload = await uploadPriceReportImageToCloudinary(
          image: image,
          stationId: stationRef.id,
          createdAt: now,
        );
        photoUrl = upload?.secureUrl;
        photoPublicId = upload?.publicId;
      }

      final reportData = <String, Object?>{
        'stationId': stationRef.id,
        'stationKey': stationKey,
        'stationName': details.name,
        'brand': details.brand,
        'lat': details.lat,
        'lng': details.lng,
        'gasoline': gasoline,
        'diesel': diesel,
        'premium': premium,
        'status': 'pending',
        'photoProvider': photoUrl == null ? null : 'cloudinary',
        'photoUrl': photoUrl,
        'photoPublicId': photoPublicId,
        'photoUploadFailed': image != null && photoUrl == null,
        'updatedAt': Timestamp.fromDate(now),
        'distanceMeters': details.distanceMeters,
        'userId': user.uid,
        'userEmail': user.email,
        'userDisplayName': user.displayName,
      };

      if (existingPendingReport == null) {
        await FirebaseFirestore.instance.collection('priceReports').add({
          ...reportData,
          'createdAt': Timestamp.fromDate(now),
        });
      } else {
        await existingPendingReport.reference.set(
          reportData,
          SetOptions(merge: true),
        );
      }

      return true;
    } catch (error) {
      debugPrint('Price report submit failed: $error');
      return false;
    }
  }

  String _stationReportKey(StationMarkerDetails details) {
    final priceId = details.price?.id;
    if (priceId != null && priceId.isNotEmpty) return 'station:$priceId';

    final normalizedName = details.name.trim().toLowerCase();
    return 'live:$normalizedName:${details.lat.toStringAsFixed(5)},${details.lng.toStringAsFixed(5)}';
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _pendingReportForStation(
    String userId,
    String stationKey,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('userId', isEqualTo: userId)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_stringField(data, 'status') == 'pending' &&
          _stringField(data, 'stationKey') == stationKey) {
        return doc;
      }
    }
    return null;
  }

  Future<bool> _confirmPendingReportUpdate(StationMarkerDetails details) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update pending report?'),
          content: Text(
            'You already have a pending report for ${details.name}. Update that report instead of creating another one?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> refreshPriceMarkersFromFirestore() async {
    final location = currentLocation;
    if (location == null || mapboxMap == null) {
      await moveToCurrentLocation();
      return;
    }

    final loadId = ++stationLoadId;
    firestoreStations = await fetchStationPrices();
    if (!mounted || loadId != stationLoadId || mapboxMap == null) return;

    final pricedStations = _firestoreStationMapsNear(
      location.latitude,
      location.longitude,
    );
    cachedStations = pricedStations;
    await drawStationMarkers(pricedStations, loadId);
  }

  Future<void> showInAppRoute(StationMarkerDetails details) async {
    final origin = currentLocation;
    if (origin == null || mapboxMap == null) return;

    Navigator.of(context).pop();

    final route = await fetchDrivingRoute(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destinationLat: details.lat,
      destinationLng: details.lng,
    );
    if (!mounted || route == null) return;

    await drawRoute(route);
    await focusRouteFromCurrentLocation(details);
    await showTrafficRouteSummary(
      route,
      destinationName: _stationTitle(details),
    );
    if (mounted) {
      setState(() {
        activeRouteDestination = details;
        isRouteActive = true;
      });
    }
  }

  Future<void> showRouteToPlace(DestinationPlace place) async {
    final origin = currentLocation;
    if (origin == null || mapboxMap == null) return;

    final route = await fetchDrivingRoute(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destinationLat: place.lat,
      destinationLng: place.lng,
    );
    if (!mounted || route == null) return;

    final destination = StationMarkerDetails(
      name: place.name,
      brand: 'Destination',
      lat: place.lat,
      lng: place.lng,
      distanceMeters: null,
    );

    await drawRoute(route);
    await focusRouteFromCurrentLocation(destination);
    await showTrafficRouteSummary(route, destinationName: place.name);
    if (mounted) {
      setState(() {
        activeRouteDestination = destination;
        isRouteActive = true;
      });
    }
  }

  Future<void> showCheapestDetourAnalysis(DestinationPlace place) async {
    final origin = currentLocation;
    if (origin == null || mapboxMap == null) return;

    final fuelType = await _preferredFuelType();
    final options = _refuelOptionsForDestination(place, fuelType);
    if (!mounted) return;

    if (options.isEmpty) {
      _showSimpleMapMessage(
        'No ${_fuelLabel(fuelType).toLowerCase()} price data found yet.',
      );
      return;
    }

    showRefuelOptionsSheet(options, place);
  }

  List<RefuelOption> _refuelOptionsForDestination(
    DestinationPlace place,
    String fuelType,
  ) {
    final origin = currentLocation;
    if (origin == null) return [];

    final referencePrice = _referenceFuelPrice(fuelType);
    if (referencePrice == null) return [];

    final directDistance = geo.Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      place.lat,
      place.lng,
    );
    final stations = nearbyStationDetails
        .where((details) {
          final distance = details.distanceMeters;
          return distance != null &&
              distance <= 12000 &&
              _fuelPrice(details.price, fuelType) != null;
        })
        .map((details) {
          final stationPrice = _fuelPrice(details.price, fuelType)!;
          final currentToStation = details.distanceMeters ?? 0;
          final stationToDestination = geo.Geolocator.distanceBetween(
            details.lat,
            details.lng,
            place.lat,
            place.lng,
          );
          final detourDistance = currentToStation + stationToDestination;
          final extraDistance = math
              .max(detourDistance - directDistance, 0)
              .toDouble();
          final estimatedFuelSavings = (referencePrice - stationPrice) * 20;
          final estimatedExtraTripCost =
              (extraDistance / 1000 / 10) * referencePrice;

          return RefuelOption(
            station: details,
            fuelType: fuelType,
            stationPrice: stationPrice,
            referencePrice: referencePrice,
            extraDistanceMeters: extraDistance,
            estimatedNetSavings: estimatedFuelSavings - estimatedExtraTripCost,
          );
        })
        .toList();

    stations.sort((a, b) {
      final scoreCompare = b.estimatedNetSavings.compareTo(
        a.estimatedNetSavings,
      );
      if (scoreCompare != 0) return scoreCompare;

      final aDistance = a.station.distanceMeters ?? double.infinity;
      final bDistance = b.station.distanceMeters ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });

    return stations;
  }

  void showRefuelOptionsSheet(
    List<RefuelOption> options,
    DestinationPlace destination,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.68,
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Refuel Options',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Within 12 km • Sorted by estimated value',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: math.min(
                  MediaQuery.of(context).size.height * 0.50,
                  options.length * 96.0,
                ),
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return _refuelOptionTile(
                      option: option,
                      onTap: () {
                        Navigator.of(context).pop();
                        showSelectedRefuelAnalysis(option.station, destination);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _refuelOptionTile({
    required RefuelOption option,
    required VoidCallback onTap,
  }) {
    final color = _refuelRecommendationColor(option.estimatedNetSavings);
    final label = _refuelRecommendationLabel(option.estimatedNetSavings);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(Icons.local_gas_station, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stationTitle(option.station),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _formatCompactDistance(
                        option.station.distanceMeters ?? 0,
                      ),
                      _fuelLabelForStation(option.station, option.fuelType),
                      'PHP ${option.stationPrice.toStringAsFixed(2)}/L',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              option.estimatedNetSavings >= 0
                  ? '+PHP ${option.estimatedNetSavings.toStringAsFixed(0)}'
                  : '-PHP ${option.estimatedNetSavings.abs().toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showSelectedRefuelAnalysis(
    StationMarkerDetails station,
    DestinationPlace place,
  ) async {
    final origin = currentLocation;
    if (origin == null || mapboxMap == null) return;

    final fuelType = await _preferredFuelType();
    final directRoute = await fetchDrivingRoute(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destinationLat: place.lat,
      destinationLng: place.lng,
    );
    if (!mounted || directRoute == null) return;
    final directDistance = _routeDistanceMeters(directRoute);
    if (directDistance == null) {
      _showSimpleMapMessage('Not enough price or route data to compare yet.');
      return;
    }

    final detourRoute = await fetchDrivingRouteWithCoordinates([
      Position(origin.longitude, origin.latitude),
      Position(station.lng, station.lat),
      Position(place.lng, place.lat),
    ]);
    if (!mounted || detourRoute == null) {
      _showSimpleMapMessage('No usable detour route found yet.');
      return;
    }

    final detourDistance = _routeDistanceMeters(detourRoute);
    final stationPrice = _fuelPrice(station.price, fuelType);
    final referencePrice = _referenceFuelPrice(fuelType, exclude: station);
    if (detourDistance == null ||
        stationPrice == null ||
        referencePrice == null) {
      _showSimpleMapMessage('Not enough price or route data to compare yet.');
      return;
    }

    final analysis = DetourAnalysis(
      station: station,
      fuelType: fuelType,
      stationPrice: stationPrice,
      referencePrice: referencePrice,
      directDistanceMeters: directDistance,
      detourDistanceMeters: detourDistance,
    );

    await drawRoute(detourRoute);
    await focusRouteFromCurrentLocation(station);
    if (mounted) {
      setState(() {
        activeRouteDestination = StationMarkerDetails(
          name: place.name,
          brand: 'Destination',
          lat: place.lat,
          lng: place.lng,
          distanceMeters: null,
        );
        isRouteActive = true;
      });
    }

    showDetourAnalysisSheet(analysis, place);
  }

  Color _refuelRecommendationColor(double estimatedNetSavings) {
    if (estimatedNetSavings >= 20) return const Color(0xFF1E8E3E);
    if (estimatedNetSavings >= -20) return const Color(0xFFFFA000);
    return const Color(0xFFD93025);
  }

  String _refuelRecommendationLabel(double estimatedNetSavings) {
    if (estimatedNetSavings >= 20) return 'Recommended';
    if (estimatedNetSavings >= -20) return 'Average';
    return 'Not recommended';
  }

  void showDetourAnalysisSheet(
    DetourAnalysis analysis,
    DestinationPlace destination,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return _DetourAnalysisSheet(
          analysis: analysis,
          destination: destination,
          stationTitle: _stationTitle(analysis.station),
          fuelLabel: _fuelLabelForStation(analysis.station, analysis.fuelType),
        );
      },
    );
  }

  Future<String> _preferredFuelType() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'gasoline';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final vehicle = doc.data()?['vehicle'];
      if (vehicle is Map<String, dynamic>) {
        final fuel = _profileValue(
          vehicle['preferredFuelType'],
          fallback: 'Gasoline',
        ).toLowerCase();
        if (fuel.contains('diesel')) return 'diesel';
        if (fuel.contains('premium')) return 'premium';
      }
    } catch (error) {
      debugPrint('Preferred fuel load failed: $error');
    }

    return 'gasoline';
  }

  double? _referenceFuelPrice(
    String fuelType, {
    StationMarkerDetails? exclude,
  }) {
    final prices = nearbyStationDetails
        .where(
          (details) =>
              exclude == null ||
              _stationFavoriteKey(details) != _stationFavoriteKey(exclude),
        )
        .map((details) => _fuelPrice(details.price, fuelType))
        .whereType<double>()
        .toList();
    if (prices.isEmpty) return null;

    return prices.reduce((a, b) => a + b) / prices.length;
  }

  double? _routeDistanceMeters(Map<String, dynamic> routeGeoJson) {
    final properties = routeGeoJson['properties'];
    if (properties is! Map<String, dynamic>) return null;
    final distance = properties['distance'];
    if (distance is num) return distance.toDouble();
    return null;
  }

  double? _routePropertyMetersOrSeconds(
    Map<String, dynamic> routeGeoJson,
    String key,
  ) {
    final properties = routeGeoJson['properties'];
    if (properties is! Map<String, dynamic>) return null;
    final value = properties[key];
    if (value is num) return value.toDouble();
    return null;
  }

  Future<void> showTrafficRouteSummary(
    Map<String, dynamic> routeGeoJson, {
    required String destinationName,
  }) async {
    if (!mounted) return;

    final distanceMeters = _routeDistanceMeters(routeGeoJson);
    final durationSeconds = _routePropertyMetersOrSeconds(
      routeGeoJson,
      'duration',
    );
    if (distanceMeters == null || durationSeconds == null) return;

    final fuelType = await _preferredFuelType();
    if (!mounted) return;

    final trafficDelaySeconds =
        _routePropertyMetersOrSeconds(routeGeoJson, 'trafficDelay') ?? 0;
    final heavyDistance =
        _routePropertyMetersOrSeconds(routeGeoJson, 'heavyDistance') ?? 0;
    final severeDistance =
        _routePropertyMetersOrSeconds(routeGeoJson, 'severeDistance') ?? 0;
    final fuelProfile = await _fuelConsumptionProfile();
    if (!mounted) return;

    final estimatedFuelLiters = _estimateRouteFuelLiters(
      distanceMeters: distanceMeters,
      trafficDelaySeconds: trafficDelaySeconds,
      kmPerLiter: fuelProfile.kmPerLiter,
      idleLitersPerHour: fuelProfile.idleLitersPerHour,
    );
    final referencePrice = _referenceFuelPrice(fuelType);
    final estimatedCost = referencePrice == null
        ? null
        : estimatedFuelLiters * referencePrice;

    setState(() {
      activeRouteDashboard = _RouteDashboardData(
        destinationName: destinationName,
        eta: _formatDuration(durationSeconds),
        distance: _formatCompactDistance(distanceMeters),
        trafficDelay: trafficDelaySeconds <= 30
            ? 'Light'
            : '+${_formatDuration(trafficDelaySeconds)}',
        heavyTraffic: _formatHeavyTrafficDistance(
          heavyDistance,
          severeDistance,
        ),
        fuelEstimate: estimatedCost == null
            ? '${estimatedFuelLiters.toStringAsFixed(2)} L'
            : '${estimatedFuelLiters.toStringAsFixed(2)} L / PHP ${estimatedCost.toStringAsFixed(0)}',
      );
    });
  }

  double _estimateRouteFuelLiters({
    required double distanceMeters,
    required double trafficDelaySeconds,
    required double kmPerLiter,
    required double idleLitersPerHour,
  }) {
    final distanceFuel = (distanceMeters / 1000) / kmPerLiter;
    final trafficIdleFuel = (trafficDelaySeconds / 3600) * idleLitersPerHour;
    return distanceFuel + trafficIdleFuel;
  }

  Future<_FuelConsumptionProfile> _fuelConsumptionProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const _FuelConsumptionProfile();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final vehicle = doc.data()?['vehicle'];
      if (vehicle is Map<String, dynamic>) {
        final kmPerLiter = _doubleField(vehicle, 'kmPerLiter');
        final idleLitersPerHour = _doubleField(vehicle, 'idleLitersPerHour');
        return _FuelConsumptionProfile(
          kmPerLiter: kmPerLiter != null && kmPerLiter > 0 ? kmPerLiter : 10,
          idleLitersPerHour: idleLitersPerHour != null && idleLitersPerHour >= 0
              ? idleLitersPerHour
              : 0.8,
        );
      }
    } catch (error) {
      debugPrint('Fuel consumption profile load failed: $error');
    }

    return const _FuelConsumptionProfile();
  }

  String _formatHeavyTrafficDistance(double heavyMeters, double severeMeters) {
    final combined = heavyMeters + severeMeters;
    if (combined < 50) return 'None reported';
    if (severeMeters >= 50) {
      return '${_formatCompactDistance(combined)} incl. severe';
    }
    return _formatCompactDistance(combined);
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours hr';
    return '$hours hr $remainingMinutes min';
  }

  void _showSimpleMapMessage(String message) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Text(
            message,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  Future<void> focusRouteFromCurrentLocation(
    StationMarkerDetails destination,
  ) async {
    final origin = currentLocation;
    final map = mapboxMap;
    if (origin == null || map == null) return;

    await map.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(origin.longitude, origin.latitude)),
        zoom: 16.5,
        bearing: _bearingToDestination(
          origin.latitude,
          origin.longitude,
          destination.lat,
          destination.lng,
        ),
        pitch: 50,
      ),
    );
  }

  Future<void> drawRoute(Map<String, dynamic> routeGeoJson) async {
    final map = mapboxMap;
    if (map == null) return;

    final style = map.style;
    if (await style.styleLayerExists(routeLayerId)) {
      await style.removeStyleLayer(routeLayerId);
    }
    if (await style.styleSourceExists(routeSourceId)) {
      await style.removeStyleSource(routeSourceId);
    }

    await style.addSource(
      GeoJsonSource(id: routeSourceId, data: jsonEncode(routeGeoJson)),
    );
    await style.addLayer(
      LineLayer(
        id: routeLayerId,
        sourceId: routeSourceId,
        lineColorExpression: [
          'match',
          ['get', 'congestion'],
          'low',
          '#2962FF',
          'moderate',
          '#FBC02D',
          'heavy',
          '#F57C00',
          'severe',
          '#D32F2F',
          '#2962FF',
        ],
        lineWidth: 5,
        lineOpacity: 0.9,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
      ),
    );
  }

  Future<void> enable3DMapView() async {
    final map = mapboxMap;
    if (map == null) return;

    final style = map.style;

    try {
      if (!await style.styleSourceExists(terrainSourceId)) {
        await style.addStyleSource(
          terrainSourceId,
          jsonEncode({
            'type': 'raster-dem',
            'url': 'mapbox://mapbox.mapbox-terrain-dem-v1',
            'tileSize': 512,
            'maxzoom': 14,
          }),
        );
      }

      await style.setStyleTerrain(
        jsonEncode({'source': terrainSourceId, 'exaggeration': 1.15}),
      );

      if (await style.styleLayerExists(buildingsLayerId)) return;

      await style.addStyleLayer(
        jsonEncode({
          'id': buildingsLayerId,
          'type': 'fill-extrusion',
          'source': 'composite',
          'source-layer': 'building',
          'minzoom': 15,
          'paint': {
            'fill-extrusion-color': '#9CA3AF',
            'fill-extrusion-height': [
              'coalesce',
              [
                'to-number',
                ['get', 'height'],
              ],
              18,
            ],
            'fill-extrusion-base': [
              'coalesce',
              [
                'to-number',
                ['get', 'min_height'],
              ],
              0,
            ],
            'fill-extrusion-opacity': 0.75,
            'fill-extrusion-vertical-gradient': true,
          },
        }),
        null,
      );
    } catch (error) {
      debugPrint('3D map setup failed: $error');
    }
  }

  Future<void> cancelRoute() async {
    final map = mapboxMap;
    if (map != null) {
      final style = map.style;
      if (await style.styleLayerExists(routeLayerId)) {
        await style.removeStyleLayer(routeLayerId);
      }
      if (await style.styleSourceExists(routeSourceId)) {
        await style.removeStyleSource(routeSourceId);
      }
    }

    if (mounted) {
      setState(() {
        activeRouteDestination = null;
        activeRouteDashboard = null;
        isRouteActive = false;
      });
    }

    await moveToCurrentLocation();
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  String _formatCompactDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _freshnessLabel(DateTime? updatedAt) {
    if (updatedAt == null) return 'No approved price yet';
    final age = DateTime.now().difference(updatedAt);
    if (age.inDays <= 0) return 'Updated today';
    if (age.inDays == 1) return '1 day old';
    if (age.inDays <= 6) return '${age.inDays} days old';
    return 'Outdated';
  }

  Color _freshnessColor(DateTime updatedAt) {
    final age = DateTime.now().difference(updatedAt);
    if (age.inDays <= 1) return const Color(0xFF1E8E3E);
    if (age.inDays <= 6) return const Color(0xFFFFA000);
    return const Color(0xFFE94B5A);
  }

  Widget _priceFreshnessBadge(DateTime updatedAt) {
    final color = _freshnessColor(updatedAt);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          _freshnessLabel(updatedAt),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _stationTitle(StationMarkerDetails details) {
    if (details.brand.isEmpty || details.brand == details.name) {
      return details.name;
    }

    return '${details.brand} - ${details.name}';
  }

  String _stationFavoriteKey(StationMarkerDetails details) {
    final priceId = details.price?.id;
    if (priceId != null && priceId.isNotEmpty) return priceId;

    return '${details.name}:${details.lat.toStringAsFixed(5)},${details.lng.toStringAsFixed(5)}';
  }

  String? _primaryStationPrice(StationMarkerDetails details) {
    final price = details.price;
    if (price == null) return null;
    if (price.gasoline != null) {
      final label = _fuelLabelForStation(details, 'gasoline');
      return '$label PHP ${price.gasoline!.toStringAsFixed(2)}/L';
    }
    if (price.diesel != null) {
      final label = _fuelLabelForStation(details, 'diesel');
      return '$label PHP ${price.diesel!.toStringAsFixed(2)}/L';
    }
    if (price.premium != null) {
      final label = _fuelLabelForStation(details, 'premium');
      return '$label PHP ${price.premium!.toStringAsFixed(2)}/L';
    }
    return null;
  }

  double? _fuelPrice(StationPrice? price, String fuelType) {
    if (price == null) return null;

    return switch (fuelType) {
      'diesel' => price.diesel,
      'premium' => price.premium,
      _ => price.gasoline,
    };
  }

  String _fuelLabel(String fuelType) {
    return switch (fuelType) {
      'diesel' => 'Diesel',
      'premium' => 'Premium Gasoline',
      _ => 'Gasoline',
    };
  }

  List<FuelDisplayItem> _fuelDisplayItems(StationMarkerDetails details) {
    final price = details.price;
    if (price == null) return const [];

    return [
      FuelDisplayItem(
        fuelType: 'gasoline',
        label: _fuelLabelForStation(details, 'gasoline'),
        shortLabel: _shortFuelLabelForStation(details, 'gasoline'),
        price: price.gasoline,
      ),
      FuelDisplayItem(
        fuelType: 'diesel',
        label: _fuelLabelForStation(details, 'diesel'),
        shortLabel: _shortFuelLabelForStation(details, 'diesel'),
        price: price.diesel,
      ),
      FuelDisplayItem(
        fuelType: 'premium',
        label: _fuelLabelForStation(details, 'premium'),
        shortLabel: _shortFuelLabelForStation(details, 'premium'),
        price: price.premium,
      ),
    ];
  }

  String _fuelLabelForStation(StationMarkerDetails details, String fuelType) {
    final brand = _normalizedBrandForLabels(details);

    if (brand.contains('shell')) {
      return switch (fuelType) {
        'diesel' => 'Shell FuelSave Diesel',
        'premium' => 'Shell V-Power Gasoline',
        _ => 'Shell FuelSave Gasoline',
      };
    }

    if (brand.contains('petron')) {
      return switch (fuelType) {
        'diesel' => 'Petron Diesel Max',
        'premium' => 'Petron XCS',
        _ => 'Petron Xtra Advance',
      };
    }

    if (brand.contains('unioil')) {
      return switch (fuelType) {
        'diesel' => 'Unioil Diesel',
        'premium' => 'Unioil Gasoline 95',
        _ => 'Unioil Gasoline',
      };
    }

    if (brand.contains('caltex')) {
      return switch (fuelType) {
        'diesel' => 'Caltex Diesel',
        'premium' => 'Caltex Platinum',
        _ => 'Caltex Silver',
      };
    }

    if (brand.contains('seaoil') || brand.contains('sea oil')) {
      return switch (fuelType) {
        'diesel' => 'SEAOIL Exceed Diesel',
        'premium' => 'SEAOIL Extreme 95',
        _ => 'SEAOIL Extreme U',
      };
    }

    if (brand.contains('phoenix')) {
      return switch (fuelType) {
        'diesel' => 'Phoenix Diesel',
        'premium' => 'Phoenix Premium 98',
        _ => 'Phoenix Gasoline 95',
      };
    }

    if (brand.contains('total')) {
      return switch (fuelType) {
        'diesel' => 'Total Diesel',
        'premium' => 'Total Excellium',
        _ => 'Total Unleaded',
      };
    }

    return _fuelLabel(fuelType);
  }

  String _shortFuelLabelForStation(
    StationMarkerDetails details,
    String fuelType,
  ) {
    final fullLabel = _fuelLabelForStation(details, fuelType);
    final brand = _brandNameForShortLabels(details);
    if (brand.isEmpty) return fullLabel;

    return fullLabel
        .replaceFirst(RegExp('^$brand\\s+', caseSensitive: false), '')
        .trim();
  }

  String _normalizedBrandForLabels(StationMarkerDetails details) {
    return '${details.brand} ${details.name}'.toLowerCase();
  }

  String _brandNameForShortLabels(StationMarkerDetails details) {
    final brand = _normalizedBrandForLabels(details);
    if (brand.contains('shell')) return 'Shell';
    if (brand.contains('petron')) return 'Petron';
    if (brand.contains('unioil')) return 'Unioil';
    if (brand.contains('caltex')) return 'Caltex';
    if (brand.contains('seaoil') || brand.contains('sea oil')) return 'Seaoil';
    if (brand.contains('phoenix')) return 'Phoenix';
    if (brand.contains('total')) return 'Total';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.desktop_windows_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Run PumpScout on Windows desktop',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'The map view is built for the desktop/mobile app. Use flutter run -d windows instead of Chrome.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MapWidget(
          key: ValueKey("mapWidget-$mapStyleUri"),
          styleUri: mapStyleUri,
          cameraOptions: CameraOptions(
            center: Point(coordinates: Position(125.6128, 7.0731)),
            zoom: 16,
            pitch: 55,
            bearing: -20,
          ),
          onMapCreated: (mapbox) async {
            mapboxMap = mapbox;

            await mapbox.location.updateSettings(
              LocationComponentSettings(enabled: true, pulsingEnabled: true),
            );
            startLocationUpdates();
          },
          onStyleLoadedListener: (_) async {
            stationAnnotationManager = null;
            stationLabelManager = null;
            activeRouteDestination = null;
            activeRouteDashboard = null;
            isRouteActive = false;
            if (enableDetailed3D) {
              await enable3DMapView();
            }
            moveToCurrentLocation();
          },
        ),
        if (activeRouteDashboard != null)
          Positioned(
            top: 12,
            right: 12,
            left: 66,
            child: _RouteDashboardCard(data: activeRouteDashboard!),
          ),
        Positioned(
          top: 46,
          left: 12,
          child: Material(
            color: Colors.white,
            elevation: 3,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Tooltip(
              message: 'Recenter',
              child: InkWell(
                onTap: moveToCurrentLocation,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Image.asset(
                      'assets/images/center.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isRouteActive)
          Positioned(
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: FilledButton.icon(
                onPressed: cancelRoute,
                icon: const Icon(Icons.close),
                label: const Text('Cancel route'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FuelConsumptionProfile {
  const _FuelConsumptionProfile({
    this.kmPerLiter = 10,
    this.idleLitersPerHour = 0.8,
  });

  final double kmPerLiter;
  final double idleLitersPerHour;
}

class _RouteDashboardData {
  const _RouteDashboardData({
    required this.destinationName,
    required this.eta,
    required this.distance,
    required this.trafficDelay,
    required this.heavyTraffic,
    required this.fuelEstimate,
  });

  final String destinationName;
  final String eta;
  final String distance;
  final String trafficDelay;
  final String heavyTraffic;
  final String fuelEstimate;
}

class _RouteDashboardCard extends StatelessWidget {
  const _RouteDashboardCard({required this.data});

  final _RouteDashboardData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.destinationName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _RouteMetric(icon: Icons.schedule, value: data.eta),
                _RouteMetric(icon: Icons.route, value: data.distance),
                _RouteMetric(icon: Icons.traffic, value: data.trafficDelay),
                _RouteMetric(
                  icon: Icons.local_gas_station,
                  value: data.fuelEstimate,
                ),
              ],
            ),
            if (data.heavyTraffic != 'None reported') ...[
              const SizedBox(height: 6),
              Text(
                'Heavy traffic: ${data.heavyTraffic}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF1E8E3E)),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DetourAnalysisSheet extends StatefulWidget {
  const _DetourAnalysisSheet({
    required this.analysis,
    required this.destination,
    required this.stationTitle,
    required this.fuelLabel,
  });

  final DetourAnalysis analysis;
  final DestinationPlace destination;
  final String stationTitle;
  final String fuelLabel;

  @override
  State<_DetourAnalysisSheet> createState() => _DetourAnalysisSheetState();
}

class _DetourAnalysisSheetState extends State<_DetourAnalysisSheet> {
  late final TextEditingController kmPerLiterController;
  late final TextEditingController litersToBuyController;

  @override
  void initState() {
    super.initState();
    kmPerLiterController = TextEditingController(text: '10');
    litersToBuyController = TextEditingController(text: '20');
  }

  @override
  void dispose() {
    kmPerLiterController.dispose();
    litersToBuyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    final kmPerLiter = _parsePrice(kmPerLiterController.text);
    final litersToBuy = _parsePrice(litersToBuyController.text);
    final extraKm = math.max(analysis.extraDistanceMeters, 0) / 1000;
    final extraFuelCost = kmPerLiter == null || kmPerLiter <= 0
        ? null
        : (extraKm / kmPerLiter) * analysis.referencePrice;
    final fuelSavings = litersToBuy == null
        ? null
        : analysis.priceDifference * litersToBuy;
    final netSavings = fuelSavings == null || extraFuelCost == null
        ? null
        : fuelSavings - extraFuelCost;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cheapest Gas Detour',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Destination: ${widget.destination.name}'),
            const SizedBox(height: 14),
            _infoRow(context, 'Station', widget.stationTitle),
            _infoRow(context, 'Fuel', widget.fuelLabel),
            _infoRow(
              context,
              'Cheapest',
              'PHP ${analysis.stationPrice.toStringAsFixed(2)} / L',
            ),
            _infoRow(
              context,
              'Reference',
              'PHP ${analysis.referencePrice.toStringAsFixed(2)} / L',
            ),
            _infoRow(
              context,
              'Direct',
              '${(analysis.directDistanceMeters / 1000).toStringAsFixed(1)} km',
            ),
            _infoRow(
              context,
              'Via station',
              '${(analysis.detourDistanceMeters / 1000).toStringAsFixed(1)} km',
            ),
            _infoRow(context, 'Extra', '${extraKm.toStringAsFixed(1)} km'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    controller: kmPerLiterController,
                    label: 'Vehicle km/L',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    controller: litersToBuyController,
                    label: 'Liters to buy',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    netSavings == null
                        ? 'Enter valid values to estimate.'
                        : netSavings >= 0
                        ? 'Worth it'
                        : 'Not worth it',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: netSavings == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : netSavings >= 0
                          ? const Color(0xFF1E8E3E)
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    netSavings == null
                        ? 'The app compares the detour fuel cost against the fuel price savings.'
                        : 'Estimated net ${netSavings >= 0 ? 'savings' : 'loss'}: PHP ${netSavings.abs().toStringAsFixed(2)}',
                  ),
                  if (fuelSavings != null && extraFuelCost != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Fuel savings PHP ${fuelSavings.toStringAsFixed(2)} - extra trip cost PHP ${extraFuelCost.toStringAsFixed(2)}',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.map),
                label: const Text('Keep detour route on map'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
