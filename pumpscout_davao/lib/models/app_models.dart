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
    this.fuelProducts = const <String, double>{},
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
  final Map<String, double> fuelProducts;
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
      fuelProducts: _doubleMapField(data, 'fuelProducts'),
      updatedAt: _dateTimeField(data, 'updatedAt'),
    );
  }
}

class StationCrowdStatus {
  const StationCrowdStatus({
    required this.stationId,
    required this.stationName,
    required this.currentCount,
    required this.capacity,
    required this.status,
    this.updatedAt,
  });

  final String stationId;
  final String stationName;
  final int currentCount;
  final int capacity;
  final String status;
  final DateTime? updatedAt;

  double get occupancyRatio {
    if (capacity <= 0) return 0;
    return (currentCount / capacity).clamp(0, 1);
  }

  String get computedStatus {
    if (occupancyRatio >= 0.8) return 'crowded';
    if (occupancyRatio >= 0.5) return 'moderate';
    if (status.trim().isNotEmpty) return status.trim();
    return 'not_crowded';
  }

  factory StationCrowdStatus.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return StationCrowdStatus(
      stationId: _stringField(data, 'stationId', fallback: doc.id),
      stationName: _stringField(data, 'stationName', fallback: 'Fuel station'),
      currentCount: _crowdIntField(data, 'currentCount'),
      capacity: _crowdIntField(data, 'capacity'),
      status: _stringField(data, 'status'),
      updatedAt: _dateTimeField(data, 'updatedAt'),
    );
  }

  factory StationCrowdStatus.fromRealtimeDatabase({
    required String stationId,
    required Map<String, dynamic> data,
  }) {
    return StationCrowdStatus(
      stationId: _stringField(data, 'stationId', fallback: stationId),
      stationName: _stringField(data, 'stationName', fallback: 'Fuel station'),
      currentCount: _crowdIntField(data, 'currentCount'),
      capacity: _crowdIntField(data, 'capacity'),
      status: _stringField(data, 'status'),
      updatedAt: _realtimeDateTimeField(data, 'updatedAt'),
    );
  }
}

int _crowdIntField(Map<String, dynamic> data, String key) {
  final direct = _doubleField(data, key);
  if (direct != null) return direct.round();

  final normalizedKey = key.toLowerCase();
  for (final entry in data.entries) {
    if (entry.key.trim().toLowerCase() != normalizedKey) continue;
    final value = entry.value;
    if (value is num) return value.round();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', ''))?.round() ?? 0;
    }
  }
  return 0;
}

DateTime? _realtimeDateTimeField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value.trim());
  if (value is num) {
    final raw = value.toInt();
    if (raw <= 0) return null;
    final milliseconds = raw < 10000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  return _dateTimeField(data, key);
}

class PriceReport {
  const PriceReport({
    required this.stationId,
    required this.createdAt,
    this.gasoline,
    this.diesel,
    this.premium,
    this.fuelProducts = const <String, double>{},
    this.photoUrl,
  });

  final String stationId;
  final DateTime createdAt;
  final double? gasoline;
  final double? diesel;
  final double? premium;
  final Map<String, double> fuelProducts;
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
      fuelProducts: _doubleMapField(data, 'fuelProducts'),
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
    required this.trustBadge,
  });

  final String displayName;
  final String email;
  final Map<String, dynamic> vehicle;
  final List<Map<String, dynamic>> vehicles;
  final int activeVehicleIndex;
  final int reportCount;
  final String role;
  final DateTime? lastReportAt;
  final ContributorTrustBadge trustBadge;

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
    this.fuelProducts = const <String, double>{},
    this.photoUrl,
    this.userId,
    this.userDisplayName,
    this.userEmail,
    this.rejectionReason,
    this.aiClassification,
    this.aiConfidence,
    this.aiReasons = const <String>[],
    this.needsAdminAttention = false,
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
  final Map<String, double> fuelProducts;
  final String? photoUrl;
  final String? userId;
  final String? userDisplayName;
  final String? userEmail;
  final String? rejectionReason;
  final String? aiClassification;
  final double? aiConfidence;
  final List<String> aiReasons;
  final bool needsAdminAttention;

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
      fuelProducts: _doubleMapField(data, 'fuelProducts'),
      photoUrl: _stringField(data, 'photoUrl'),
      userId: _stringField(data, 'userId'),
      userDisplayName: _stringField(data, 'userDisplayName'),
      userEmail: _stringField(data, 'userEmail'),
      rejectionReason: _stringField(data, 'rejectionReason'),
      aiClassification: _stringField(
        data,
        'aiClassification',
        fallback: 'needs_review',
      ),
      aiConfidence: _doubleField(data, 'aiConfidence'),
      aiReasons: _stringListField(data, 'aiReasons'),
      needsAdminAttention: data['needsAdminAttention'] == true,
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

