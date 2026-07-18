import 'package:equatable/equatable.dart';
import 'package:soplay/features/trivia/domain/entities/actor_fan_stat_entity.dart';

enum TopFansStatus { initial, loading, loaded, error }

const Object _unset = Object();

class TopFansState extends Equatable {
  const TopFansState({
    this.status = TopFansStatus.initial,
    this.fanStat,
    this.message,
  });

  final TopFansStatus status;
  final ActorFanStatEntity? fanStat;
  final String? message;

  TopFansState copyWith({
    TopFansStatus? status,
    Object? fanStat = _unset,
    Object? message = _unset,
  }) {
    return TopFansState(
      status: status ?? this.status,
      fanStat:
          fanStat == _unset ? this.fanStat : fanStat as ActorFanStatEntity?,
      message: message == _unset ? this.message : message as String?,
    );
  }

  @override
  List<Object?> get props => [status, fanStat, message];
}
