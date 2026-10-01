import 'package:flutter/material.dart';

import 'e2e.dart';

/// Unlocks (or sets up) the member's chat key on this device — Flutter port of
/// the web's `components/chat-unlock-dialog.tsx`. Resolves to true once the
/// key is ready.
Future<bool> showChatUnlockDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ChatUnlockDialog(),
  );
  return ok == true;
}

enum _Step { loading, setup, password, recover, passphrase, forgot, error }

const _brand = Color(0xFFD61A45);

class _ChatUnlockDialog extends StatefulWidget {
  const _ChatUnlockDialog();

  @override
  State<_ChatUnlockDialog> createState() => _ChatUnlockDialogState();
}

class _ChatUnlockDialogState extends State<_ChatUnlockDialog> {
  _Step _step = _Step.loading;
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  String _currentPassword = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _secret.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _step = _Step.loading;
      _error = null;
    });
    final s = await E2E.status();
    if (!mounted) return;
    switch (s.state) {
      case ChatKeyState.ready:
        Navigator.of(context).pop(true);
      case ChatKeyState.setup:
        _goto(_Step.setup);
      case ChatKeyState.locked:
        _goto(s.mode == ChatKeyMode.passphrase ? _Step.passphrase : _Step.password);
      case ChatKeyState.unavailable:
        _goto(_Step.error);
    }
  }

  void _goto(_Step step) {
    setState(() {
      _step = step;
      _secret.clear();
      _confirm.clear();
      _error = null;
    });
  }

  void _done() {
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _submit() async {
    if (_step == _Step.error) return _load();
    final secret = _secret.text;
    if (secret.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      switch (_step) {
        case _Step.setup:
          if (!await E2E.verifyLoginPassword(secret)) {
            error = 'Incorrect password.';
          } else if (await E2E.createKey(ChatKeyMode.password, secret)) {
            return _done();
          } else {
            // Another device created the key meanwhile.
            return _load();
          }
        case _Step.password:
          final r = await E2E.unlock(secret);
          if (r == UnlockResult.ok) return _done();
          if (r == UnlockResult.error) return _goto(_Step.error);
          if (!await E2E.verifyLoginPassword(secret)) {
            error = 'Incorrect password.';
          } else {
            // Correct login password that doesn't open the key: it was
            // sealed before a password reset.
            _currentPassword = secret;
            return _goto(_Step.recover);
          }
        case _Step.recover:
          final r = await E2E.unlock(secret);
          if (r == UnlockResult.ok) {
            await E2E.reseal(ChatKeyMode.password, _currentPassword);
            return _done();
          }
          if (r == UnlockResult.error) return _goto(_Step.error);
          error = "That password doesn't unlock your chats either.";
        case _Step.passphrase:
          final r = await E2E.unlock(secret);
          if (r == UnlockResult.ok) return _done();
          if (r == UnlockResult.error) return _goto(_Step.error);
          error = 'Incorrect passphrase.';
        case _Step.forgot:
          if (secret.length < E2E.minPassphraseLength) {
            error = 'Use at least ${E2E.minPassphraseLength} characters.';
          } else if (secret != _confirm.text) {
            error = "Passphrases don't match.";
          } else if (await E2E.createKey(ChatKeyMode.passphrase, secret,
              replace: true)) {
            return _done();
          } else {
            error = "Couldn't reset your chat key. Please try again.";
          }
        case _Step.loading:
        case _Step.error:
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (error != null) _error = error;
        });
      }
    }
  }

  Future<void> _startFreshWithPassword() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await E2E.createKey(ChatKeyMode.password, _currentPassword,
        replace: true);
    if (!mounted) return;
    if (ok) return _done();
    setState(() {
      _busy = false;
      _error = "Couldn't reset your chat key. Please try again.";
    });
  }

  ({String title, String body, String label, String action}) get _copy =>
      switch (_step) {
        _Step.loading => (
            title: 'Checking your chats…',
            body: 'One moment.',
            label: '',
            action: ''
          ),
        _Step.setup => (
            title: 'Set up secure messaging',
            body:
                'Enter your login password. Your chat key is locked with it on this device before it is stored, so your messages stay private.',
            label: 'Login password',
            action: 'Set up'
          ),
        _Step.password => (
            title: 'Unlock your chats',
            body:
                'Enter your login password to read and send encrypted messages on this device.',
            label: 'Login password',
            action: 'Unlock'
          ),
        _Step.recover => (
            title: 'Your password was changed',
            body:
                'Your chats are still locked with your previous password. Enter it to recover your chat history.',
            label: 'Previous password',
            action: 'Recover chats'
          ),
        _Step.passphrase => (
            title: 'Unlock your chats',
            body:
                'End-to-end encryption is on. Enter your chat passphrase to read and send messages on this device.',
            label: 'Chat passphrase',
            action: 'Unlock'
          ),
        _Step.forgot => (
            title: 'Start fresh with a new passphrase',
            body:
                "Without your old passphrase, earlier messages can't be recovered by anyone — including Manavizha. New messages will use the new passphrase.",
            label: 'New chat passphrase',
            action: 'Reset and continue'
          ),
        _Step.error => (
            title: "Couldn't reach Manavizha",
            body: 'Check your connection and try again.',
            label: '',
            action: 'Try again'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: _brand),
          const SizedBox(width: 10),
          Expanded(child: Text(copy.title, style: const TextStyle(fontSize: 18))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(copy.body,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            if (_step == _Step.loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: _brand)),
              ),
            if (_step != _Step.loading && _step != _Step.error) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _secret,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                    labelText: copy.label, border: const OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              if (_step == _Step.forgot) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                      labelText: 'Repeat new passphrase',
                      border: OutlineInputBorder()),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            if (_step == _Step.passphrase)
              TextButton(
                onPressed: _busy ? null : () => _goto(_Step.forgot),
                child: const Text('Forgot your passphrase?'),
              ),
            if (_step == _Step.recover)
              TextButton(
                onPressed: _busy ? null : _startFreshWithPassword,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text(
                    "I don't remember it — start fresh (earlier messages can't be read)",
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (_step != _Step.loading)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(copy.action),
          ),
      ],
    );
  }
}