class CommunityFeedbackComment {
  const CommunityFeedbackComment({
    required this.id,
    required this.authorName,
    required this.comment,
    required this.reaction,
    this.replies = const <CommunityFeedbackReply>[],
    this.createdAt,
  });

  final String id;
  final String authorName;
  final String comment;
  final String reaction;
  final List<CommunityFeedbackReply> replies;
  final DateTime? createdAt;

  bool get hasVisibleComment => comment.trim().isNotEmpty;
}

class CommunityFeedbackReply {
  const CommunityFeedbackReply({
    required this.authorName,
    required this.comment,
    this.createdAt,
  });

  final String authorName;
  final String comment;
  final DateTime? createdAt;
}

class CommunityContribution {
  const CommunityContribution({
    required this.id,
    required this.stationName,
    required this.brand,
    required this.createdAt,
    required this.trustBadge,
    required this.lat,
    required this.lng,
    this.gasoline,
    this.diesel,
    this.premium,
    this.fuelProducts = const <String, double>{},
    this.photoUrl,
    this.userId,
    this.userDisplayName,
    this.userEmail,
    this.likeCount = 0,
    this.disagreeCount = 0,
    this.feedbackCount = 0,
    this.myReaction,
    List<CommunityFeedbackComment>? publicComments,
  }) : _publicComments = publicComments;

  final String id;
  final String stationName;
  final String brand;
  final DateTime createdAt;
  final double lat;
  final double lng;
  final double? gasoline;
  final double? diesel;
  final double? premium;
  final Map<String, double> fuelProducts;
  final String? photoUrl;
  final String? userId;
  final String? userDisplayName;
  final String? userEmail;
  final int likeCount;
  final int disagreeCount;
  final int feedbackCount;
  final String? myReaction;
  final List<CommunityFeedbackComment>? _publicComments;
  final ContributorTrustBadge trustBadge;

  List<CommunityFeedbackComment> get publicComments =>
      _publicComments ?? const <CommunityFeedbackComment>[];

  int get commentThreadCount {
    return publicComments.fold<int>(
      0,
      (total, comment) => total + 1 + comment.replies.length,
    );
  }

  int get visibleLikeCount => math.max(0, likeCount - disagreeCount);

  String get contributorName {
    if (userDisplayName?.trim().isNotEmpty == true) {
      return userDisplayName!.trim();
    }
    if (userEmail?.trim().isNotEmpty == true) return userEmail!.trim();
    return 'PumpScout contributor';
  }

  factory CommunityContribution.fromFirestore({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required ContributorTrustBadge trustBadge,
    required int likeCount,
    required int disagreeCount,
    required int feedbackCount,
    required String? myReaction,
    List<CommunityFeedbackComment> publicComments =
        const <CommunityFeedbackComment>[],
  }) {
    final data = doc.data();
    return CommunityContribution(
      id: doc.id,
      stationName: _stringField(data, 'stationName', fallback: 'Fuel station'),
      brand: _stringField(data, 'brand'),
      createdAt: _dateTimeField(data, 'createdAt') ?? DateTime(1970),
      lat: _doubleField(data, 'lat') ?? 0,
      lng: _doubleField(data, 'lng') ?? 0,
      gasoline: _doubleField(data, 'gasoline'),
      diesel: _doubleField(data, 'diesel'),
      premium: _doubleField(data, 'premium'),
      fuelProducts: _doubleMapField(data, 'fuelProducts'),
      photoUrl: _stringField(data, 'photoUrl'),
      userId: _stringField(data, 'userId'),
      userDisplayName: _stringField(data, 'userDisplayName'),
      userEmail: _stringField(data, 'userEmail'),
      likeCount: likeCount,
      disagreeCount: disagreeCount,
      feedbackCount: feedbackCount,
      myReaction: myReaction,
      publicComments: publicComments,
      trustBadge: trustBadge,
    );
  }

  CommunityContribution copyWith({
    int? likeCount,
    int? disagreeCount,
    int? feedbackCount,
    String? myReaction,
    List<CommunityFeedbackComment>? publicComments,
  }) {
    return CommunityContribution(
      id: id,
      stationName: stationName,
      brand: brand,
      createdAt: createdAt,
      trustBadge: trustBadge,
      lat: lat,
      lng: lng,
      gasoline: gasoline,
      diesel: diesel,
      premium: premium,
      fuelProducts: fuelProducts,
      photoUrl: photoUrl,
      userId: userId,
      userDisplayName: userDisplayName,
      userEmail: userEmail,
      likeCount: likeCount ?? this.likeCount,
      disagreeCount: disagreeCount ?? this.disagreeCount,
      feedbackCount: feedbackCount ?? this.feedbackCount,
      myReaction: myReaction,
      publicComments: publicComments ?? this.publicComments,
    );
  }
}

class ContributorTrustBadge {
  const ContributorTrustBadge({
    required this.label,
    required this.score,
    required this.reason,
  });

  final String label;
  final int score;
  final String reason;
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
