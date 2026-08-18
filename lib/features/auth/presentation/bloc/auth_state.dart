import 'package:equatable/equatable.dart';

import '../../domain/entities/auth_token.dart';

class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthError extends AuthState {
  final String message;

  AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AuthLoaded extends AuthState {
  final AuthToken token;

  AuthLoaded({required this.token});

  @override
  List<Object?> get props => [
    token.accessToken,
    token.refreshToken,
    token.user,
  ];
}

class AuthOtpPending extends AuthState {
  final String email;
  final DateTime cooldownUntil;
  final bool justResent;
  final bool verifying;
  final bool resending;
  final String? error;

  AuthOtpPending({
    required this.email,
    required this.cooldownUntil,
    this.justResent = false,
    this.verifying = false,
    this.resending = false,
    this.error,
  });

  AuthOtpPending copyWith({
    DateTime? cooldownUntil,
    bool? justResent,
    bool? verifying,
    bool? resending,
    String? error,
    bool clearError = false,
  }) {
    return AuthOtpPending(
      email: email,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      justResent: justResent ?? this.justResent,
      verifying: verifying ?? this.verifying,
      resending: resending ?? this.resending,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    email,
    cooldownUntil,
    justResent,
    verifying,
    resending,
    error,
  ];
}

/// Waiting on the code emailed by a password reset.
///
/// Separate from [AuthOtpPending] even though both hold an email and a
/// cooldown: that one means "finish signing up" and the screen behind it only
/// asks for a code, while this one also collects the new password. Sharing it
/// would leave the OTP screen unable to tell which it is looking at.
class AuthPasswordResetPending extends AuthState {
  final String email;
  final DateTime cooldownUntil;
  final bool justSent;
  final bool submitting;
  final bool resending;
  final String? error;

  AuthPasswordResetPending({
    required this.email,
    required this.cooldownUntil,
    this.justSent = false,
    this.submitting = false,
    this.resending = false,
    this.error,
  });

  AuthPasswordResetPending copyWith({
    DateTime? cooldownUntil,
    bool? justSent,
    bool? submitting,
    bool? resending,
    String? error,
    bool clearError = false,
  }) {
    return AuthPasswordResetPending(
      email: email,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      justSent: justSent ?? this.justSent,
      submitting: submitting ?? this.submitting,
      resending: resending ?? this.resending,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    email,
    cooldownUntil,
    justSent,
    submitting,
    resending,
    error,
  ];
}
