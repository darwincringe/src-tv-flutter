import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/auth/auth_service.dart';
import '../../data/store/library_store.dart';
import '../../data/store/watch_progress.dart';
import '../../data/sync/sync_service.dart';

enum AuthMode { login, register }

/// The register/login form, wired to [AuthService]. Reused by the first-run
/// welcome gate and the Settings page. Built for a TV remote: Enter/OK on a
/// field moves to the NEXT field (not the button), fields scroll clear of the
/// on-screen keyboard, and the post-auth sync dialog is D-pad focusable.
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
    await runPostAuthSync(context);
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

/// Post-authentication: if this device has local data, ask whether to upload it
/// to the account; then pull the account's data down (last-write-wins).
Future<void> runPostAuthSync(BuildContext context) async {
  final localCount =
      WatchProgressStore.all().length + LibraryStore.all().length;
  var upload = false;
  if (localCount > 0) {
    upload = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black87,
          builder: (_) => _SyncPromptDialog(count: localCount),
        ) ??
        false;
  }
  if (upload) {
    final ok = await SyncService.pushAllLocal();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'This device\'s data was saved to your account.'
                : 'Could not upload local data — it will retry as you use the app.',
          ),
        ),
      );
    }
  }
  await SyncService.pullAll();
}

/// The "save this device's data" dialog. A [FocusScope] + an explicit
/// post-frame focus request guarantee the remote lands on a button (autofocus
/// alone can miss while the dialog route is still animating in).
class _SyncPromptDialog extends StatefulWidget {
  const _SyncPromptDialog({required this.count});
  final int count;

  @override
  State<_SyncPromptDialog> createState() => _SyncPromptDialogState();
}

class _SyncPromptDialogState extends State<_SyncPromptDialog> {
  final _syncNode = FocusNode(debugLabel: 'syncBtn');

  @override
  void initState() {
    super.initState();
    // Force focus onto a dialog button so the remote lands inside the modal and
    // can't drift to the widgets behind it. Post-frame handles the normal case;
    // the short delay covers the route still transitioning in.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSync());
    Future.delayed(const Duration(milliseconds: 150), _focusSync);
  }

  void _focusSync() {
    if (mounted) _syncNode.requestFocus();
  }

  @override
  void dispose() {
    _syncNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    return Dialog(
      backgroundColor: AppColors.charcoalLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      // A traversal group keeps D-pad Left/Right/Up/Down contained to the two
      // buttons instead of escaping to the form behind the modal.
      child: FocusTraversalGroup(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Save this device\'s data to your account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You have $n item${n == 1 ? '' : 's'} watched or saved on this '
                'device. Sync them so they follow you to other devices.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PillButton(
                    label: 'Not now',
                    filled: false,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 12),
                  _PillButton(
                    label: 'Sync',
                    focusNode: _syncNode,
                    autofocus: true,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    this.autofocus = false,
    this.focusNode,
  });
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: widget.onTap,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
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
