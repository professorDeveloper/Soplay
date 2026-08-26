// ignore_for_file: unused_element
part of 'profile_page.dart';

/// The rows of the profile list — providers, activity, connections, security,
/// settings entries, content and extensions.
class _ProvidersSection extends StatelessWidget {
  const _ProvidersSection();

  /// The provider row on its own, so the mobile CONTENT card can put it above
  /// the extension sources rather than give it a labelled card of its own.
  static Widget row() => const _ProviderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_providers'.tr()),
          _SectionCard(children: [row()]),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
            builder: (context, state) {
              final loaded = state is ProviderLoaded ? state : null;
              final currentProvider = loaded?.currentProvider;
              final currentName =
                  currentProvider?.name ?? loaded?.currentProviderId ?? '—';
              final total = loaded?.providers.length ?? 0;

              return _Tile(
                    icon: Icons.movie_filter_outlined,
                    title: 'profile.provider'.tr(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (currentProvider != null &&
                            currentProvider.image.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: currentProvider.image,
                                width: 22,
                                height: 22,
                                fit: BoxFit.cover,
                                // Holds the slot while loading so the name next
                                // to it does not slide sideways when it lands.
                                placeholder: (_, _) =>
                                    const SizedBox(width: 22, height: 22),
                                errorWidget: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            currentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (total > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '· $total',
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        const _TileChevron(),
                      ],
                    ),
                    onTap: () => context.push('/providers'),
                  );
            },
          );
  }
}

void openProviderPicker(BuildContext context, ProviderBloc bloc) {
  ProvidersPage.open(context, bloc);
}

class _WatchHistorySection extends StatefulWidget {
  const _WatchHistorySection({this.signedIn = true});

  /// Hides the rows that only work with a Sozo account.
  final bool signedIn;

  @override
  State<_WatchHistorySection> createState() => _WatchHistorySectionState();
}

class _WatchHistorySectionState extends State<_WatchHistorySection> {
  final HistoryService _historyService = getIt<HistoryService>();
  final DownloadService _downloadService = getIt<DownloadService>();
  int _historyCount = 0;
  int _downloadCount = 0;

  @override
  void initState() {
    super.initState();
    _historyService.revision.addListener(_reload);
    _downloadService.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_reload);
    _downloadService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _historyCount = _historyService.getAll().length;
      _downloadCount = _downloadService.getAll().length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_activity'.tr(),
              featureIds: const ['torrents', 'backup']),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.history_rounded,
                title: 'profile.watch_history'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_historyCount > 0)
                      Text(
                        '$_historyCount',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const _TileChevron(),
                  ],
                ),
                onTap: () => context.push('/history'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.download_rounded,
                title: 'profile.downloads'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_downloadCount > 0)
                      Text(
                        '$_downloadCount',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const _TileChevron(),
                  ],
                ),
                onTap: () => context.push('/downloads'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.notifications_active_outlined,
                title: 'tracker.title'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/following'),
              ),
              // Moved out of the home top bar, which had five permanent icons
              // and no room. Each of these is somewhere you go on purpose, and
              // this list is where the app already keeps those; leaving them
              // only in the bar was the reason the bar could not be trimmed.
              //
              // Watch Party is the one that hard-requires an account — tapping
              // it signed out only bounces to /login — so a guest is not shown
              // a door that opens onto a sign-in wall.
              if (widget.signedIn) ...[
                const _TileDivider(),
                _Tile(
                  icon: Icons.groups_rounded,
                  title: 'watch_party.title'.tr(),
                  trailing: const _TileChevron(),
                  onTap: () => showPartyEntrySheet(context),
                ),
              ],
              const _TileDivider(),
              _Tile(
                icon: Icons.track_changes_rounded,
                title: 'navigation.anilist'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/anilist'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.live_tv_rounded,
                title: 'navigation.live_tv'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/live-tv'),
              ),
              // Android only: the torrent engine is a native Android library
              // with no iOS or desktop equivalent, so on those platforms the
              // row is absent rather than present and failing.
              if (!kIsWeb && Platform.isAndroid) ...[
                const _TileDivider(),
                _Tile(
                  icon: Icons.hub_rounded,
                  title: 'torrent.title'.tr(),
                  featureId: 'torrents',
                  trailing: const _TileChevron(),
                  onTap: () => context.push('/torrents'),
                ),
              ],
              const _TileDivider(),
              _Tile(
                icon: Icons.backup_outlined,
                title: 'backup.title'.tr(),
                  featureId: 'backup',
                trailing: const _TileChevron(),
                onTap: () => BackupSheet.show(context),
              ),
              _Tile(
                icon: Icons.devices_rounded,
                title: BridgeControl.canHost
                    ? 'profile.share_sources_desktop'.tr()
                    : Platform.isIOS
                    ? 'ios.sources_title'.tr()
                    : 'profile.desktop_sources'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/desktop-share'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sits directly under the streak card: the offer to connect a tracker only
/// works if it is seen, and it was previously buried in the Activity list.
class _ConnectionsSection extends StatelessWidget {
  const _ConnectionsSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_connections'.tr()),
          _SectionCard(
          children: [
          const _ConnectionsTile(),
          const _TileDivider(),
          // Link a TV, not Live TV: the channel line-up moved to the home
          // bar, and pairing a television — a thing you genuinely connect —
          // had no entry point anywhere in the app except a deep link.
          _Tile(
          icon: Icons.cast_connected_rounded,
          title: 'link_tv.title'.tr(),
          subtitle: 'link_tv.tile_subtitle'.tr(),
          trailing: const _TileChevron(),
          onTap: () => context.push('/link-tv'),
          ),
          ],
          ),
        ],
      ),
    );
  }
}

