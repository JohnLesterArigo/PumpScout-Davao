part of '../main.dart';

class StationPrice {
  const StationPrice({
    required this.id,
    required this.name,
    required this.brand,
    required this.lat,
    required this.lng,
    this.gasoline,
    this.diesel,
    this.premium,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String brand;
  final double lat;
  final double lng;
  final double? gasoline;
  final double? diesel;
  final double? premium;
  final DateTime? updatedAt;

  factory StationPrice.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return StationPrice(
      id: doc.id,
      name: _stringField(data, 'name', fallback: 'Fuel station'),
      brand: _stringField(data, 'brand', fallback: _stringField(data, 'Brand')),
      lat: _doubleField(data, 'lat') ?? 0,
      lng: _doubleField(data, 'lng') ?? 0,
      gasoline: _stationFuelPrice(data, 'gasoline'),
      diesel: _stationFuelPrice(data, 'diesel'),
      premium: _stationFuelPrice(data, 'premium'),
      updatedAt: _dateTimeField(data, 'updatedAt'),
    );
  }
}

class PriceReport {
  const PriceReport({
    required this.stationId,
    required this.createdAt,
    this.gasoline,
    this.diesel,
    this.premium,
    this.photoUrl,
  });

  final String stationId;
  final DateTime createdAt;
  final double? gasoline;
  final double? diesel;
  final double? premium;
  final String? photoUrl;

  factory PriceReport.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return PriceReport(
      stationId: _stringField(data, 'stationId'),
      createdAt: _dateTimeField(data, 'createdAt') ?? DateTime(1970),
      gasoline: _doubleField(data, 'gasoline'),
      diesel: _doubleField(data, 'diesel'),
      premium: _doubleField(data, 'premium'),
      photoUrl: _stringField(data, 'photoUrl'),
    );
  }
}

class StationMarkerDetails {
  const StationMarkerDetails({
    required this.name,
    required this.brand,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    this.price,
  });

  final String name;
  final String brand;
  final double lat;
  final double lng;
  final double? distanceMeters;
  final StationPrice? price;
}

class FuelDisplayItem {
  const FuelDisplayItem({
    required this.fuelType,
    required this.label,
    required this.shortLabel,
    required this.price,
  });

  final String fuelType;
  final String label;
  final String shortLabel;
  final double? price;
}

class UserProfileSummary {
  const UserProfileSummary({
    required this.displayName,
    required this.email,
    required this.vehicle,
    required this.vehicles,
    required this.activeVehicleIndex,
    required this.reportCount,
    required this.role,
    this.lastReportAt,
  });

  final String displayName;
  final String email;
  final Map<String, dynamic> vehicle;
  final List<Map<String, dynamic>> vehicles;
  final int activeVehicleIndex;
  final int reportCount;
  final String role;
  final DateTime? lastReportAt;

  bool get isAdmin => role.toLowerCase() == 'admin';
}

class ContributorSummary {
  const ContributorSummary({
    required this.userId,
    required this.name,
    required this.reportCount,
  });

  final String userId;
  final String name;
  final int reportCount;
}

class AdminContribution {
  const AdminContribution({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.brand,
    required this.lat,
    required this.lng,
    required this.status,
    required this.createdAt,
    this.gasoline,
    this.diesel,
    this.premium,
    this.photoUrl,
    this.userId,
    this.userDisplayName,
    this.userEmail,
    this.rejectionReason,
  });

  final String id;
  final String stationId;
  final String stationName;
  final String brand;
  final double lat;
  final double lng;
  final String status;
  final DateTime createdAt;
  final double? gasoline;
  final double? diesel;
  final double? premium;
  final String? photoUrl;
  final String? userId;
  final String? userDisplayName;
  final String? userEmail;
  final String? rejectionReason;

  factory AdminContribution.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AdminContribution(
      id: doc.id,
      stationId: _stringField(data, 'stationId'),
      stationName: _stringField(data, 'stationName', fallback: 'Fuel station'),
      brand: _stringField(data, 'brand'),
      lat: _doubleField(data, 'lat') ?? 0,
      lng: _doubleField(data, 'lng') ?? 0,
      status: _stringField(data, 'status', fallback: 'pending'),
      createdAt: _dateTimeField(data, 'createdAt') ?? DateTime(1970),
      gasoline: _doubleField(data, 'gasoline'),
      diesel: _doubleField(data, 'diesel'),
      premium: _doubleField(data, 'premium'),
      photoUrl: _stringField(data, 'photoUrl'),
      userId: _stringField(data, 'userId'),
      userDisplayName: _stringField(data, 'userDisplayName'),
      userEmail: _stringField(data, 'userEmail'),
      rejectionReason: _stringField(data, 'rejectionReason'),
    );
  }
}

class UserNotification {
  const UserNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.reportId,
    this.stationName,
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? reportId;
  final String? stationName;

  factory UserNotification.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return UserNotification(
      id: doc.id,
      title: _stringField(data, 'title', fallback: 'PumpScout update'),
      message: _stringField(data, 'message'),
      type: _stringField(data, 'type', fallback: 'info'),
      isRead: data['isRead'] == true,
      createdAt: _dateTimeField(data, 'createdAt') ?? DateTime(1970),
      reportId: _stringField(data, 'reportId'),
      stationName: _stringField(data, 'stationName'),
    );
  }
}

class UserContribution {
  const UserContribution({
    required this.id,
    required this.stationName,
    required this.status,
    required this.createdAt,
    this.gasoline,
    this.diesel,
    this.premium,
    this.rejectionReason,
  });

  final String id;
  final String stationName;
  final String status;
  final DateTime createdAt;
  final double? gasoline;
  final double? diesel;
  final double? premium;
  final String? rejectionReason;

  factory UserContribution.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return UserContribution(
      id: doc.id,
      stationName: _stringField(data, 'stationName', fallback: 'Fuel station'),
      status: _stringField(data, 'status', fallback: 'pending'),
      createdAt: _dateTimeField(data, 'createdAt') ?? DateTime(1970),
      gasoline: _doubleField(data, 'gasoline'),
      diesel: _doubleField(data, 'diesel'),
      premium: _doubleField(data, 'premium'),
      rejectionReason: _stringField(data, 'rejectionReason'),
    );
  }
}

class DestinationPlace {
  const DestinationPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String name;
  final String address;
  final double lat;
  final double lng;
}

class DetourAnalysis {
  const DetourAnalysis({
    required this.station,
    required this.fuelType,
    required this.stationPrice,
    required this.referencePrice,
    required this.directDistanceMeters,
    required this.detourDistanceMeters,
  });

  final StationMarkerDetails station;
  final String fuelType;
  final double stationPrice;
  final double referencePrice;
  final double directDistanceMeters;
  final double detourDistanceMeters;

  double get extraDistanceMeters => detourDistanceMeters - directDistanceMeters;
  double get priceDifference => referencePrice - stationPrice;
}

class RefuelOption {
  const RefuelOption({
    required this.station,
    required this.fuelType,
    required this.stationPrice,
    required this.referencePrice,
    required this.extraDistanceMeters,
    required this.estimatedNetSavings,
  });

  final StationMarkerDetails station;
  final String fuelType;
  final double stationPrice;
  final double referencePrice;
  final double extraDistanceMeters;
  final double estimatedNetSavings;
}
