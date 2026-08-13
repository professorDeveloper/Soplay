/// The user-curated lists the backend exposes at `/auth/lists/<slug>`.
///
/// One enum drives every layer (data source, repository, UI tabs) so adding a
/// third list is a single entry here plus a registry line on the server — never
/// a parallel copy of the feature. [slug] MUST match the server's registry in
/// `authService.USER_LISTS`.
enum UserListKind {
  watchLater('watch-later', 'Watch Later'),
  watched('watched', 'Watched');

  const UserListKind(this.slug, this.label);

  /// URL segment — the server validates this and 400s on anything unknown.
  final String slug;

  /// Human label for tabs and buttons.
  final String label;
}
