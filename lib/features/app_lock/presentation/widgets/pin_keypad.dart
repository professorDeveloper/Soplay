import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/theme/app_colors.dart';

class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.biometricIcon,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final IconData? biometricIcon;

  @override
  Widget build(BuildContext context) {
    final rows = <List<_Key>>[
      [_Key.digit('1'), _Key.digit('2'), _Key.digit('3')],
      [_Key.digit('4'), _Key.digit('5'), _Key.digit('6')],
      [_Key.digit('7'), _Key.digit('8'), _Key.digit('9')],
      [
        onBiometric != null
            ? _Key.action(
                icon: biometricIcon ?? Icons.fingerprint_rounded,
                action: _KeyAction.biometric,
              )
            : _Key.empty(),
        _Key.digit('0'),
        _Key.action(
          icon: Icons.backspace_outlined,
          action: _KeyAction.backspace,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final k in row)
                    _KeyButton(
                      data: k,
                      onTap: () => _handle(k),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _handle(_Key k) {
    HapticFeedback.selectionClick();
    switch (k.action) {
      case _KeyAction.digit:
        onDigit(k.label!);
      case _KeyAction.backspace:
        onBackspace();
      case _KeyAction.biometric:
        onBiometric?.call();
      case _KeyAction.none:
        break;
    }
  }
}

enum _KeyAction { digit, backspace, biometric, none }

class _Key {
  _Key._({this.label, this.icon, required this.action});
  factory _Key.digit(String d) => _Key._(label: d, action: _KeyAction.digit);
  factory _Key.action({
    required IconData icon,
    required _KeyAction action,
  }) =>
      _Key._(icon: icon, action: action);
  factory _Key.empty() => _Key._(action: _KeyAction.none);

  final String? label;
  final IconData? icon;
  final _KeyAction action;
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.data, required this.onTap});
  final _Key data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (data.action == _KeyAction.none) {
      return const SizedBox(width: 72, height: 72);
    }
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: data.icon != null
                ? Icon(
                    data.icon,
                    color: AppColors.textPrimary,
                    size: 26,
                  )
                : Text(
                    data.label!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
