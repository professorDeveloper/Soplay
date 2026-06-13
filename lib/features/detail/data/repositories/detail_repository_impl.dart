import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/player/webview_stream_extractor.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';

class DetailRepositoryImpl implements DetailRepository {
  final DetailDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;
  final WebViewStreamExtractor? webViewExtractor;

  const DetailRepositoryImpl(
    this.dataSource, {
    this.jsRuntime,
    this.hive,
    this.webViewExtractor,
  });

  String? _resolveProvider(String? provider) {
    if (provider != null && provider.isNotEmpty) return provider;
    final fromHive = hive?.getCurrentProvider();
    if (fromHive != null && fromHive.isNotEmpty) return fromHive;
    return null;
  }

  @override
  Future<Result<DetailEntity>> getDetail(String contentUrl, {String? provider}) async {
    final js = jsRuntime;
    final effective = _resolveProvider(provider);
    if (effective != null && effective.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(DetailModel.fromJson(map));
        return Failure(Exception('CloudStream: details not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(DetailModel.fromJson(map));
        return Failure(Exception('Aniyomi: details not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (js != null && effective != null) {
      try {
        final map = await js.tryGetDetail(effective, contentUrl);
        if (map != null) return Success(DetailModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    try {
      return Success(await dataSource.getDetail(contentUrl, provider: effective));
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async {
    final js = jsRuntime;
    final effective = _resolveProvider(provider);
    if (effective != null && effective.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(PlaybackModel.fromJson(map));
        return Failure(Exception('CloudStream: episodes not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(PlaybackModel.fromJson(map));
        return Failure(Exception('Aniyomi: episodes not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (js != null && effective != null) {
      try {
        final map = await js.tryGetEpisodes(effective, contentUrl);
        if (map != null) return Success(PlaybackModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    try {
      return Success(
        await dataSource.getEpisodes(
          contentUrl,
          page: page,
          size: size,
          sort: sort,
          provider: effective,
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 501) {
        return Failure(
          Exception('Provider epizodlarni qo\'llab-quvvatlamaydi'),
        );
      }
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    if (provider.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.loadLinks(provider.substring(3), ref);
        final sources = map['videoSources'];
        if (map.isNotEmpty && sources is List && sources.isNotEmpty) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
        return Failure(Exception('CloudStream: oqim topilmadi'));
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] CloudStream path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (provider.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.loadLinks(provider.substring(3), ref);
        final sources = map['videoSources'];
        if (map.isNotEmpty && sources is List && sources.isNotEmpty) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
        return Failure(Exception('Aniyomi: oqim topilmadi'));
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] Aniyomi path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    final js = jsRuntime;
    if (js != null) {
      try {
        final map = await js.tryResolveMedia(
          provider: provider,
          ref: ref,
          lang: lang,
        );
        if (map != null) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] JS path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }

    try {
      return _postProcess(
        await dataSource.resolveMedia(
          ref: ref,
          provider: provider,
          lang: lang,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 422) {
        return Failure(Exception('Video URL aniqlanmadi'));
      }
      if (code == 501) {
        return Failure(
          Exception('Provider media yechishni qo\'llab-quvvatlamaydi'),
        );
      }
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<MediaResolveEntity>> _postProcess(
    MediaResolveEntity media,
  ) async {
    // No special post-processing currently. webview-extract was used by
    // uzmovi which has been removed — kept here as a no-op pass-through so
    // future webview-extract providers (if any) don't break the flow.
    return Success(media);
  }

  String _normalizeJsError(Object error) {
    final raw = error.toString();
    if (raw.contains('no playable source')) return 'Video manbasi topilmadi';
    if (raw.contains('Invalid mediaRef')) {
      return 'Provider versiyasi eskirgan';
    }
    if (raw.contains('No servers found')) return 'Episode uchun server yo\'q';
    return raw.replaceFirst('Exception: ', '');
  }

  String _messageFrom(DioException e) {
    return (e.response?.data as Map<String, dynamic>?)?['message']
            as String? ??
        e.message ??
        'Xatolik yuz berdi';
  }
}
