import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/system/desktop_window.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/home/presentation/bloc/home/home_bloc.dart';

/// Desktop scroll behaviour: adds mouse + trackpad + stylus as drag devices so
/// touch-oriented scrollables (PageView, horizontal ListViews) can be dragged
/// with a pointer, and keeps a visible scrollbar.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    getIt<NotificationService>().onTap = _handlePushTap;
    // Desktop: hide the custom title-bar strip on the immersive full-bleed
    // routes (player / reader) by watching the router itself — reliable
    // regardless of a page's initState timing.
    if (isDesktopPlatform) {
      AppRouter.router.routerDelegate.addListener(_syncImmersive);
      _syncImmersive();
    }
  }

  /// Set [DesktopWindow.immersive] from the current top-of-stack route.
  void _syncImmersive() {
    try {
      final path =
          AppRouter.router.routerDelegate.currentConfiguration.uri.path;
      DesktopWindow.immersive.value = path == '/player' || path == '/reader';
    } catch (_) {}
  }

  @override
  void dispose() {
    if (isDesktopPlatform) {
      AppRouter.router.routerDelegate.removeListener(_syncImmersive);
    }
    getIt<NotificationService>().onTap = null;
    super.dispose();
  }

  void _handlePushTap(Map<String, dynamic> data) {
    final router = AppRouter.router;
    final type = data['type']?.toString() ?? '';
    final contentUrl = data['contentUrl']?.toString();
    final provider = data['provider']?.toString();

    switch (type) {
      case 'system_comment_reply':
      case 'system_comment_like':
        if (contentUrl != null && contentUrl.isNotEmpty) {
          router.push(
            '/detail',
            extra: DetailArgs(contentUrl: contentUrl, provider: provider),
          );
        } else {
          router.push('/notifications');
        }
      case 'system_ban':
        getIt<AuthBloc>().add(AuthSessionExpired());
        router.go('/login');
      case 'system_unban':
      case 'admin_broadcast':
      case 'admin_direct':
        router.push('/notifications');
      case 'streak_risk':
        getIt<NavController>().goTo(4);
      default:
        router.push('/notifications');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: getIt<AuthBloc>()),
        BlocProvider<ViewAllBloc>(create: (_) => getIt<ViewAllBloc>()),
        BlocProvider<HomeBloc>(create: (_) => getIt<HomeBloc>()),
        BlocProvider<SearchBloc>(create: (_) => getIt<SearchBloc>()),
        BlocProvider<ProviderBloc>(
          create: (_) => getIt<ProviderBloc>()..add(const ProviderLoad()),
        ),
      ],
      child: MaterialApp.router(
        title: 'app_name'.tr(),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        // Desktop: let horizontal rows / carousels / the Shorts feed be dragged
        // with a mouse & trackpad. Mobile keeps Flutter's default behaviour.
        scrollBehavior: isDesktopPlatform ? const _DesktopScrollBehavior() : null,
        routerConfig: AppRouter.router,
        // Desktop: a custom frameless title bar + Esc-to-dismiss (closes the
        // topmost dialog/sheet, else pops the page). Mobile returns the child
        // unchanged.
        builder: (context, child) {
          final app = child ?? const SizedBox.shrink();
          if (!isDesktopPlatform) return app;
          final shell = Column(
            children: [
              const WindowTitleBar(),
              Expanded(child: app),
            ],
          );
          return CallbackShortcuts(
            bindings: {
              // Dismiss the topmost route on the real Navigator — a dialog/sheet
              // if one is open, otherwise the page. (GoRouter.pop() ignores
              // imperative overlays and would pop the page under a dialog.)
              const SingleActivator(LogicalKeyboardKey.escape):
                  AppRouter.dismissTopmost,
            },
            child: Focus(autofocus: true, child: shell),
          );
        },
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
      ),
    );
  }
}
