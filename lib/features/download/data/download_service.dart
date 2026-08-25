import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class DownloadService {
  DownloadService() {
    if (_useNativeDownloader) {
      _nativePoller = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(syncNativeStates()),
      );
    }
  }

  /// How many downloads actually run at once.
  ///
  /// Queuing ten episodes used to start ten transfers, which on a phone means
  /// ten streams fighting over one connection: everything crawls, the first
  /// episode the viewer wanted to watch finishes last, and on mobile data it is
  /// the worst possible shape. Two keeps the link busy without starving the one
  /// at the front of the queue.
  static const int maxConcurrent = 2;

  final Dio _dio = Dio();
  final Map<String, CancelToken> _tokens = {};

  /// Accepted but not yet started, oldest first.
  final List<DownloadItem> _queue = [];

  /// Ids currently transferring, so [_pump] knows when a slot frees.
  final Set<String> _running = {};
  final _NativeDownloadBridge _native = _NativeDownloadBridge();
  Timer? _nativePoller;
  int _activeCount = 0;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Box get _box => Hive.box(AppConstants.downloadBox);

  bool get _useNativeDownloader =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String _fnv(String value) {
    var hash = 0x811c9dc5;
    for (final u in value.codeUnits) {
      hash ^= u;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(36);
  }

  static String mangaChapterId({
    required String contentUrl,
    required String provider,
    required String chapterRef,
  }) => _fnv('manga|$contentUrl|$provider|$chapterRef');

  /// Id for a downloaded episode, or for a movie when [episodeNumber] is null.
  ///
  /// Both the player and the episode list build ids for the same episode, and
  /// they have to agree byte for byte. When they did not, the list showed no
  /// progress for a download the player had started, and starting it again
  /// from the other screen downloaded the same file twice. One definition,
  /// used from both.
  static String videoId({
    required String contentUrl,
    int? episodeNumber,
  }) =>
      _fnv(episodeNumber == null ? contentUrl : '${contentUrl}_ep$episodeNumber');

  void dispose() {
    _nativePoller?.cancel();
    revision.dispose();
  }

  List<DownloadItem> getAll() {
    final items = <DownloadItem>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is String) {
          items.add(
            DownloadItem.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  DownloadItem? get(String id) {
    final raw = _box.get(id);
    if (raw is! String) return null;
    try {
      return DownloadItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool isDownloaded(String id) {
    final item = get(id);
    return item != null && item.status == DownloadStatus.completed;
  }

  int _lastRevisionMs = 0;

  Future<void> _save(DownloadItem item, {bool force = false}) async {
    await _box.put(item.id, jsonEncode(item.toJson()));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (force || now - _lastRevisionMs > 500) {
      _lastRevisionMs = now;
      revision.value++;
    }
  }

  Future<void> _acquireWakelock() async {
    _activeCount++;
    if (_activeCount == 1) await WakelockPlus.enable();
  }

  Future<void> _releaseWakelock() async {
    _activeCount--;
    if (_activeCount <= 0) {
      _activeCount = 0;
      await WakelockPlus.disable();
    }
  }

  Future<String> _itemDir(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final dlDir = Directory('${dir.path}/downloads/$id');
    if (!await dlDir.exists()) await dlDir.create(recursive: true);
    return dlDir.path;
  }

  bool _isHls(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8');
  }

  /// Accept a download. Returns whether it was accepted, NOT whether it
  /// finished.
  ///
  /// It used to await the whole transfer on the Dart path while returning
  /// immediately on the native one, so the caller's "Download started" message
  /// appeared at the start on Android and at the *end* everywhere else. A queue
  /// makes both paths agree, and agrees with what the message already said.
  Future<bool> startDownload(DownloadItem item) async {
    if (_tokens.containsKey(item.id) ||
        _running.contains(item.id) ||
        _queue.any((q) => q.id == item.id)) {
      return false;
    }

    if (_useNativeDownloader) {
      return _startNativeDownload(item);
    }

    // Persisted as pending before it starts so it appears in the list the
    // moment it is accepted. A queued download that is invisible until a slot
    // frees looks like a button that did nothing.
    await _save(item.copyWith(status: DownloadStatus.pending), force: true);
    _queue.add(item);
    _pump();
    return true;
  }

  /// Start whatever the free slots allow.
  void _pump() {
    while (_running.length < maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _running.add(next.id);
      unawaited(
        _run(next).whenComplete(() {
          _running.remove(next.id);
          // Draining from here rather than from a timer means the next item
          // starts the instant a slot frees.
          _pump();
        }),
      );
    }
  }

  /// Stop a transfer but keep what it has already written.
  ///
  /// Distinct from [cancelDownload], which is a request to forget the thing.
  /// A paused HLS download keeps its segments, and [resume] picks up where it
  /// stopped because the segment loop skips files that are already on disk.
  Future<void> pause(String id) async {
    _queue.removeWhere((q) => q.id == id);
    _tokens[id]?.cancel();
    _tokens.remove(id);
    final item = get(id);
    if (item == null) return;
    if (item.status == DownloadStatus.completed) return;
    await _save(item.copyWith(status: DownloadStatus.paused), force: true);
  }

  Future<void> resume(String id) async {
    final item = get(id);
    if (item == null || item.status == DownloadStatus.completed) return;
    await startDownload(item);
  }

  Future<bool> _run(DownloadItem item) async {
    final cancel = CancelToken();
    _tokens[item.id] = cancel;

    var dl = item.copyWith(status: DownloadStatus.downloading);
    dl = await _cacheThumbnail(dl);
    await _save(dl, force: true);
    await _acquireWakelock();

    try {
      if (item.kind == 'manga') {
        dl = await _downloadMangaChapter(dl, cancel);
      } else if (_isHls(item.videoUrl)) {
        dl = await _downloadHls(dl, cancel);
      } else {
        dl = await _downloadDirect(dl, cancel);
      }
      // A cancelled HLS/manga download returns early with status still
      // 'downloading'; don't persist it as completed (an HLS entry would have
      // no index.m3u8 and be unplayable). Mirrors the DioException cancel path.
      if (cancel.isCancelled) return false;
      dl = dl.copyWith(status: DownloadStatus.completed);
      await _save(dl, force: true);
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return false;
      dl = dl.copyWith(status: DownloadStatus.failed);
      await _save(dl, force: true);
      return false;
    } catch (e) {
      debugPrint('[DOWNLOAD] error: $e');
      dl = dl.copyWith(status: DownloadStatus.failed);
      await _save(dl, force: true);
      return false;
    } finally {
      _tokens.remove(item.id);
      await _releaseWakelock();
    }
  }

  Future<bool> _startNativeDownload(DownloadItem item) async {
    final dir = await _itemDir(item.id);
    var dl = item;

    final String localPath;
    if (item.kind == 'manga') {
      localPath = dir;
      if (dl.pageUrls.isEmpty && dl.chapterRef != null) {
        final res = await getIt<GetPagesUseCase>()(
          ref: dl.chapterRef!,
          provider: dl.provider,
        );
        if (res is Success<MangaPagesEntity>) {
          dl = dl.copyWith(
            pageUrls: res.value.pages.map((p) => p.imageUrl).toList(),
            headers: res.value.headers,
          );
        }
      }
    } else if (_isHls(item.videoUrl)) {
      localPath = '$dir/index.m3u8';
    } else {
      localPath = '$dir/video${_extensionFrom(item.videoUrl)}';
    }

    dl = dl.copyWith(
      localPath: localPath,
      status: DownloadStatus.downloading,
    );
    dl = await _cacheThumbnail(dl);
    await _save(dl, force: true);

    final started = await _native.startDownload(dl);
    if (!started) {
      await _save(dl.copyWith(status: DownloadStatus.failed), force: true);
      return false;
    }

    await syncNativeStates();
    return true;
  }

  Future<void> resumeIncomplete() async {
    if (_useNativeDownloader) {
      await syncNativeStates();
    }
    final items = getAll();
    for (final item in items) {
      // `pending` is included because the app can be killed with items still
      // queued, and those never started at all — leaving them out would strand
      // exactly the downloads that had not had their turn yet. `paused` is
      // excluded on purpose: that state was chosen by the viewer, and a restart
      // is not consent to resume.
      if (item.status == DownloadStatus.downloading ||
          item.status == DownloadStatus.pending) {
        unawaited(startDownload(item));
      }
    }
  }

  Future<void> syncNativeStates() async {
    if (!_useNativeDownloader) return;
    List<_NativeDownloadState> states;
    try {
      states = await _native.getStates();
    } catch (_) {
      return;
    }

    for (final state in states) {
      final item = get(state.id);
      if (item == null) continue;

      final status = switch (state.status) {
        'completed' => DownloadStatus.completed,
        'failed' => DownloadStatus.failed,
        'cancelled' => DownloadStatus.failed,
        'downloading' => DownloadStatus.downloading,
        _ => item.status,
      };
      final updated = item.copyWith(
        status: status,
        localPath: state.localPath.isEmpty ? item.localPath : state.localPath,
        downloadedBytes: state.downloadedBytes,
        totalBytes: state.totalBytes,
      );
      if (updated.status != item.status ||
          updated.localPath != item.localPath ||
          updated.downloadedBytes != item.downloadedBytes ||
          updated.totalBytes != item.totalBytes) {
        await _save(updated, force: true);
      }
    }
  }

  Future<DownloadItem> _downloadDirect(
    DownloadItem dl,
    CancelToken cancel,
  ) async {
    final dir = await _itemDir(dl.id);
    final ext = _extensionFrom(dl.videoUrl);
    final path = '$dir/video$ext';

    var current = dl.copyWith(localPath: path);
    await _save(current);

    await _dio.download(
      dl.videoUrl,
      path,
      cancelToken: cancel,
      options: Options(headers: dl.headers),
      onReceiveProgress: (received, total) {
        current = current.copyWith(
          downloadedBytes: received,
          totalBytes: total > 0 ? total : 0,
        );
        _save(current);
      },
    );
    return current;
  }

  Future<DownloadItem> _cacheThumbnail(DownloadItem item) async {
    final thumbnail = item.thumbnail?.trim();
    if (thumbnail == null || thumbnail.isEmpty) return item;

    final dir = await _itemDir(item.id);
    final path = '$dir/thumbnail${_imageExtensionFrom(thumbnail)}';
    final file = File(path);
    if (await file.exists() && await file.length() > 0) {
      return item.copyWith(localThumbnailPath: path);
    }

    try {
      await _dio.download(
        thumbnail,
        path,
        options: Options(headers: item.headers),
      );
      if (await file.exists() && await file.length() > 0) {
        return item.copyWith(localThumbnailPath: path);
      }
    } catch (e) {
      debugPrint('[DOWNLOAD] thumbnail cache failed: $e');
    }
    return item;
  }

  Future<DownloadItem> _downloadHls(DownloadItem dl, CancelToken cancel) async {
    final dir = await _itemDir(dl.id);

    final m3u8Resp = await _dio.get<String>(
      dl.videoUrl,
      cancelToken: cancel,
      options: Options(headers: dl.headers, responseType: ResponseType.plain),
    );
    final m3u8 = m3u8Resp.data ?? '';
    final baseUrl = _baseUrlOf(dl.videoUrl);

    String mediaPlaylist = m3u8;
    String mediaBaseUrl = baseUrl;

    if (_isMasterPlaylist(m3u8)) {
      final variantUrl = _pickVariantUrl(m3u8, baseUrl);
      if (variantUrl == null) throw Exception('No variant found in m3u8');
      final varResp = await _dio.get<String>(
        variantUrl,
        cancelToken: cancel,
        options: Options(headers: dl.headers, responseType: ResponseType.plain),
      );
      mediaPlaylist = varResp.data ?? '';
      mediaBaseUrl = _baseUrlOf(variantUrl);
    }

    final segments = _parseSegments(mediaPlaylist, mediaBaseUrl);
    if (segments.isEmpty) throw Exception('No segments in m3u8');

    final totalSegments = segments.length;
    var downloaded = 0;
    var totalBytes = 0;

    var current = dl.copyWith(
      localPath: '$dir/index.m3u8',
      totalBytes: totalSegments,
      downloadedBytes: 0,
    );
    await _save(current, force: true);

    for (var i = 0; i < segments.length; i++) {
      if (cancel.isCancelled) return current;
      final segFile = '$dir/seg_$i.ts';
      final file = File(segFile);
      if (await file.exists() && await file.length() > 0) {
        totalBytes += await file.length();
        downloaded++;
        continue;
      }
      await _dio.download(
        segments[i],
        segFile,
        cancelToken: cancel,
        options: Options(headers: dl.headers),
      );
      final size = await File(segFile).length();
      totalBytes += size;
      downloaded++;
      current = current.copyWith(
        downloadedBytes: downloaded,
        totalBytes: totalSegments,
      );
      _save(current);
    }

    final localM3u8 = _buildLocalM3u8(mediaPlaylist);
    await File('$dir/index.m3u8').writeAsString(localM3u8);

    return current.copyWith(totalBytes: totalBytes);
  }

  Future<DownloadItem> _downloadMangaChapter(
    DownloadItem dl,
    CancelToken cancel,
  ) async {
    final dir = await _itemDir(dl.id);

    var urls = dl.pageUrls;
    var headers = dl.headers;

    if (urls.isEmpty && dl.chapterRef != null) {
      final res = await getIt<GetPagesUseCase>()(
        ref: dl.chapterRef!,
        provider: dl.provider,
      );
      if (res is Success<MangaPagesEntity>) {
        urls = res.value.pages.map((p) => p.imageUrl).toList();
        headers = res.value.headers;
      }
    }

    if (urls.isEmpty) throw Exception('No pages to download');

    final total = urls.length;
    var downloaded = 0;

    var current = dl.copyWith(
      localPath: dir,
      totalBytes: total,
      downloadedBytes: 0,
    );
    await _save(current, force: true);

    for (var i = 0; i < urls.length; i++) {
      if (cancel.isCancelled) return current;
      final path =
          '$dir/p_${i.toString().padLeft(3, '0')}${_imageExtensionFrom(urls[i])}';
      final file = File(path);
      if (await file.exists() && await file.length() > 0) {
        downloaded++;
        continue;
      }
      await _dio.download(
        urls[i],
        path,
        cancelToken: cancel,
        options: Options(headers: headers),
      );
      downloaded++;
      current = current.copyWith(
        downloadedBytes: downloaded,
        totalBytes: total,
      );
      _save(current);
    }

    return current;
  }

  Future<List<MangaPageEntity>> localMangaPages(String id) async {
    final item = get(id);
    if (item == null ||
        !item.isManga ||
        item.status != DownloadStatus.completed) {
      return const [];
    }
    final dir = Directory(await _itemDir(id));
    if (!await dir.exists()) return const [];
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.startsWith('p_'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (var i = 0; i < files.length; i++)
        MangaPageEntity(index: i, imageUrl: files[i].path),
    ];
  }

  bool _isMasterPlaylist(String m3u8) {
    return m3u8.contains('#EXT-X-STREAM-INF');
  }

  String? _pickVariantUrl(String m3u8, String baseUrl) {
    final lines = m3u8.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
        for (var j = i + 1; j < lines.length; j++) {
          final line = lines[j].trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          return _resolveUrl(line, baseUrl);
        }
      }
    }
    return null;
  }

  List<String> _parseSegments(String m3u8, String baseUrl) {
    final segments = <String>[];
    for (final line in m3u8.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      segments.add(_resolveUrl(trimmed, baseUrl));
    }
    return segments;
  }

  String _buildLocalM3u8(String original) {
    final buf = StringBuffer();
    var segIdx = 0;
    for (final line in original.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        buf.writeln(trimmed);
      } else {
        buf.writeln('seg_$segIdx.ts');
        segIdx++;
      }
    }
    return buf.toString();
  }

  String _baseUrlOf(String url) {
    final lastSlash = url.lastIndexOf('/');
    return lastSlash > 0 ? url.substring(0, lastSlash + 1) : url;
  }

  String _resolveUrl(String path, String baseUrl) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) {
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}$path';
    }
    return '$baseUrl$path';
  }

  void cancelDownload(String id) {
    if (_useNativeDownloader) {
      unawaited(_native.cancelDownload(id));
    }
    // Dropped from the queue too, or cancelling something that had not started
    // would leave it waiting for a slot it no longer wants.
    _queue.removeWhere((q) => q.id == id);
    _tokens[id]?.cancel();
    _tokens.remove(id);
  }

  Future<void> remove(String id) async {
    cancelDownload(id);
    if (_useNativeDownloader) {
      await _native.removeState(id);
    }
    final dir = await _itemDir(id);
    final folder = Directory(dir);
    if (await folder.exists()) await folder.delete(recursive: true);
    await _box.delete(id);
    revision.value++;
  }

  Future<void> clearAll() async {
    _tokens.forEach((_, t) => t.cancel());
    _tokens.clear();
    if (_useNativeDownloader) {
      await _native.cancelAll();
    }
    final base = await getApplicationDocumentsDirectory();
    final dlDir = Directory('${base.path}/downloads');
    if (await dlDir.exists()) await dlDir.delete(recursive: true);
    await _box.clear();
    revision.value++;
  }

  String _extensionFrom(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '.mp4';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.mp4')) return '.mp4';
    if (path.endsWith('.mkv')) return '.mkv';
    if (path.endsWith('.ts')) return '.ts';
    return '.mp4';
  }

  String _imageExtensionFrom(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    if (path.endsWith('.gif')) return '.gif';
    return '.jpg';
  }
}

