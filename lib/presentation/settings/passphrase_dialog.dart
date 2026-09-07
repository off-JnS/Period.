import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shortest passphrase the app will accept for a backup.
///
/// A number, not a strength meter. The file is offline and there is nobody to
/// rate-limit, so what matters is that it is not trivially short; anything more
/// opinionated would be theatre.
const minimumPassphraseLength = 8;

/// Asks for a passphrase, returning null if she backs out.
///
/// [confirming] adds a second field, for choosing a new passphrase rather than
/// entering an existing one: a typo in a passphrase that is never recoverable
/// would make the backup unopenable and nothing would notice until the day it
/// was needed.
class PassphraseDialog extends StatefulWidget {
  /// Creates the dialogue.
  const PassphraseDialog({required this.confirming, super.key});

  /// Whether this is choosing a new passphrase rather than entering one.
  final bool confirming;

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _passphrase = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final value = _passphrase.text;

    if (widget.confirming) {
      if (value.length < minimumPassphraseLength) {
        setState(
          () => _error = l10n.passphraseTooShort(minimumPassphraseLength),
        );
        return;
      }
      if (value != _again.text) {
        setState(() => _error = l10n.passphraseMismatch);
        return;
      }
    } else if (value.isEmpty) {
      setState(() => _error = l10n.passphraseTooShort(1));
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(
        widget.confirming
            ? l10n.choosePassphraseTitle
            : l10n.enterPassphraseTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Before the field, not after it. By the time she has typed a
          // passphrase she has already decided; the consequence of forgetting
          // it needs to reach her first.
          if (widget.confirming) ...[
            Text(
              l10n.choosePassphraseBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _passphrase,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.passphraseLabel,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => widget.confirming ? null : _submit(),
          ),
          if (widget.confirming) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _again,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.passphraseAgainLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.confirming ? l10n.exportBackup : l10n.replaceAction,
          ),
        ),
      ],
    );
  }
}

/// Shows [PassphraseDialog] and returns what was typed, or null.
Future<String?> askForPassphrase(
  BuildContext context, {
  required bool confirming,
}) => showDialog<String>(
  context: context,
  builder: (context) => PassphraseDialog(confirming: confirming),
);
