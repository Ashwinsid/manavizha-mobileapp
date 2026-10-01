import 'package:flutter/material.dart';

import 'chat_unlock_dialog.dart';
import 'e2e.dart';

/// Settings → Chat Security: switch between login-password and passphrase
/// (end-to-end) protection of the chat key — Flutter port of the web's
/// `components/chat-security-settings.tsx`.
class ChatSecuritySettings extends StatefulWidget {
  const ChatSecuritySettings({super.key, required this.accent});

  final Color accent;

  @override
  State<ChatSecuritySettings> createState() => _ChatSecuritySettingsState();
}

enum _Form { enable, change, disable }

class _ChatSecuritySettingsState extends State<ChatSecuritySettings> {
  ChatKeyStatus? _status;
  _Form? _form;
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _secret.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await E2E.status();
    if (mounted) setState(() => _status = s);
  }

  void _openForm(_Form? f) {
    setState(() {
      _form = f;
      _secret.clear();
      _confirm.clear();
    });
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final secret = _secret.text;
    final form = _form;
    if (secret.isEmpty || form == null) return;
    if (form != _Form.disable) {
      if (secret.length < E2E.minPassphraseLength) {
        return _toast('Use at least ${E2E.minPassphraseLength} characters');
      }
      if (secret != _confirm.text) return _toast("Passphrases don't match");
    }
    setState(() => _busy = true);
    try {
      if (form == _Form.disable) {
        if (!await E2E.verifyLoginPassword(secret)) {
          return _toast('Incorrect password');
        }
        if (!await E2E.reseal(ChatKeyMode.password, secret)) throw Exception();
        _toast('Your chats are now locked with your login password');
      } else {
        if (!await E2E.reseal(ChatKeyMode.passphrase, secret)) throw Exception();
        _toast(form == _Form.enable
            ? 'End-to-end encryption is on'
            : 'Chat passphrase changed');
      }
      _openForm(null);
      await _refresh();
    } catch (_) {
      _toast("Couldn't update chat security. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final accent = widget.accent;
    if (s == null) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    final e2eOn = s.mode == ChatKeyMode.passphrase;
    final muted = TextStyle(
        fontSize: 13, color: Colors.black.withValues(alpha: 0.6), height: 1.4);

    Widget body;
    if (s.state == ChatKeyState.unavailable) {
      body = Text(
          "Chat security can't be changed right now. Check your connection and try again.",
          style: muted);
    } else if (s.state != ChatKeyState.ready) {
      final setup = s.state == ChatKeyState.setup;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              setup
                  ? 'Set up secure messaging on this device to manage these settings.'
                  : 'Unlock your chats on this device to manage these settings.',
              style: muted),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () async {
              if (await showChatUnlockDialog(context)) await _refresh();
            },
            child: Text(setup ? 'Set up' : 'Unlock chats'),
          ),
        ],
      );
    } else if (_form != null) {
      final disable = _form == _Form.disable;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            disable
                ? 'Enter your login password to switch back'
                : _form == _Form.enable
                    ? 'Choose a chat passphrase'
                    : 'Choose a new chat passphrase',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (!disable) ...[
            const SizedBox(height: 4),
            Text(
                "Use something you'll remember — at least ${E2E.minPassphraseLength} characters. You'll enter it once on each new phone or browser.",
                style: muted),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _secret,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
                labelText: disable ? 'Login password' : 'Chat passphrase',
                border: const OutlineInputBorder()),
          ),
          if (!disable) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Repeat passphrase', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: _busy ? null : () => _openForm(null),
                  child: const Text('Cancel')),
            ],
          ),
        ],
      );
    } else if (e2eOn) {
      body = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
              onPressed: () => _openForm(_Form.change),
              child: const Text('Change passphrase')),
          OutlinedButton(
              onPressed: () => _openForm(_Form.disable),
              child: const Text('Turn off end-to-end encryption')),
        ],
      );
    } else {
      body = FilledButton(
        style: FilledButton.styleFrom(backgroundColor: accent),
        onPressed: () => _openForm(_Form.enable),
        child: const Text('Turn on end-to-end encryption'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(e2eOn ? Icons.verified_user_rounded : Icons.lock_rounded,
                  color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        e2eOn
                            ? 'End-to-end encryption is on'
                            : 'Messages are encrypted',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        e2eOn
                            ? "Your chat key is locked with a passphrase that never leaves your devices. Nobody else — including Manavizha — can read your messages. If you forget the passphrase, your chat history can't be recovered."
                            : "Messages are encrypted on your device. Your chat key is stored locked with your login password, so it can't be read from our database.",
                        style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}
