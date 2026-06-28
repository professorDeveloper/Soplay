/// A single readable page of a manga chapter.
class MangaPageEntity {
  /// 0-based order within the chapter.
  final int index;

  /// Direct image URL (already resolved by the native source).
  final String imageUrl;

  const MangaPageEntity({required this.index, required this.imageUrl});
}
