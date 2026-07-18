import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_state.dart';
import 'package:soplay/features/trivia/presentation/widgets/popular_cast_grid.dart';

/// Fan-Test entry surface: a pinned glass search bar over a "Popular now" grid
/// that becomes debounced as-you-type results. Tapping a card flies its photo
/// into the Actor Hero screen. Only live actors (kind 'person') are surfaced.
class CastPickerPage extends StatelessWidget {
  const CastPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CastBloc>(
      create: (_) => getIt<CastBloc>()..add(const CastStarted()),
      child: const _CastPickerView(),
    );
  }
}

class _CastPickerView extends StatefulWidget {
  const _CastPickerView();

  @override
  State<_CastPickerView> createState() => _CastPickerViewState();
}

class _CastPickerViewState extends State<_CastPickerView> {
  final TextEditingController _controller = TextEditingController();

  /// Search field (48) + gap (10) + caption, plus the header's own 10/12
  /// vertical padding. Excludes the top safe area, which is added separately.
  static const double _headerHeight = 98;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openActor(CastPersonEntity person) {
    context.push('/trivia/actor', extra: person);
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.paddingOf(context).top;
    final contentTop = topSafe + _headerHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: BlocBuilder<CastBloc, CastState>(
              builder: (context, state) => _Body(
                state: state,
                topPadding: contentTop,
                onTapPerson: _openActor,
              ),
            ),
          ),
          _GlassHeader(
            topSafe: topSafe,
            controller: _controller,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.topPadding,
    required this.onTapPerson,
  });

  final CastState state;
  final double topPadding;
  final void Function(CastPersonEntity) onTapPerson;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(16, topPadding, 16, 28);
    final searching = state.isSearchActive;

    switch (state.status) {
      case CastStatus.initial:
      case CastStatus.loadingPopular:
      case CastStatus.searching:
        return CastGridSkeleton(padding: padding);

      case CastStatus.error:
        return _CenteredNotice(
          topPadding: topPadding,
          icon: CupertinoIcons.wifi_slash,
          title: 'trivia.something_wrong'.tr(),
          subtitle: state.message,
          onRetry: () {
            final bloc = context.read<CastBloc>();
            if (searching) {
              bloc.add(CastQueryChanged(state.query));
            } else {
              bloc.add(const CastStarted());
            }
          },
        );

      case CastStatus.empty:
        return _CenteredNotice(
          topPadding: topPadding,
          icon: CupertinoIcons.search,
          title: 'trivia.no_results'.tr(),
          subtitle: 'trivia.no_results_hint'.tr(),
        );

      case CastStatus.popular:
        return PopularCastGrid(
          people: state.popular,
          onTapPerson: onTapPerson,
          padding: padding,
        );

      case CastStatus.results:
        return PopularCastGrid(
          people: state.results,
          highlight: state.query,
          onTapPerson: onTapPerson,
          padding: padding,
        );
    }
  }
}

/// The pinned, frosted search header floating over the grid.
class _GlassHeader extends StatelessWidget {
  const _GlassHeader({required this.topSafe, required this.controller});

  final double topSafe;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, topSafe + 10, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.92),
                  AppColors.background.withValues(alpha: 0.55),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchField(controller: controller),
                const SizedBox(height: 10),
                const _ContextCaption(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CastBloc, CastState>(
      buildWhen: (a, b) => a.query.isEmpty != b.query.isEmpty,
      builder: (context, state) {
        final hasText = state.query.isNotEmpty;
        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.search,
                color: AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  cursorColor: AppColors.primary,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'trivia.search_cast_hint'.tr(),
                    hintStyle: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 15,
                    ),
                  ),
                  onChanged: (v) =>
                      context.read<CastBloc>().add(CastQueryChanged(v)),
                ),
              ),
              if (hasText)
                GestureDetector(
                  onTap: () {
                    controller.clear();
                    context.read<CastBloc>().add(const CastCleared());
                    FocusScope.of(context).unfocus();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      CupertinoIcons.clear_circled_solid,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

class _ContextCaption extends StatelessWidget {
  const _ContextCaption();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CastBloc, CastState>(
      buildWhen: (a, b) =>
          a.isSearchActive != b.isSearchActive || a.status != b.status,
      builder: (context, state) {
        final String text;
        if (!state.isSearchActive) {
          text = 'trivia.popular_now'.tr();
        } else if (state.status == CastStatus.results) {
          text = 'trivia.results'.tr();
        } else {
          text = 'trivia.searching'.tr();
        }
        return Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        );
      },
    );
  }
}

class _CenteredNotice extends StatelessWidget {
  const _CenteredNotice({
    required this.topPadding,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
  });

  final double topPadding;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding + 40, left: 32, right: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textHint, size: 46),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryLight,
              ),
              child: Text('general.retry'.tr()),
            ),
          ],
        ],
      ),
    );
  }
}
