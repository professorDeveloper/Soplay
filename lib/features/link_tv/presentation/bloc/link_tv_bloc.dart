import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:riasdxd/core/error/result.dart';

import '../../domain/entities/linked_device.dart';
import '../../domain/link_tv_failure.dart';
import '../../domain/repositories/link_tv_repository.dart';

part 'link_tv_event.dart';
part 'link_tv_state.dart';

/// The phone side of the TV pairing: approve one code, then keep the list of
/// linked devices honest.
class LinkTvBloc extends Bloc<LinkTvEvent, LinkTvState> {
  final LinkTvRepository repository;

  LinkTvBloc({required this.repository}) : super(const LinkTvState()) {
    on<LinkTvCodeChanged>(_onCodeChanged);
    on<LinkTvApprove>(_onApprove);
    on<LinkTvDevicesRequested>(_onDevicesRequested);
    on<LinkTvUnlinkRequested>(_onUnlinkRequested);
  }

  void _onCodeChanged(LinkTvCodeChanged event, Emitter<LinkTvState> emit) {
    emit(state.copyWith(code: normalizeCode(event.code), clearError: true));
  }

  Future<void> _onApprove(LinkTvApprove event, Emitter<LinkTvState> emit) async {
    final code = normalizeCode(event.code ?? state.code);
    if (code.length != codeLength) {
      emit(state.copyWith(code: code, errorKey: 'link_tv.error_bad_code'));
      return;
    }
    // Guard the whole approval, not just the button: the scanner fires on every
    // decoded frame, so without this one QR in view would post the same code
    // several times a second.
    if (state.submitting) return;

    emit(state.copyWith(code: code, submitting: true, clearError: true));
    final result = await repository.approve(code);
    switch (result) {
      case Success(:final value):
        emit(state.copyWith(
          submitting: false,
          approvedDeviceName: value,
          approved: true,
        ));
        add(const LinkTvDevicesRequested());
      case Failure(:final error):
        emit(state.withError(error));
    }
  }

  Future<void> _onDevicesRequested(
    LinkTvDevicesRequested event,
    Emitter<LinkTvState> emit,
  ) async {
    emit(state.copyWith(loadingDevices: true));
    final result = await repository.listDevices();
    switch (result) {
      case Success(:final value):
        emit(state.copyWith(loadingDevices: false, devices: value));
      case Failure():
        // A failed list is not worth an error banner over a successful pairing —
        // the pull-to-refresh on the page is the recovery path.
        emit(state.copyWith(loadingDevices: false));
    }
  }

  Future<void> _onUnlinkRequested(
    LinkTvUnlinkRequested event,
    Emitter<LinkTvState> emit,
  ) async {
    emit(state.copyWith(unlinkingId: event.id, clearError: true));
    final result = await repository.unlinkDevice(event.id);
    switch (result) {
      case Success():
        emit(state.copyWith(
          clearUnlinkingId: true,
          devices: state.devices.where((d) => d.id != event.id).toList(),
        ));
      case Failure(:final error):
        emit(state.withError(error));
    }
  }

  static const int codeLength = 8;

  /// A scanned URL, a pasted code and a hand-typed one all arrive in the same shape.
  ///
  /// Only separators are stripped. The server's alphabet drops I, O, 0 and 1 so the
  /// code survives being read off a TV, but a mistyped 0 is left in rather than
  /// silently deleted — a rejected code is clearer than a code that lost a character.
  static String normalizeCode(String raw) {
    final upper = raw.trim().toUpperCase();
    // A scanned QR carries https://sozo.azamov.me/link/<CODE>; take the last segment.
    final fromUrl = upper.contains('/') ? upper.split('/').last : upper;
    return fromUrl.replaceAll(RegExp('[^A-Z0-9]'), '');
  }
}
