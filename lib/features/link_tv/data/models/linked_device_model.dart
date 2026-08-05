import '../../domain/entities/linked_device.dart';

class LinkedDeviceModel extends LinkedDevice {
  const LinkedDeviceModel({
    required super.id,
    super.deviceName,
    super.lastSeenAt,
    super.linkedAt,
  });

  factory LinkedDeviceModel.fromJson(Map<String, dynamic> json) {
    return LinkedDeviceModel(
      id: json['id']?.toString() ?? '',
      deviceName: json['deviceName'] as String?,
      lastSeenAt: _parseDate(json['lastSeenAt']),
      linkedAt: _parseDate(json['linkedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
