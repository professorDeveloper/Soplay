import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';

/// Resetting a forgotten password.
///
/// One page, two steps: ask for the address, then take the emailed code and the
/// new password together. Splitting the second step across two screens would
/// mean holding a verified code while navigating, and the code is only useful
/// alongside the password anyway.
///
/// The server signs the user in as part of the reset, so a success here lands
/// in [AuthLoaded] and the router takes them into the app — there is no window
/// where they know the new password but still face a login form.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();

  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCooldown(DateTime until) {
    _ticker?.cancel();
    void tick() {
      if (!mounted) return;
      final left = until.difference(DateTime.now());
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left.isNegative) _ticker?.cancel();
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _sendCode({bool resend = false}) {
    if (!resend && !(_emailForm.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthPasswordResetRequested(email: _email.text.trim(), isResend: resend),
    );
  }

  void _submitReset() {
    if (!(_resetForm.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthPasswordResetSubmitted(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.pushReplacement('/login'),
        ),
      ),
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) => b is AuthPasswordResetPending || b is AuthError,
          listener: (context, state) {
            if (state is AuthPasswordResetPending) {
              _startCooldown(state.cooldownUntil);
              if (state.justSent) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('auth.reset_code_sent'.tr()),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
          builder: (context, state) {
            final pending = state is AuthPasswordResetPending ? state : null;
            final sending = state is AuthLoading;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'auth.forgot_password_title'.tr(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pending == null
                        ? 'auth.forgot_password_subtitle'.tr()
                        : 'auth.reset_password_subtitle'.tr(
                            namedArgs: {'email': pending.email},
                          ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 26),

                  if (pending == null)
                    _EmailStep(
                      formKey: _emailForm,
                      controller: _email,
                      busy: sending,
                      onSubmit: _sendCode,
                    )
                  else
                    _ResetStep(
                      formKey: _resetForm,
                      code: _code,
                      password: _password,
                      confirm: _confirm,
                      obscure: _obscure,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      state: pending,
                      remaining: _remaining,
                      onResend: () => _sendCode(resend: true),
                      onSubmit: _submitReset,
                    ),

                  if (state is AuthError) ...[
                    const SizedBox(height: 14),
                    Text(
                      state.message,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    required this.formKey,
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          _Field(
            controller: controller,
            hint: 'auth.email_hint'.tr(),
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return 'auth.email'.tr();
              if (!value.contains('@') || !value.contains('.')) {
                return 'auth.invalid_email'.tr();
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'auth.send_reset_code'.tr(),
            busy: busy,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _ResetStep extends StatelessWidget {
  const _ResetStep({
    required this.formKey,
    required this.code,
    required this.password,
    required this.confirm,
    required this.obscure,
    required this.onToggleObscure,
    required this.state,
    required this.remaining,
    required this.onResend,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController code;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final AuthPasswordResetPending state;
  final Duration remaining;
  final VoidCallback onResend;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final canResend = remaining == Duration.zero && !state.resending;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            controller: code,
            hint: 'auth.reset_code_hint'.tr(),
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.length != 6) return 'auth.invalid_reset_code'.tr();
              return null;
            },
          ),
          const SizedBox(height: 12),
          _Field(
            controller: password,
            hint: 'auth.new_password_hint'.tr(),
            icon: Icons.lock_outline_rounded,
            obscureText: obscure,
            textInputAction: TextInputAction.next,
            suffix: IconButton(
              onPressed: onToggleObscure,
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppColors.textHint,
              ),
            ),
            validator: (v) {
              if ((v ?? '').isEmpty) return 'auth.password'.tr();
              if ((v ?? '').length < 6) return 'auth.invalid_password'.tr();
              return null;
            },
          ),
          const SizedBox(height: 12),
          _Field(
            controller: confirm,
            hint: 'auth.confirm_password_hint'.tr(),
            icon: Icons.lock_reset_rounded,
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            validator: (v) {
              // Checked here rather than only on the server: a typo would
              // otherwise burn the one-time code and force another email.
              if (v != password.text) return 'auth.passwords_not_match'.tr();
              return null;
            },
          ),

          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12.5),
            ),
          ],

          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'auth.reset_password'.tr(),
            busy: state.submitting,
            onPressed: onSubmit,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: canResend ? onResend : null,
              child: Text(
                canResend
                    ? 'auth.resend_code'.tr()
                    : 'auth.resend_in'.tr(
                        namedArgs: {'seconds': '${remaining.inSeconds}'},
                      ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onFieldSubmitted,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textHint),
        suffixIcon: suffix,
      ),
    );
  }
}
