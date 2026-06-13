import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'provider_event.dart';
import 'provider_state.dart';

/// Shared icon shown for every CloudStream (`cs:`) provider in the list.
const String _kCloudStreamIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s';

/// Shared icon shown for every Aniyomi (`an:`) provider in the list.
const String _kAniyomiIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';

class ProviderBloc extends Bloc<ProviderEvent, ProviderState> {
  final GetProvidersUseCase useCase;
  final HiveService hiveService;
  final ProviderManager providerManager;
  // ProviderRegistry feeds the legacy JsRuntimeService path. It caches the
  // provider list in-memory for the lifetime of the app, so a backend change
  // (e.g. a provider flipping from `server` → `hybrid`) wouldn't take effect
  // until the user killed the app. Invalidating it on every successful
  // ProviderLoad keeps both caches in sync.
  final ProviderRegistry providerRegistry;

  ProviderBloc({
    required this.useCase,
    required this.hiveService,
    required this.providerManager,
    required this.providerRegistry,
  }) : super(ProviderInitial()) {
    on<ProviderLoad>(_onLoad);
    on<ProviderSelect>(_onSelect);
  }

  Future<void> _onLoad(ProviderLoad event, Emitter<ProviderState> emit) async {
    final previous = state;
    if (previous is! ProviderLoaded) {
      emit(ProviderLoading());
    }

    final result = await useCase();
    switch (result) {
      case Success(:final value):
        final providers = value
            .where((p) => p.id.trim().isNotEmpty)
            .toList();

        // Merge native CloudStream providers (Android-only). They live in the
        // `cs:` id namespace and are routed to the native channel by the data
        // repositories; the rest of the app treats them like any provider.
        await _appendCloudStreamProviders(providers);
        await _appendAniyomiProviders(providers);

        if (providers.isEmpty) {
          if (previous is! ProviderLoaded) {
            emit(ProviderError());
          }
          return;
        }

        final resolvedId = _resolveCurrentProviderId(providers);
        if (resolvedId != hiveService.getCurrentProvider()) {
          await hiveService.saveCurrentProvider(resolvedId);
        }

        providerManager.updateProviders(providers);
        // Drop the legacy registry's in-memory cache so JsRuntimeService
        // re-fetches /providers next time it needs scope/mode info.
        providerRegistry.invalidate();

        emit(
          ProviderLoaded(providers: providers, currentProviderId: resolvedId),
        );
      case Failure():
        if (previous is! ProviderLoaded) {
          emit(ProviderError());
        }
    }
  }

  Future<void> _onSelect(
    ProviderSelect event,
    Emitter<ProviderState> emit,
  ) async {
    await hiveService.saveCurrentProvider(event.providerId);
    if (state is ProviderLoaded) {
      final loaded = state as ProviderLoaded;
      emit(
        ProviderLoaded(
          providers: loaded.providers,
          currentProviderId: event.providerId,
        ),
      );
    }
  }

  Future<void> _appendCloudStreamProviders(List<ProviderEntity> into) async {
    if (!CloudStreamChannel.isSupported) return;
    try {
      // ensureLoaded re-adds saved repos (once per process) and returns the
      // resulting provider list.
      final list = await CloudStreamChannel.ensureLoaded();
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        into.add(ProviderModel(
          id: id,
          name: (m['name'] as String?) ?? id,
          image: (m['icon'] as String?)?.isNotEmpty == true
              ? m['icon'] as String
              : _kCloudStreamIcon,
          url: (m['mainUrl'] as String?) ?? '',
          // Show which repo this provider came from (e.g. "phisher98/…") as the
          // subtitle; fall back to a generic label for legacy entries.
          description: (m['repo'] as String?)?.isNotEmpty == true
              ? m['repo'] as String
              : 'CloudStream',
          domains: const [],
          mode: 'client',
          category: 'cloudstream',
        ));
      }
    } catch (_) {
      // CloudStream optional — never block the provider list on it.
    }
  }

  Future<void> _appendAniyomiProviders(List<ProviderEntity> into) async {
    if (!AniyomiChannel.isSupported) return;
    try {
      final list = await AniyomiChannel.ensureLoaded();
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        into.add(ProviderModel(
          id: id,
          name: (m['name'] as String?) ?? id,
          image: (m['icon'] as String?)?.isNotEmpty == true
              ? m['icon'] as String
              : _kAniyomiIcon,
          url: (m['baseUrl'] as String?) ?? '',
          description: (m['repo'] as String?)?.isNotEmpty == true
              ? m['repo'] as String
              : 'Aniyomi',
          domains: const [],
          mode: 'client',
          category: 'aniyomi',
        ));
      }
    } catch (_) {}
  }

  String _resolveCurrentProviderId(List<ProviderEntity> providers) {
    final savedProviderId = hiveService.getCurrentProvider();
    final hasSavedProvider = providers.any((p) => p.id == savedProviderId);
    if (hasSavedProvider) return savedProviderId;
    return providers.first.id;
  }
}
