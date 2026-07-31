import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'provider_event.dart';
import 'provider_state.dart';

const String _kCloudStreamIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s';

const String _kAniyomiIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';

const String _kMangaIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';

class ProviderBloc extends Bloc<ProviderEvent, ProviderState> {
  final GetProvidersUseCase useCase;
  final HiveService hiveService;
  final ProviderManager providerManager;
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

    // The on-device plugin hosts are appended in every branch, including the
    // failure one. They talk to Kotlin over a platform channel and need no
    // backend at all, so an outage must never hide them — that is exactly when
    // they are the only thing keeping the app usable.
    final providers = <ProviderEntity>[];
    var offline = false;
    DateTime? cachedAt;

    switch (result) {
      case Success(:final value):
        providers.addAll(value.providers.where((p) => p.id.trim().isNotEmpty));
        offline = value.fromCache;
        cachedAt = value.cachedAt;
      case Failure():
        // No network list and no cache — local plugins are all we have.
        offline = true;
    }

    await _appendCloudStreamProviders(providers);
    await _appendAniyomiProviders(providers);
    await _appendMangaProviders(providers);

    if (providers.isEmpty) {
      if (previous is! ProviderLoaded) {
        emit(ProviderError());
      }
      return;
    }

    final resolvedId = await _resolveAndPersistProvider(
      providers,
      offline: offline,
    );

    providerManager.updateProviders(providers);
    providerRegistry.invalidate();

    emit(
      ProviderLoaded(
        providers: providers,
        currentProviderId: resolvedId,
        offline: offline,
        cachedAt: cachedAt,
      ),
    );
  }

  Future<void> _onSelect(
    ProviderSelect event,
    Emitter<ProviderState> emit,
  ) async {
    await hiveService.saveCurrentProvider(event.providerId);
    // An explicit pick supersedes any provider parked by the outage handler,
    // so it is not undone when the backend comes back.
    await hiveService.clearPreOutageProvider();
    if (state is ProviderLoaded) {
      final loaded = state as ProviderLoaded;
      emit(
        ProviderLoaded(
          providers: loaded.providers,
          currentProviderId: event.providerId,
          offline: loaded.offline,
          cachedAt: loaded.cachedAt,
        ),
      );
    }
  }

  Future<void> _appendCloudStreamProviders(List<ProviderEntity> into) async {
    if (!CloudStreamChannel.isSupported) return;
    try {
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
          description: (m['repo'] as String?)?.isNotEmpty == true
              ? m['repo'] as String
              : 'CloudStream',
          domains: const [],
          mode: 'client',
          category: 'cloudstream',
          nsfw: m['nsfw'] == true,
        ));
      }
    } catch (_) {
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
          nsfw: m['nsfw'] == true,
        ));
      }
    } catch (_) {}
  }

  Future<void> _appendMangaProviders(List<ProviderEntity> into) async {
    if (!MangaChannel.isSupported) return;
    // Adult manga sources are opt-in. Dropping them here rather than in the
    // picker's own filter is deliberate: everything downstream — the picker,
    // ProviderManager, and _resolveAndPersistProvider — works off this list, so
    // a hidden source is also one the resolver will not keep selected. Turning
    // the setting off therefore retires a dangling 18+ selection on the next
    // load instead of leaving it live but invisible.
    final allowNsfw = hiveService.showNsfwMangaSources;
    try {
      final list = await MangaChannel.ensureLoaded();
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        if (m['nsfw'] == true && !allowNsfw) continue;
        into.add(ProviderModel(
          id: id,
          name: (m['name'] as String?) ?? id,
          image: (m['icon'] as String?)?.isNotEmpty == true
              ? m['icon'] as String
              : _kMangaIcon,
          url: (m['baseUrl'] as String?) ?? '',
          description: (m['repo'] as String?)?.isNotEmpty == true
              ? m['repo'] as String
              : 'Manga',
          domains: const [],
          mode: 'client',
          category: 'manga',
          nsfw: m['nsfw'] == true,
        ));
      }
    } catch (_) {}
  }

  /// Picks the provider to run with and keeps Hive in step, because the home,
  /// search and detail repositories all read the current id straight out of
  /// Hive — a selection that lived only in bloc state would leave them calling
  /// the dead server while the UI showed a working plugin.
  ///
  /// During an outage a saved *server* provider is unusable, so we move to an
  /// on-device plugin and park the original id, restoring it the moment the
  /// backend answers again. A deliberate pick made during the outage clears
  /// the parked id (see [_onSelect]) and therefore sticks.
  Future<String> _resolveAndPersistProvider(
    List<ProviderEntity> providers, {
    required bool offline,
  }) async {
    final savedId = hiveService.getCurrentProvider();
    final saved = providers.where((p) => p.id == savedId).firstOrNull;

    if (!offline) {
      final parked = hiveService.getPreOutageProvider();
      if (parked.isNotEmpty) {
        await hiveService.clearPreOutageProvider();
        if (providers.any((p) => p.id == parked)) {
          if (parked != savedId) await hiveService.saveCurrentProvider(parked);
          return parked;
        }
      }
      if (saved != null) return saved.id;
      final fallback = providers.first.id;
      await hiveService.saveCurrentProvider(fallback);
      return fallback;
    }

    if (saved != null && saved.isServerIndependent) return saved.id;

    final local = providers.where((p) => p.isServerIndependent).firstOrNull;
    // Nothing local to fall back to — leave the saved id alone so the picker's
    // offline state is what the user sees, not a silent switch.
    if (local == null) return saved?.id ?? providers.first.id;

    if (savedId.isNotEmpty && hiveService.getPreOutageProvider().isEmpty) {
      await hiveService.savePreOutageProvider(savedId);
    }
    await hiveService.saveCurrentProvider(local.id);
    return local.id;
  }
}
