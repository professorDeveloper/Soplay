import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/splash/presentation/widgets/netflix_splash.dart';

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
    } else {
      context.go('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return NetflixSplash(onComplete: _onComplete);
  }
}