class _NativeDownloadBridge {
  static const MethodChannel _channel = MethodChannel('soplay/downloads');

  Future<bool> startDownload(DownloadItem item) async {
    final allowed =
        await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
    if (!allowed) return false;

    return await _channel.invokeMethod<bool>('startDownload', {
          'id': item.id,
          'title': item.title,
          'url': item.videoUrl,
          'localPath': item.localPath,
          'headers': item.headers,
          'kind': item.kind,
          'pageUrls': item.pageUrls,
        }) ??
        false;
  }

  Future<List<_NativeDownloadState>> getStates() async {
    final raw =
        await _channel.invokeMethod<String>('getDownloadStates') ?? '{}';
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    return decoded.values
        .whereType<Map>()
        .map((e) => _NativeDownloadState.fromJson(e))
        .toList();
  }

  Future<void> cancelDownload(String id) async {
    await _channel.invokeMethod<void>('cancelDownload', {'id': id});
  }

  Future<void> removeState(String id) async {
    await _channel.invokeMethod<void>('removeDownloadState', {'id': id});
  }

  Future<void> cancelAll() async {
    await _channel.invokeMethod<void>('cancelAllDownloads');
  }
}

class _NativeDownloadState {
  const _NativeDownloadState({
    required this.id,
    required this.status,
    required this.localPath,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final String id;
  final String status;
  final String localPath;
  final int downloadedBytes;
  final int totalBytes;

  factory _NativeDownloadState.fromJson(Map<dynamic, dynamic> json) =>
      _NativeDownloadState(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        localPath: json['localPath']?.toString() ?? '',
        downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      );
}