/// The Connections row, which shows the trackers' state inline.
///
/// A tile of its own rather than a plain link: whether a tracker is connected
/// is the entire question a user opens this row to answer, and making them
/// navigate to find out defeats the point.
///
/// It speaks for BOTH trackers rather than for AniList alone. Branded as one
/// service, it read as an AniList row — so someone looking for MyAnimeList had
/// no reason to tap it and reasonably concluded the app did not support it.
/// Listens to both services so connecting elsewhere updates it without a
/// manual refresh.
class _ConnectionsTile extends StatefulWidget {
  const _ConnectionsTile();

  @override
  State<_ConnectionsTile> createState() => _ConnectionsTileState();
}

class _ConnectionsTileState extends State<_ConnectionsTile> {
  final AnilistService _anilist = getIt<AnilistService>();
  final MalService _mal = getIt<MalService>();

  @override
  void initState() {
    super.initState();
    _anilist.addListener(_onChange);
    _mal.addListener(_onChange);
  }

  @override
  void dispose() {
    _anilist.removeListener(_onChange);
    _mal.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Who is connected, in one line.
  ///
  /// Account names rather than service names: two people with both trackers
  /// linked want to see WHICH accounts, and the logos beside this already say
  /// which services. Falls back to the service name when a link carries no
  /// username yet.
  String _subtitle() {
    final names = <String>[
      if (_anilist.isConnected)
        (_anilist.viewer?.name.trim().isNotEmpty ?? false)
            ? _anilist.viewer!.name.trim()
            : 'AniList',
      if (_mal.isConnected)
        (_mal.viewer?.name.trim().isNotEmpty ?? false)
            ? _mal.viewer!.name.trim()
            : 'MyAnimeList',
    ];
    return names.isEmpty ? 'anilist.connect_tagline'.tr() : names.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final anyConnected = _anilist.isConnected || _mal.isConnected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/connections'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: Row(
            children: [
              // Both marks, so the row names what it actually offers. Dimmed
              // when that tracker is not connected, so the pair doubles as a
              // status readout at a glance.
              _TrackerMark(
                connected: _anilist.isConnected,
                child: const AnilistLogo(size: 28, radius: 8),
              ),
              const SizedBox(width: 7),
              _TrackerMark(
                connected: _mal.isConnected,
                child: const MalLogo(size: 28, radius: 8),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'anilist.connections_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: anyConnected ? kAnilistBlue : AppColors.textHint,
                        fontSize: 12.5,
                        fontWeight:
                            anyConnected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (!anyConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kAnilistBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'anilist.connect_short'.tr(),
                    style: const TextStyle(
                      color: kAnilistBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const _TileChevron(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tracker logo, dimmed while that tracker is not connected.
class _TrackerMark extends StatelessWidget {
  const _TrackerMark({required this.connected, required this.child});

  final bool connected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: connected ? 1 : 0.38,
        child: child,
      );
}

class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('app_lock.section_label'.tr()),
          _SectionCard(children: [_SecurityRows()]),
        ],
      ),
    );
  }
}

/// App lock + private list, as two bare rows.
///
/// Split out of [_SecuritySection] so the mobile SETTINGS card can hold them
/// next to Appearance and Player — where they belong — while desktop keeps its
/// own "Security" panel.
class _SecurityRows extends StatefulWidget {
  const _SecurityRows();

  @override
  State<_SecurityRows> createState() => _SecurityRowsState();
}

class _SecurityRowsState extends State<_SecurityRows> {
  late final AppLockRepository _lock = getIt<AppLockRepository>();

  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    return Column(
            children: [
              _Tile(
                icon: Icons.lock_rounded,
                title: 'app_lock.app_lock'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enabled
                          ? 'app_lock.state_on'.tr()
                          : 'app_lock.state_off'.tr(),
                      style: TextStyle(
                        color: enabled
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const _TileChevron(),
                  ],
                ),
                onTap: () async {
                  await context.push('/app-lock-settings');
                  if (mounted) setState(() {});
                },
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.folder_special_rounded,
                title: 'app_lock.private_list'.tr(),
                trailing: const _TileChevron(),
                onTap: () async {
                  final unlocked = await requestPrivateUnlock(context);
                  if (unlocked && context.mounted) {
                    context.push('/private-list');
                  }
                },
              ),
            ],
          );
  }
}

