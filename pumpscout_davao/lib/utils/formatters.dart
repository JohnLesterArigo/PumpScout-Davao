part of '../main.dart';

String _stationName(dynamic station) {
  if (station is! Map<String, dynamic>) return 'Fuel';

  final tags = station['tags'];
  if (tags is Map<String, dynamic>) {
    for (final key in ['brand', 'name', 'operator']) {
      final value = tags[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }

  return 'Fuel';
}

String _stringField(
  Map<String, dynamic> data,
  String key, {
  String fallback = '',
}) {
  final value = data[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

List<String> _stringListField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is Iterable) {
    return value
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

double? _doubleField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim().replaceAll(',', ''));
  return null;
}

double? _doubleAnyField(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = _doubleField(data, key);
    if (value != null && value > 0) return value;
  }

  return null;
}

double? _stationFuelPrice(Map<String, dynamic> data, String fuelType) {
  return _doubleAnyField(data, _stationFuelFieldAliases(fuelType));
}

List<String> _stationFuelFieldAliases(String fuelType) {
  return switch (fuelType) {
    'diesel' => const [
      'diesel',
      'Diesel',
      'Shell FuelSave Diesel',
      'Shell V-Power Diesel',
      'Petron Diesel Max',
      'Petron Turbo Diesel',
      'Unioil Diesel',
      'Caltex Diesel',
      'Seaoil Exceed Diesel',
      'SeaOil Exceed Diesel',
      'SEAOIL Exceed Diesel',
      'Exceed Diesel',
      'Seaoil Diesel',
      'SeaOil Diesel',
      'Phoenix Diesel',
      'Total Diesel',
    ],
    'premium' => const [
      'Shell V-Power Gasoline',
      'Shell V-Power',
      'Petron XCS',
      'Petron Blaze',
      'Unioil Gasoline 95',
      'Unioil Gas 95',
      'Caltex Platinum',
      'Seaoil Extreme 95',
      'SeaOil Extreme 95',
      'SEAOIL Extreme 95',
      'Extreme 95',
      'Seaoil Extreme 97',
      'SeaOil Extreme 97',
      'Phoenix Premium 98',
      'Total Excellium',
      'premium',
      'Premium',
      'premiumGasoline',
      'Premium Gasoline',
    ],
    _ => const [
      'gasoline',
      'Gasoline',
      'unleaded',
      'Unleaded',
      'regular',
      'Regular',
      'Shell FuelSave Gasoline',
      'Petron Xtra Advance',
      'Petron Xtra',
      'Unioil Gasoline',
      'Unioil Gas',
      'Caltex Silver',
      'Seaoil Extreme U',
      'SeaOil Extreme U',
      'SEAOIL Extreme U',
      'Extreme U',
      'Phoenix Gasoline 95',
      'Total Unleaded',
    ],
  };
}

DateTime? _dateTimeField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

double? _parsePrice(String value) {
  final normalized = value.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

String _formatDateTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes} min ago';
  if (difference.inDays < 1) return '${difference.inHours} hr ago';
  if (difference.inDays < 7) return '${difference.inDays} days ago';

  return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
}

String _profileValue(dynamic value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}
