/// The signed-in MyAnimeList account.
class MalViewer {
  const MalViewer({required this.id, required this.name, this.avatarUrl});

  final int id;
  final String name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarUrl': avatarUrl,
      };

  factory MalViewer.fromJson(Map<String, dynamic> j) => MalViewer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        avatarUrl: j['avatarUrl'] as String?,
      );
}

/// Where the account currently stands on one anime.
///
/// [totalEpisodes] comes from the anime itself rather than from the list entry,
/// and is what lets the tracker decide that an episode finishes a show.
class MalEntryState {
  const MalEntryState({
    required this.watchedEpisodes,
    this.status,
    this.totalEpisodes,
    this.isRewatching = false,
  });

  /// `my_list_status.num_episodes_watched`.
  final int watchedEpisodes;

  /// One of [MalStatus]. Null when the anime is not on the list at all.
  final String? status;

  final int? totalEpisodes;

  /// MAL models a rewatch as a FLAG on a completed entry, not as a status of
  /// its own — so it is read here and never written back. Sending a status
  /// during a rewatch would knock the entry out of `completed`.
  final bool isRewatching;

  /// True when the entry is not on the list yet.
  bool get isNew => status == null;

  factory MalEntryState.fromAnime(Map<String, dynamic> anime) {
    final listStatus =
        (anime['my_list_status'] as Map?)?.cast<String, dynamic>();
    final total = (anime['num_episodes'] as num?)?.toInt();
    return MalEntryState(
      watchedEpisodes:
          (listStatus?['num_episodes_watched'] as num?)?.toInt() ?? 0,
      status: listStatus?['status'] as String?,
      totalEpisodes: (total != null && total > 0) ? total : null,
      isRewatching: listStatus?['is_rewatching'] == true,
    );
  }
}

/// One search hit, reduced to what a match needs.
class MalAnime {
  const MalAnime({
    required this.id,
    required this.title,
    this.alternativeTitles = const [],
    this.picture,
    this.episodes,
  });

  final int id;
  final String title;
  final List<String> alternativeTitles;
  final String? picture;
  final int? episodes;

  /// Every name worth matching against a source title, best guess first and no
  /// blanks or duplicates.
  List<String> get searchTitles {
    final out = <String>[];
    for (final t in [title, ...alternativeTitles]) {
      final v = t.trim();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    return out;
  }

  factory MalAnime.fromJson(Map<String, dynamic> j) {
    final alt = (j['alternative_titles'] as Map?)?.cast<String, dynamic>();
    final synonyms = (alt?['synonyms'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final episodes = (j['num_episodes'] as num?)?.toInt();
    return MalAnime(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      alternativeTitles: [
        if (alt?['en'] is String) alt!['en'] as String,
        if (alt?['ja'] is String) alt!['ja'] as String,
        ...synonyms,
      ],
      picture: (j['main_picture'] as Map?)?['medium'] as String? ??
          (j['main_picture'] as Map?)?['large'] as String?,
      episodes: (episodes != null && episodes > 0) ? episodes : null,
    );
  }
}
