import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/features/app_lock/presentation/pages/app_lock_settings_page.dart';
import 'package:soplay/features/app_lock/presentation/pages/pin_setup_page.dart';
import 'package:soplay/features/app_lock/presentation/pages/pin_verify_page.dart';
import 'package:soplay/features/desktop_share/presentation/pages/desktop_share_page.dart';
import 'package:soplay/features/auth/presentation/pages/login_page.dart';
import 'package:soplay/features/auth/presentation/pages/otp_verify_page.dart';
import 'package:soplay/features/auth/presentation/pages/register_page.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/pages/actor_page.dart';
import 'package:soplay/features/detail/presentation/pages/detail_page.dart';
import 'package:soplay/features/detail/presentation/pages/episodes_page.dart';
import 'package:soplay/features/detail/presentation/pages/player_page.dart';
import 'package:soplay/features/download/presentation/pages/downloads_page.dart';
import 'package:soplay/features/history/presentation/pages/history_page.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/presentation/pages/reader_page.dart';
import 'package:soplay/features/main/presentation/pages/main_page.dart';
import 'package:soplay/features/network/presentation/pages/no_internet_page.dart';
import 'package:soplay/features/notifications/presentation/pages/notifications_page.dart';
import 'package:soplay/features/private_list/presentation/pages/private_list_page.dart';
import 'package:soplay/features/splash/presentation/pages/splash_page.dart';
import 'package:soplay/features/streak/presentation/pages/streak_page.dart';

import '../../features/home/presentation/pages/home_view_all_page.dart';

class AppRouter {
  AppRouter._();

  static bool dismissTopmost() {
    final nav = router.routerDelegate.navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
      return true;
    }
    return false;
  }

  static final router = GoRouter(
    initialLocation: '/splash',
    observers: Platform.isAndroid
        ? [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
        : [],
    routes: [
      GoRoute(
        path: '/view-all',
        builder: (context, state) {
          final args = state.extra as ViewAllEntity;
          final slug = args.slug;
          final title = args.name.isNotEmpty
              ? args.name
              : (slug.isEmpty ? args.type : slug);
          return HomeViewAllPage(
            keyCat: args.type,
            slug: args.slug,
            title: title,
          );
        },
      ),
      GoRoute(
        path: '/detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is DetailArgs) return DetailPage(args: extra);
          final q = state.uri.queryParameters;
          final url = q['url'] ?? '';
          final provider = q['provider']?.trim();
          return DetailPage(
            args: DetailArgs(
              contentUrl: url,
              provider: provider != null && provider.isNotEmpty
                  ? provider
                  : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/episodes',
        builder: (context, state) {
          final args = state.extra as EpisodesArgs;
          return EpisodesPage(args: args);
        },
      ),
      GoRoute(
        path: '/actor',
        builder: (context, state) {
          final args = state.extra as ActorArgs;
          return ActorPage(args: args);
        },
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final args = state.extra as PlayerArgs;
          return PlayerPage(args: args);
        },
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final args = state.extra as ReaderArgs;
          return ReaderPage(args: args);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryPage(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadsPage(),
      ),
      GoRoute(
        path: '/desktop-share',
        builder: (context, state) => const DesktopSharePage(),
      ),
      GoRoute(
        path: '/no-internet',
        builder: (context, state) => const NoInternetPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/streak',
        builder: (context, state) => const StreakPage(),
      ),
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/main', builder: (context, state) => const MainPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return OtpVerifyPage(email: email);
        },
      ),
      GoRoute(
        path: '/pin-verify',
        builder: (context, state) {
          final redirect = state.uri.queryParameters['redirect'] ?? '/main';
          return PinVerifyPage(redirectTo: redirect);
        },
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (context, state) {
          final change = state.extra == true;
          return PinSetupPage(changeMode: change);
        },
      ),
      GoRoute(
        path: '/app-lock-settings',
        builder: (context, state) => const AppLockSettingsPage(),
      ),
      GoRoute(
        path: '/private-list',
        builder: (context, state) => const PrivateListPage(),
      ),
    ],
  );
}
