part of 'link_tv_bloc.dart';

sealed class LinkTvEvent extends Equatable {
  const LinkTvEvent();

  @override
  List<Object?> get props => const [];
}

class LinkTvCodeChanged extends LinkTvEvent {
  final String code;

  const LinkTvCodeChanged(this.code);

  @override
  List<Object?> get props => [code];
}

/// [code] is supplied by the scanner; the manual form submits the state's code.
class LinkTvApprove extends LinkTvEvent {
  final String? code;

  const LinkTvApprove({this.code});

  @override
  List<Object?> get props => [code];
}

class LinkTvDevicesRequested extends LinkTvEvent {
  const LinkTvDevicesRequested();
}

class LinkTvUnlinkRequested extends LinkTvEvent {
  final String id;

  const LinkTvUnlinkRequested(this.id);

  @override
  List<Object?> get props => [id];
}
