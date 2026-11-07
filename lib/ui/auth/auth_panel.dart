import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/auth/auth_service.dart';
import '../../data/sync/sync_service.dart';

enum AuthMode { login, register }

/// The register/login form, wired to [AuthService]. Reused by the first-run
/// welcome gate and the Settings page. Built for a TV remote: Enter/OK on a
/// field moves to the NEXT field (not the button), and fields scroll clear of
/// the on-screen keyboard. Signing in syncs this device with the account.
class AuthPanel extends StatefulWidget {
  const AuthPanel({
    super.key,
    this.onAuthenticated,
    this.showSkip = false,
    this.onSkip,
    this.initialMode = AuthMode.register,
  });

  final VoidCallback? onAuthenticated;
  final bool showSkip;
  final VoidCallback? onSkip;
  final AuthMode initialMode;

  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel> {
  late AuthMode _mode = widget.initialMode;
  final _username = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final _usernameNode = FocusNode();
  final _identifierNode = FocusNode();
  final _passwordNode = FocusNode();
  final _confirmNode = FocusNode();

  bool _busy = false;
  String? _error;

  static final RegExp _usernameRe = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  @override
  void dispose() {
    _username.dispose();
    _identifier.dispose();
    _password.dispose();
    _confirm.dispose();
    _usernameNode.dispose();
    _identifierNode.dispose();
    _passwordNode.dispose();
    _confirmNode.dispose();
    super.dispose();
  }

  String? _validate() {
    final pass = _password.text;
    if (_mode == AuthMode.register) {
      if (!_usernameRe.hasMatch(_username.text.trim())) {
        return 'Username must be 3-20 letters, numbers or underscore.';
      }
      final email = _identifier.text.trim();
      if (!email.contains('@') || !email.contains('.')) {
        return 'Enter a valid email address.';
      }
      if (pass.length < 8) return 'Password must be at least 8 characters.';
      if (pass != _confirm.text) return 'Passwords do not match.';
    } else {
      if (_identifier.text.trim().isEmpty) {
        return 'Enter your email or username.';
      }
      if (pass.isEmpty) return 'Enter your password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus(); // drop the keyboard before the request
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = _mode == AuthMode.register
        ? await AuthService.register(
            _username.text.trim(),
            _identifier.text.trim(),
            _password.text,
          )
        : await AuthService.login(_identifier.text.trim(), _password.text);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _busy = false;
        _error = result;
      });
      return;
    }
    await SyncService.sync();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onAuthenticated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == AuthMode.register;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ModeTab(
              label: 'Login',
              selected: !isRegister,
              autofocus: widget.initialMode == AuthMode.login,
              onTap: () => setState(() {
                _mode = AuthMode.login;
                _error = null;
              }),
            ),
            const SizedBox(width: 12),
            _ModeTab(
              label: 'Register',
              selected: isRegister,
              autofocus: widget.initialMode == AuthMode.register,
              onTap: () => setState(() {
                _mode = AuthMode.register;
                _error = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (isRegister) ...[
          _AuthField(
            controller: _username,
            focusNode: _usernameNode,
            placeholder: 'Username',
            textInputAction: TextInputAction.next,
            onSubmitted: () => _identifierNode.requestFocus(),
          ),
          const SizedBox(height: 14),
        ],
        _AuthField(
          controller: _identifier,
          focusNode: _identifierNode,
          placeholder: isRegister ? 'Email' : 'Email or username',
          keyboardType:
              isRegister ? TextInputType.emailAddress : TextInputType.text,
          textInputAction: TextInputAction.next,
          onSubmitted: () => _passwordNode.requestFocus(),
        ),
        const SizedBox(height: 14),
        _AuthField(
          controller: _password,
          focusNode: _passwordNode,
          placeholder: 'Password',
          obscure: true,
          textInputAction:
              isRegister ? TextInputAction.next : TextInputAction.done,
          onSubmitted: () =>
              isRegister ? _confirmNode.requestFocus() : _submit(),
        ),
        if (isRegister) ...[
          const SizedBox(height: 14),
          _AuthField(
            controller: _confirm,
            focusNode: _confirmNode,
            placeholder: 'Confirm password',
            obscure: true,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        _PillButton(
          label: _busy
              ? 'Please wait…'
              : (isRegister ? 'Create Account' : 'Sign In'),
          onTap: _busy ? null : _submit,
        ),
        if (widget.showSkip) ...[
          const SizedBox(height: 14),
          _PillButton(
            label: 'Skip for now',
            filled: false,
            onTap: _busy ? null : widget.onSkip,
          ),
        ],
      ],
    );
  }
}

// ---- shared building blocks (D-pad friendly) ----------------------------

class _ModeTab extends StatefulWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_ModeTab> createState() => _ModeTabState();
}

class _ModeTabState extends State<_ModeTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      focusedScale: 1.05,
      showBorder: false,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(23),
      child: FocusRing(
        focused: _focused,
        radius: 23,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.textPrimary
                : AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected
                  ? AppColors.charcoal
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field that: lets the D-pad move Up/Down out of it (via [DpadFieldFocus]),
/// routes Enter/IME-action to [onSubmitted] (wired to the next field / submit),
/// and scrolls itself clear of the keyboard when it gains focus.
class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (!widget.focusNode.hasFocus) return;
    // Scroll this field toward the top so the keyboard never covers it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.15,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DpadFieldFocus(
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: widget.obscure,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.charcoalLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.textPrimary, width: 2),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.filled = true,
  });
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: widget.onTap,
      focusedScale: 1.05,
      showBorder: false,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(11),
      child: FocusRing(
        focused: _focused,
        radius: 11,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            color: widget.filled
                ? AppColors.textPrimary
                : AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.filled
                  ? AppColors.charcoal
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
