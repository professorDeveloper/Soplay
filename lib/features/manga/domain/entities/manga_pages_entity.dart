import 'manga_page_entity.dart';

/// A resolved chapter: its ordered image pages plus the HTTP headers
/// (referer / user-agent) that must be applied to every image request.
class MangaPagesEntity {
  final List<MangaPageEntity> pages;
  final Map<String, String> headers;

  const MangaPagesEntity({required this.pages, required this.headers});
}
