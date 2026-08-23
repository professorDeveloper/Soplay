import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/splash/presentation/widgets/netflix_splash.dart';

/// Temporary: send every launch to the onboarding, signed in or not, so the
/// screen can be looked at without clearing the session each time.
///
/// Set back to `false` to restore the shipping behaviour — onboarding as the
/// signed-out landing screen only.
const bool kAlwaysShowOnboarding = true;

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  void _onComplete() {
    unawaited(_resolveRoute());
  }

  Future<void> _resolveRoute() async {
    final lock = getIt<AppLockRepository>();
    await lock.ensureConsistent();
    if (!mounted) return;
    if (lock.isEnabled) {
      context.go('/pin-verify?redirect=/main');
      return;
    }
    // Shown on every launch, not just the first: while nobody is signed in it
    // IS the landing screen — the place the app says what it is and offers the
    // two ways in. A signed-in device skips it and goes straight to the app.
    // A device with a PIN has been used before, so the question only arises on
    // the branch with no lock to unlock.
    if (kAlwaysShowOnboarding ||
        (getIt<HiveService>().getToken() ?? '').isEmpty) {
      context.go('/onboarding');
      return;
    }
    context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    return NetflixSplash(onComplete: _onComplete);
  }
}
