import '../../domain/entities/manga_page_entity.dart';
import '../../domain/entities/manga_pages_entity.dart';

class MangaPagesModel extends MangaPagesEntity {
  const MangaPagesModel({required super.pages, required super.headers});

  factory MangaPagesModel.fromJson(Map<String, dynamic> json) {
    final pages = <MangaPageEntity>[];
    final rawPages = json['pages'];
    if (rawPages is List) {
      for (final e in rawPages) {
        if (e is! Map) continue;
        final img = (e['imageUrl'] as String?) ?? '';
        if (img.isEmpty) continue;
        pages.add(MangaPageEntity(
          index: (e['index'] as num?)?.toInt() ?? pages.length,
          imageUrl: img,
        ));
      }
    }
    final headers = <String, String>{};
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (v != null) headers[k.toString()] = v.toString();
      });
    }
    return MangaPagesModel(pages: pages, headers: headers);
  }
}
