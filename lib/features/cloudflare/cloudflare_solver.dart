import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver_page.dart';

Future<bool> requestCloudflareSolve(
  BuildContext context,
  String provider,
) async {
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

bool isCloudflareError(Object? error) {
  if (error == null) return false;
  final msg = error.toString().toLowerCase();
  return msg.contains('cloudflare') ||
      msg.contains('failed to bypass cloudflare');
}
