import 'package:equatable/equatable.dart';
import '../../domain/entities/provider_entity.dart';

abstract class ProviderState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ProviderInitial extends ProviderState {}

class ProviderLoading extends ProviderState {}

class ProviderLoaded extends ProviderState {
  final List<ProviderEntity> providers;
  final String currentProviderId;

  /// The backend was unreachable: [providers] came from the Hive cache and/or
  /// the on-device plugin hosts, and every server-backed entry in it is
  /// currently unusable.
  final bool offline;

  /// When the cached slice of [providers] was stored. Null if there was no
  /// cache and this is a local-plugins-only list.
  final DateTime? cachedAt;

  ProviderLoaded({
    required this.providers,
    required this.currentProviderId,
    this.offline = false,
    this.cachedAt,
  });

  ProviderEntity? get currentProvider =>
      providers.where((p) => p.id == currentProviderId).firstOrNull;

  /// Whether [provider] can actually serve content right now. Offline, only
  /// the on-device plugin hosts can.
  bool isUsable(ProviderEntity provider) =>
      !offline || provider.isServerIndependent;

  /// The providers that work right now — the set consumers should fan out to.
  List<ProviderEntity> get usableProviders => offline
      ? providers.where((p) => p.isServerIndependent).toList()
      : providers;

  @override
  List<Object?> get props => [providers, currentProviderId, offline, cachedAt];
}

class ProviderError extends ProviderState {}