class _SettingsEntriesSection extends StatelessWidget {
  const _SettingsEntriesSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_settings'.tr(),
              featureIds: const ['change_source']),
          _SectionCard(
          children: [
          _Tile(
          icon: Icons.palette_outlined,
          title: 'appearance.title'.tr(),
          subtitle: 'appearance.entry_subtitle'.tr(),
          trailing: const _AccentDotChevron(),
          onTap: () => context.push('/appearance'),
          ),
          const _TileDivider(),
          _Tile(
          icon: Icons.view_week_rounded,
          title: 'profile.nav_style'.tr(),
          trailing: const _TileChevron(),
          onTap: () => context.push('/navbar'),
          ),
          const _TileDivider(),
          _Tile(
          icon: Icons.play_circle_outline_rounded,
          title: 'profile.section_player'.tr(),
          featureId: 'change_source',
          trailing: const _TileChevron(),
          onTap: () => context.push('/player-settings'),
          ),
          const _TileDivider(),
          const _SecurityRows(),
          ],
          ),
        ],
      ),
    );
  }
}

/// Where the content comes from: the active provider, and — folded away behind
/// one row — the installable extension ecosystems.
///
/// These were two labelled cards and five rows. Four of those rows were
/// extension stores most people open once and never again, so they are collapsed
/// by default; the row still says how many there are, and opens them in place.
class _ContentSection extends StatefulWidget {
  const _ContentSection();

  @override
  State<_ContentSection> createState() => _ContentSectionState();
}

class _ContentSectionState extends State<_ContentSection> {
  bool _sourcesOpen = false;

  @override
  Widget build(BuildContext context) {
    final sources = _ExtensionSourcesSection.rowsFor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_content'.tr()),
          _SectionCard(
          children: [
          _ProvidersSection.row(),
          if (sources.isNotEmpty) ...[
          const _TileDivider(),
          _Tile(
          icon: Icons.extension_outlined,
          title: 'profile.sources_row'.tr(),
          subtitle: 'profile.sources_row_subtitle'.tr(),
          trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          Text(
          '${sources.length}',
          style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          ),
          ),
          const SizedBox(width: 6),
          AnimatedRotation(
          turns: _sourcesOpen ? 0.25 : 0,
          duration: const Duration(milliseconds: 200),
          child: const _TileChevron(),
          ),
          ],
          ),
          onTap: () => setState(() => _sourcesOpen = !_sourcesOpen),
          ),
          // AnimatedSize rather than a route: the stores are one tap
          // away either way, and expanding in place keeps the user's
          // place on a long page.
          AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _sourcesOpen
          ? Column(
          children: [
          for (final row in sources) ...[
          const _TileDivider(),
          row,
          ],
          ],
          )
          : const SizedBox(width: double.infinity),
          ),
          ],
          ],
          ),
        ],
      ),
    );
  }
}

class _ExtensionSourcesSection extends StatelessWidget {
  const _ExtensionSourcesSection();

  /// The rows themselves, so the mobile CONTENT card can host them behind an
  /// expander instead of standing up a fifth labelled card of its own.
  static List<Widget> rowsFor(BuildContext context) => <Widget>[
      // First, and ungated: this is the row that answers "what is there in my
      // language", and the four below it are the per-ecosystem repo managers it
      // saves a user from opening one at a time. It works on every platform
      // because the catalog is read from the backend — what it can OFFER still
      // depends on what this platform runs, and the page says which is which.
      _Tile(
        icon: Icons.translate_rounded,
        title: 'catalog.title'.tr(),
        subtitle: 'catalog.subtitle'.tr(),
        trailing: const _TileChevron(),
        onTap: () => SourceCatalogPage.open(context),
      ),
      if (BridgeControl.canHost && CloudStreamChannel.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s',
            fallback: Icons.extension_outlined,
          ),
          title: 'profile.cloudstream_sources'.tr(),
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CloudStreamSourcesPage()),
          ),
        ),
      if (BridgeControl.canHost && AniyomiChannel.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
            fallback: Icons.play_circle_outline,
          ),
          title: 'profile.aniyomi_sources'.tr(),
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AniyomiSourcesPage())),
        ),
      if (BridgeControl.canHost && MangaChannel.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
            fallback: Icons.menu_book_outlined,
          ),
          title: 'manga.sources_title'.tr(),
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const MangaSourcesPage())),
        ),
      // Not gated on BridgeControl.canHost / a platform channel: these
      // extensions are JavaScript, so this entry is valid on iOS, macOS and
      // Windows as well as Android — the only extension ecosystem that is.
      if (MangayomiRuntime.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png',
            fallback: Icons.javascript_outlined,
          ),
          title: 'Mangayomi Sources',
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MangayomiSourcesPage()),
          ),
        ),
    ];

  @override
  Widget build(BuildContext context) {
    final rows = rowsFor(context);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_extensions'.tr()),
          _SectionCard(
          children: [
          for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const _TileDivider(),
          rows[i],
          ],
          ],
          ),
        ],
      ),
    );
  }
}

/// Remote logo in the leading slot. Shows the plain icon chip while loading and
/// if the load fails, so the row never has a hole where its mark should be.
