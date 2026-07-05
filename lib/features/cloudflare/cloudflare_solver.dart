import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver_page.dart';

/// Opens the interactive Cloudflare solver for [provider] (a full, prefixed
/// provider id like `an:123` / `mn:123` / `cs:Name`).
///
/// Resolves the right native channel by prefix, asks it for the source's base
/// url + the exact User-Agent the OkHttp client uses, then shows a visible
/// [CloudflareSolverPage]. Returns `true` when a `cf_clearance` cookie was
/// harvested (the cookie is shared with native OkHttp automatically), `false`
/// otherwise (including when there's no resolvable base url, e.g. non-extension
/// providers or unsupported platforms).
Future<bool> requestCloudflareSolve(
  BuildContext context,
  String provider,
) async {
  // flutter_inappwebview has no Linux implementation, so the interactive solver
  // can't run there — bail out instead of crashing. (Windows/macOS/mobile OK.)
  if (Platform.isLinux) return false;
  if (provider.length < 4) return false;
  final id = provider.substring(3);

  Map<String, dynamic> info;
  if (provider.startsWith('an:')) {
    info = await AniyomiChannel.cloudflareInfo(id);
  } else if (provider.startsWith('mn:')) {
    info = await MangaChannel.cloudflareInfo(id);
  } else if (provider.startsWith('cs:')) {
    info = await CloudStreamChannel.cloudflareInfo(id);
  } else {
    return false;
  }

  final baseUrl = (info['baseUrl'] ?? '').toString();
  if (baseUrl.isEmpty) return false;
  final userAgent = (info['userAgent'] ?? '').toString();

  if (!context.mounted) return false;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => CloudflareSolverPage(
        baseUrl: baseUrl,
        userAgent: userAgent,
      ),
    ),
  );
  return result ?? false;
}

/// True when [error]'s message indicates a Cloudflare challenge — used to decide
/// whether to surface the "Solve Cloudflare" action on an error screen.
bool isCloudflareError(Object? error) {
  if (error == null) return false;
  final msg = error.toString().toLowerCase();
  return msg.contains('cloudflare') ||
      msg.contains('failed to bypass cloudflare');
}
