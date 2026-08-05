import 'package:equatable/equatable.dart';

/// A TV (or other device) that has been linked to this account via a QR pairing.
class LinkedDevice extends Equatable {
  final String id;
  final String? deviceName;
  final DateTime? lastSeenAt;
  final DateTime? linkedAt;

  const LinkedDevice({
    required this.id,
    this.deviceName,
    this.lastSeenAt,
    this.linkedAt,
  });

  @override
  List<Object?> get props => [id, deviceName, lastSeenAt, linkedAt];
}
