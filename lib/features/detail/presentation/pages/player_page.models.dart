part of 'player_page.dart';

enum _PlayerFit { contain, cover, fill }

enum _SidePanel { none, episodes, quality }

enum _LoadingStage { resolving, loading }

enum _SwipeType { brightness, volume }

class _SwipeIndicator {
  final _SwipeType type;
  final double value;
  const _SwipeIndicator(this.type, this.value);
}

const _kSubLang = 'sub';
const _kDubLang = 'dub';

const List<int> _subtitleColorPresets = <int>[
  0xFFFFFFFF,
  0xFFFFEB3B,
  0xFF00E5FF,
  0xFF76FF03,
  0xFFFF80AB,
  0xFFFF5252,
];

const MethodChannel _pipChannel = MethodChannel('soplay/pip');
const MethodChannel _systemControlsChannel = MethodChannel(
  'soplay/system_controls',
);
const double _scrubSecondsPerFullSwipe = 90;

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

class _ScrubState {
  final Duration baseline;
  final Duration duration;
  final double deltaPx;
  final double span;

  const _ScrubState({
    required this.baseline,
    required this.duration,
    required this.deltaPx,
    required this.span,
  });

  _ScrubState copyWith({double? deltaPx, double? span}) => _ScrubState(
    baseline: baseline,
    duration: duration,
    deltaPx: deltaPx ?? this.deltaPx,
    span: span ?? this.span,
  );

  Duration previewPosition(double secondsPerFullSwipe) {
    if (span <= 0 || duration.inMilliseconds <= 0) return baseline;
    final fraction = (deltaPx / span).clamp(-1.0, 1.0);
    final deltaMs = (fraction * secondsPerFullSwipe * 1000).round();
    final target = baseline.inMilliseconds + deltaMs;
    final clamped = target.clamp(0, duration.inMilliseconds);
    return Duration(milliseconds: clamped);
  }
}

class _VttThumbnail {
  final Duration start;
  final Duration end;
  final String imageUrl;
  final int x;
  final int y;
  final int w;
  final int h;

  const _VttThumbnail({
    required this.start,
    required this.end,
    required this.imageUrl,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
  });

  bool get hasSprite => w > 0 && h > 0;

  bool contains(Duration position) =>
      position >= start && position < end;

  static List<_VttThumbnail> parse(String vttBody, String baseUrl) {
    final lines = vttBody.split('\n').map((l) => l.trim()).toList();
    final results = <_VttThumbnail>[];
    final timePattern = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})',
    );

    for (var i = 0; i < lines.length; i++) {
      final match = timePattern.firstMatch(lines[i]);
      if (match == null) continue;

      final start = Duration(
        hours: int.parse(match.group(1)!),
        minutes: int.parse(match.group(2)!),
        seconds: int.parse(match.group(3)!),
        milliseconds: int.parse(match.group(4)!),
      );
      final end = Duration(
        hours: int.parse(match.group(5)!),
        minutes: int.parse(match.group(6)!),
        seconds: int.parse(match.group(7)!),
        milliseconds: int.parse(match.group(8)!),
      );

      String? imageRef;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].isNotEmpty) {
          imageRef = lines[j];
          break;
        }
      }
      if (imageRef == null) continue;

      var url = imageRef;
      var x = 0, y = 0, w = 0, h = 0;
      final hashIdx = imageRef.indexOf('#xywh=');
      if (hashIdx >= 0) {
        url = imageRef.substring(0, hashIdx);
        final coords = imageRef.substring(hashIdx + 6).split(',');
        if (coords.length == 4) {
          x = int.tryParse(coords[0]) ?? 0;
          y = int.tryParse(coords[1]) ?? 0;
          w = int.tryParse(coords[2]) ?? 0;
          h = int.tryParse(coords[3]) ?? 0;
        }
      }

      if (!url.startsWith('http')) {
        final baseUri = Uri.parse(baseUrl);
        url = baseUri.resolve(url).toString();
      }

      results.add(_VttThumbnail(
        start: start,
        end: end,
        imageUrl: url,
        x: x,
        y: y,
        w: w,
        h: h,
      ));
    }
    return results;
  }
}

class _ProxiedTarget {
  const _ProxiedTarget({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
}
