import 'manga_page_entity.dart';

class MangaPagesEntity {
  final List<MangaPageEntity> pages;
  final Map<String, String> headers;

  const MangaPagesEntity({required this.pages, required this.headers});
}
