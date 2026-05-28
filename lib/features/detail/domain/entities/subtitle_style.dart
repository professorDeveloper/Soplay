import 'dart:convert';

enum SubtitleEdge { none, shadow, outline }

enum SubtitlePosition { lower, normal, higher }

class SubtitleStyle {
  const SubtitleStyle({
    required this.fontSize,
    required this.textColor,
    required this.bgOpacity,
    required this.bold,
    required this.edge,
    required this.position,
  });

  factory SubtitleStyle.defaults() => const SubtitleStyle(
        fontSize: 16,
        textColor: 0xFFFFFFFF,
        bgOpacity: 0.75,
        bold: true,
        edge: SubtitleEdge.shadow,
        position: SubtitlePosition.normal,
      );

  factory SubtitleStyle.fromJsonString(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SubtitleStyle(
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16,
        textColor: (map['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        bgOpacity: (map['bgOpacity'] as num?)?.toDouble() ?? 0.75,
        bold: map['bold'] as bool? ?? true,
        edge: SubtitleEdge.values[(map['edge'] as num?)?.toInt() ?? 1],
        position:
            SubtitlePosition.values[(map['position'] as num?)?.toInt() ?? 1],
      );
    } catch (_) {
      return SubtitleStyle.defaults();
    }
  }

  final double fontSize;
  final int textColor;
  final double bgOpacity;
  final bool bold;
  final SubtitleEdge edge;
  final SubtitlePosition position;

  SubtitleStyle copyWith({
    double? fontSize,
    int? textColor,
    double? bgOpacity,
    bool? bold,
    SubtitleEdge? edge,
    SubtitlePosition? position,
  }) {
    return SubtitleStyle(
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      bgOpacity: bgOpacity ?? this.bgOpacity,
      bold: bold ?? this.bold,
      edge: edge ?? this.edge,
      position: position ?? this.position,
    );
  }

  String toJsonString() => jsonEncode({
        'fontSize': fontSize,
        'textColor': textColor,
        'bgOpacity': bgOpacity,
        'bold': bold,
        'edge': edge.index,
        'position': position.index,
      });
}
