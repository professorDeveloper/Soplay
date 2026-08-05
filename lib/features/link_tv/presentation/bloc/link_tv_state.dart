part of 'link_tv_bloc.dart';

class LinkTvState extends Equatable {
  final String code;
  final bool submitting;
  final bool approved;
  final String? approvedDeviceName;

  final List<LinkedDevice> devices;
  final bool loadingDevices;

  /// Id of the device currently being unlinked, so only its row shows a spinner.
  final String? unlinkingId;

  /// An easy_localization key when the reason is known, else null.
  final String? errorKey;

  /// The backend's own text, shown only when no [errorKey] applies.
  final String? errorMessage;

  const LinkTvState({
    this.code = '',
    this.submitting = false,
    this.approved = false,
    this.approvedDeviceName,
    this.devices = const [],
    this.loadingDevices = false,
    this.unlinkingId,
    this.errorKey,
    this.errorMessage,
  });

  bool get canSubmit => !submitting && code.length == LinkTvBloc.codeLength;

  bool get hasError => errorKey != null || errorMessage != null;

  LinkTvState copyWith({
    String? code,
    bool? submitting,
    bool? approved,
    String? approvedDeviceName,
    List<LinkedDevice>? devices,
    bool? loadingDevices,
    String? unlinkingId,
    bool clearUnlinkingId = false,
    String? errorKey,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LinkTvState(
      code: code ?? this.code,
      submitting: submitting ?? this.submitting,
      approved: approved ?? this.approved,
      approvedDeviceName: approvedDeviceName ?? this.approvedDeviceName,
      devices: devices ?? this.devices,
      loadingDevices: loadingDevices ?? this.loadingDevices,
      unlinkingId: clearUnlinkingId ? null : (unlinkingId ?? this.unlinkingId),
      errorKey: clearError ? null : (errorKey ?? this.errorKey),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Applies a repository failure, preferring the modelled key over raw server text
  /// so the same wording is shown in every language. Built directly rather than
  /// through [copyWith] because every failure also ends whatever was in flight.
  LinkTvState withError(Exception error) {
    final failure = error is LinkTvFailure ? error : null;
    final key = failure?.messageKey;
    return LinkTvState(
      code: code,
      approved: approved,
      approvedDeviceName: approvedDeviceName,
      devices: devices,
      errorKey: key,
      errorMessage:
          key != null ? null : (failure?.serverMessage ?? error.toString()),
    );
  }

  @override
  List<Object?> get props => [
        code,
        submitting,
        approved,
        approvedDeviceName,
        devices,
        loadingDevices,
        unlinkingId,
        errorKey,
        errorMessage,
      ];
}
