import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/tracker/presentation/pages/tracker_links_page.dart';

/// The MyAnimeList side of [TrackerLinksPage].
///
/// Worth having even though MAL's rows are matched automatically: an automatic
/// match is exactly the kind that can be wrong, and this is the only place a
/// wrong one can be seen and undone.
class MalLinksPage extends StatelessWidget {
  const MalLinksPage({super.key});

  @override
  Widget build(BuildContext context) => TrackerLinksPage(
        store: getIt<MalLinkStore>(),
        title: 'mal.linked_titles'.tr(),
        accent: kMalBlue,
      );
}
