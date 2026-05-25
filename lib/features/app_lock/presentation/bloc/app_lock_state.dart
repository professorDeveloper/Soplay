import 'package:equatable/equatable.dart';

enum AppLockStage {
  chooseLength,
  enterNew,
  confirmNew,
  verify,
  done,
  disabled,
}

class AppLockState extends Equatable {
  const AppLockState({
    required this.stage,
    required this.pinLength,
    required this.entered,
    required this.firstPin,
    required this.biometricAvailable,
    required this.biometricPreferred,
    required this.errorTick,
    required this.errorMessage,
    required this.isProcessing,
  });

  factory AppLockState.initial() => const AppLockState(
        stage: AppLockStage.chooseLength,
        pinLength: 4,
        entered: '',
        firstPin: '',
        biometricAvailable: false,
        biometricPreferred: false,
        errorTick: 0,
        errorMessage: null,
        isProcessing: false,
      );

  final AppLockStage stage;
  final int pinLength;
  final String entered;
  final String firstPin;
  final bool biometricAvailable;
  final bool biometricPreferred;
  final int errorTick;
  final String? errorMessage;
  final bool isProcessing;

  AppLockState copyWith({
    AppLockStage? stage,
    int? pinLength,
    String? entered,
    String? firstPin,
    bool? biometricAvailable,
    bool? biometricPreferred,
    int? errorTick,
    String? errorMessage,
    bool clearError = false,
    bool? isProcessing,
  }) {
    return AppLockState(
      stage: stage ?? this.stage,
      pinLength: pinLength ?? this.pinLength,
      entered: entered ?? this.entered,
      firstPin: firstPin ?? this.firstPin,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricPreferred: biometricPreferred ?? this.biometricPreferred,
      errorTick: errorTick ?? this.errorTick,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  @override
  List<Object?> get props => [
        stage,
        pinLength,
        entered,
        firstPin,
        biometricAvailable,
        biometricPreferred,
        errorTick,
        errorMessage,
        isProcessing,
      ];
}
