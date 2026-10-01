import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'web_api.dart';

enum ChatKeyMode { password, passphrase }

enum ChatKeyState {
  /// Unlocked on this device — messages can be read and sent encrypted.
  ready,

  /// No key anywhere yet; the login password creates one.
  setup,

  /// A key exists but this device hasn't unlocked it.
  locked,

  /// Offline / server unreachable.
  unavailable,
}

class ChatKeyStatus {
  const ChatKeyStatus(this.state, [this.mode]);
  final ChatKeyState state;
  final ChatKeyMode? mode;
}

enum UnlockResult { ok, wrong, error }

/// Message encryption — Dart port of the web's `lib/e2e.ts`.
///
/// ECDH P-256 key agreement + AES-256-GCM, byte-compatible with the web's
/// WebCrypto output: the AES key is the raw x-coordinate of the shared point
/// (32 bytes), the IV is 12 random bytes, and the 16-byte GCM tag is appended
/// to the ciphertext. Base64 (standard) for ciphertext/iv, base64url
/// (unpadded) for JWK fields — exactly what `btoa` / JWK produce on the web.
///
/// One key pair per member, shared by web and mobile. The private key never
/// reaches the server readable: it is sealed on the device (AES-256-GCM under
/// PBKDF2-SHA256 of the login password, or of an opt-in chat passphrase that
/// never leaves the member's devices) and only the sealed blob is stored in
/// `user_keys.wrapped_private_key`. An unlocked key is kept in the platform
/// keystore (flutter_secure_storage) until logout.
class E2E {
  E2E._();

  static const int minPassphraseLength = 8;
  static const int _pbkdf2Iterations = 310000;
  static const String _storageKey = 'manavizha_chat_key';
  static const Duration _revalidateAfter = Duration(minutes: 5);
  static const Duration _publicKeyTtl = Duration(minutes: 5);

  static final ECDomainParameters _params = ECDomainParameters('prime256v1');
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String? _ownUserId;
  static Map<String, dynamic>? _ownPrivJwk;
  static ChatKeyMode? _ownMode;
  static DateTime? _ownCheckedAt;
  static final Map<String, ({Map<String, dynamic>? jwk, DateTime at})>
      _pubCache = {};

  /// Derived AES key per conversation partner — EC point multiplication is
  /// the expensive step (tens of ms in pure Dart), so cache it; AES-GCM per
  /// message afterwards is negligible.
  static final Map<String, Uint8List> _sharedKeyCache = {};

  static String? get _currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// Forget every key on this device (call on logout / account switch).
  static void reset() {
    _forgetOwnKey();
    _pubCache.clear();
    _storage.delete(key: _storageKey).catchError((_) {});
  }

  static void _forgetOwnKey() {
    _ownUserId = null;
    _ownPrivJwk = null;
    _ownMode = null;
    _ownCheckedAt = null;
    _sharedKeyCache.clear();
  }

  // ── Key management ───────────────────────────────────────────────────────

  /// The member's chat key on this device. Never prompts — callers show
  /// `ChatUnlockDialog` for [ChatKeyState.setup] / [ChatKeyState.locked].
  static Future<ChatKeyStatus> status() async {
    final uid = _currentUserId;
    if (uid == null) return const ChatKeyStatus(ChatKeyState.unavailable);
    final checkedAt = _ownCheckedAt;
    if (_ownUserId == uid &&
        _ownPrivJwk != null &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _revalidateAfter) {
      return ChatKeyStatus(ChatKeyState.ready, _ownMode);
    }

    final local = _ownUserId == uid && _ownPrivJwk != null
        ? (jwk: _ownPrivJwk!, mode: _ownMode ?? ChatKeyMode.password)
        : await _readLocal(uid);
    final rec = await _fetchOwnRecord();

    if (rec == null) {
      // Offline: a previously unlocked key still reads cached history.
      if (local == null) return const ChatKeyStatus(ChatKeyState.unavailable);
      await _activate(uid, local.jwk, local.mode);
      return ChatKeyStatus(ChatKeyState.ready, local.mode);
    }
    if (rec.publicKey == null || rec.wrapped == null) {
      reset();
      return const ChatKeyStatus(ChatKeyState.setup);
    }
    final mode = _modeOf(rec.wrapped!);
    if (local != null && _samePoint(local.jwk, rec.publicKey!)) {
      await _activate(uid, local.jwk, mode);
      return ChatKeyStatus(ChatKeyState.ready, mode);
    }
    // Reset on another device, or never unlocked here.
    reset();
    return ChatKeyStatus(ChatKeyState.locked, mode);
  }

  /// Unseals the stored key with the login password or chat passphrase.
  static Future<UnlockResult> unlock(String secret) async {
    final uid = _currentUserId;
    final rec = await _fetchOwnRecord();
    if (uid == null || rec?.publicKey == null || rec?.wrapped == null) {
      return UnlockResult.error;
    }
    final jwk = await _unwrap(uid, rec!.wrapped!, secret, rec.publicKey!);
    if (jwk == null) return UnlockResult.wrong;
    await _activate(uid, jwk, _modeOf(rec.wrapped!));
    return UnlockResult.ok;
  }

  /// Generates a fresh key pair sealed with [secret]. [replace] discards the
  /// existing key (old conversations become unreadable); otherwise this fails
  /// when another device created a key first.
  static Future<bool> createKey(ChatKeyMode mode, String secret,
      {bool replace = false}) async {
    final uid = _currentUserId;
    if (uid == null) return false;
    final jwk = _generatePrivateJwk();
    final res = await _postKey(
        replace ? 'reset' : 'create', jwk, await _wrap(uid, jwk, mode, secret));
    if (!res.ok) return false;
    _pubCache.clear();
    await _activate(uid, jwk, mode);
    return true;
  }

  /// Re-seals the unlocked key with a new secret (switching mode or changing
  /// the passphrase).
  static Future<bool> reseal(ChatKeyMode mode, String secret) async {
    final uid = _currentUserId;
    final jwk = _ownPrivJwk;
    if (uid == null || _ownUserId != uid || jwk == null) return false;
    final res = await _postKey('rewrap', jwk, await _wrap(uid, jwk, mode, secret));
    if (!res.ok) return false;
    await _activate(uid, jwk, mode);
    return true;
  }

  /// Right after a password sign-in: unlock the key with the password, or
  /// create one on first use. Failures are swallowed — chat prompts later.
  static Future<void> unlockAfterLogin(String password) async {
    try {
      final s = await status();
      if (s.state == ChatKeyState.setup) {
        await createKey(ChatKeyMode.password, password);
      } else if (s.state == ChatKeyState.locked &&
          s.mode == ChatKeyMode.password) {
        await unlock(password);
      }
    } catch (e) {
      debugPrint('E2E unlockAfterLogin: $e');
    }
  }

  /// After a password reset: re-seal a password-mode key with the new
  /// password when this device has it unlocked. Otherwise the next unlock
  /// asks for the previous password to recover the history.
  static Future<void> resealAfterPasswordChange(String newPassword) async {
    try {
      final s = await status();
      if (s.state == ChatKeyState.ready && s.mode == ChatKeyMode.password) {
        await reseal(ChatKeyMode.password, newPassword);
      }
    } catch (e) {
      debugPrint('E2E resealAfterPasswordChange: $e');
    }
  }

  /// Checks [password] against the signed-in account (refreshes the session).
  static Future<bool> verifyLoginPassword(String password) async {
    final auth = Supabase.instance.client.auth;
    final email = auth.currentUser?.email;
    if (email == null) return false;
    try {
      await auth.signInWithPassword(email: email, password: password);
      return true;
    } on AuthException {
      return false;
    }
  }

  static Future<void> _activate(
      String uid, Map<String, dynamic> jwk, ChatKeyMode mode) async {
    if (_ownUserId != uid || _ownPrivJwk?['d'] != jwk['d']) {
      _sharedKeyCache.clear();
    }
    _ownUserId = uid;
    _ownPrivJwk = jwk;
    _ownMode = mode;
    _ownCheckedAt = DateTime.now();
    try {
      await _storage.write(
          key: _storageKey,
          value: jsonEncode({'userId': uid, 'jwk': jwk, 'mode': mode.name}));
    } catch (e) {
      debugPrint('E2E keystore write: $e');
    }
  }

  static Future<({Map<String, dynamic> jwk, ChatKeyMode mode})?> _readLocal(
      String uid) async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is! Map || m['userId'] != uid || m['jwk'] is! Map) return null;
      final jwk = Map<String, dynamic>.from(m['jwk'] as Map);
      if (jwk['d'] == null) return null;
      final mode = m['mode'] == 'passphrase'
          ? ChatKeyMode.passphrase
          : ChatKeyMode.password;
      return (jwk: jwk, mode: mode);
    } catch (_) {
      return null;
    }
  }

  static Future<
      ({
        Map<String, dynamic>? publicKey,
        Map<String, dynamic>? wrapped
      })?> _fetchOwnRecord() async {
    final res = await WebApi.get('/api/keys');
    if (!res.ok) return null;
    Map<String, dynamic>? asMap(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    return (
      publicKey: asMap(res.data['publicKey']),
      wrapped: asMap(res.data['wrappedPrivateKey']),
    );
  }

  static Future<WebApiResult> _postKey(String action,
          Map<String, dynamic> privJwk, Map<String, dynamic> wrapped) =>
      WebApi.post('/api/keys', {
        'action': action,
        'publicKey': {
          'kty': 'EC',
          'crv': 'P-256',
          'x': privJwk['x'],
          'y': privJwk['y']
        },
        'wrappedPrivateKey': wrapped,
      });

  static ChatKeyMode _modeOf(Map<String, dynamic> wrapped) =>
      wrapped['mode'] == 'passphrase'
          ? ChatKeyMode.passphrase
          : ChatKeyMode.password;

  static bool _samePoint(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a['x'] != null && a['x'] == b['x'] && a['y'] == b['y'];

  // ── Sealing the private key ──────────────────────────────────────────────

  /// Binds a sealed key to its owner so a blob can't be swapped between
  /// accounts. Must match `wrapAad` in the web's `lib/e2e.ts`.
  static Uint8List _wrapAad(String uid) =>
      Uint8List.fromList(utf8.encode('manavizha-chat-key:v1:$uid'));

  /// PBKDF2-HMAC-SHA256 → 32-byte AES key. Native on Android via
  /// cryptography_flutter; a background isolate elsewhere.
  static Future<Uint8List> _deriveWrappingKey(
      String secret, List<int> salt, int iterations) async {
    final pbkdf2 = crypto.Pbkdf2(
        macAlgorithm: crypto.Hmac.sha256(), iterations: iterations, bits: 256);
    final key =
        await pbkdf2.deriveKeyFromPassword(password: secret, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> wrapForTest(String uid,
          Map<String, dynamic> privJwk, ChatKeyMode mode, String secret) =>
      _wrap(uid, privJwk, mode, secret);

  @visibleForTesting
  static Future<Map<String, dynamic>?> unwrapForTest(
          String uid,
          Map<String, dynamic> wrapped,
          String secret,
          Map<String, dynamic> publicJwk) =>
      _unwrap(uid, wrapped, secret, publicJwk);

  static Future<Map<String, dynamic>> _wrap(String uid,
      Map<String, dynamic> privJwk, ChatKeyMode mode, String secret) async {
    final salt = _randomBytes(16);
    final iv = _randomBytes(12);
    final kek = await _deriveWrappingKey(secret, salt, _pbkdf2Iterations);
    final payload = jsonEncode({
      'kty': 'EC',
      'crv': 'P-256',
      'd': privJwk['d'],
      'x': privJwk['x'],
      'y': privJwk['y'],
    });
    final ct = gcm(true, kek, iv, Uint8List.fromList(utf8.encode(payload)),
        aad: _wrapAad(uid));
    return {
      'v': 1,
      'mode': mode.name,
      'kdf': 'PBKDF2-SHA256',
      'iter': _pbkdf2Iterations,
      'salt': base64.encode(salt),
      'iv': base64.encode(iv),
      'ct': base64.encode(ct),
    };
  }

  /// The private JWK inside [wrapped], or null for a wrong secret / tampered
  /// blob.
  static Future<Map<String, dynamic>?> _unwrap(String uid,
      Map<String, dynamic> wrapped, String secret,
      Map<String, dynamic> publicJwk) async {
    try {
      final iter = (wrapped['iter'] as num).toInt();
      final kek = await _deriveWrappingKey(
          secret, base64.decode(wrapped['salt'] as String), iter);
      final plain = gcm(
          false,
          kek,
          Uint8List.fromList(base64.decode(wrapped['iv'] as String)),
          Uint8List.fromList(base64.decode(wrapped['ct'] as String)),
          aad: _wrapAad(uid));
      final jwk = Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
      return jwk['d'] is String && _samePoint(jwk, publicJwk) ? jwk : null;
    } catch (_) {
      return null;
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _publicKeyOf(String userId) async {
    final hit = _pubCache[userId];
    if (hit != null && DateTime.now().difference(hit.at) < _publicKeyTtl) {
      return hit.jwk;
    }
    final res = await WebApi.get('/api/keys', query: {'userId': userId});
    if (!res.ok) return null;
    Map<String, dynamic>? jwk;
    final pub = res.data['publicKey'];
    if (pub is Map && pub['x'] != null && pub['y'] != null) {
      jwk = Map<String, dynamic>.from(pub);
    }
    if (hit?.jwk?['x'] != jwk?['x']) _sharedKeyCache.remove(userId);
    _pubCache[userId] = (jwk: jwk, at: DateTime.now());
    return jwk;
  }

  static Future<Uint8List?> _sharedKeyWith(String otherUserId) async {
    final priv = _ownUserId == _currentUserId ? _ownPrivJwk : null;
    if (priv == null) return null;
    final otherPub = await _publicKeyOf(otherUserId);
    if (otherPub == null) return null;
    final cached = _sharedKeyCache[otherUserId];
    if (cached != null) return cached;
    final key = sharedAesKey(priv, otherPub);
    _sharedKeyCache[otherUserId] = key;
    return key;
  }

  /// Whether [otherUserId] has published a key (i.e. can receive encrypted
  /// messages) — mirrors the web's `canEncryptFor`.
  static Future<bool> canEncryptFor(String otherUserId) async =>
      (await _publicKeyOf(otherUserId)) != null;

  /// Returns `(ciphertext, iv)` base64 strings, or null when encryption is
  /// not possible — the own key must be unlocked first ([status]).
  static Future<({String ciphertext, String iv})?> encrypt(
      String plaintext, String otherUserId) async {
    try {
      final key = await _sharedKeyWith(otherUserId);
      if (key == null) return null;
      final iv = _randomBytes(12);
      final cipher =
          gcm(true, key, iv, Uint8List.fromList(utf8.encode(plaintext)));
      return (ciphertext: base64.encode(cipher), iv: base64.encode(iv));
    } catch (e) {
      debugPrint('E2E encrypt: $e');
      return null;
    }
  }

  /// Decrypts a message exchanged with [otherUserId]; null when the content
  /// cannot be decrypted (locked key, rotated keys, tampered data).
  static Future<String?> decrypt(
      String ciphertext, String iv, String otherUserId) async {
    try {
      final key = await _sharedKeyWith(otherUserId);
      if (key == null) return null;
      final plain = gcm(false, key, Uint8List.fromList(base64.decode(iv)),
          Uint8List.fromList(base64.decode(ciphertext)));
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Whether this device can currently read/send encrypted messages.
  static bool get isUnlocked =>
      _ownPrivJwk != null && _ownUserId == _currentUserId;

  // ── Crypto internals ─────────────────────────────────────────────────────

  /// WebCrypto-compatible shared secret: x-coordinate of `theirPub · myD`,
  /// big-endian, left-padded to 32 bytes → used directly as the AES-256 key.
  @visibleForTesting
  static Uint8List sharedAesKey(
      Map<String, dynamic> privJwk, Map<String, dynamic> pubJwk) {
    final d = _bytesToBig(_b64uDecode(privJwk['d'].toString()));
    final x = _bytesToBig(_b64uDecode(pubJwk['x'].toString()));
    final y = _bytesToBig(_b64uDecode(pubJwk['y'].toString()));
    final point = _params.curve.createPoint(x, y);
    final shared = (point * d)!;
    return _bigToBytes(shared.x!.toBigInteger()!, 32);
  }

  /// AES-256-GCM with a 128-bit tag appended to the ciphertext — the exact
  /// output shape WebCrypto's `encrypt({name: "AES-GCM"})` produces. On
  /// decrypt, [input] is ciphertext+tag; a bad tag throws.
  @visibleForTesting
  static Uint8List gcm(
      bool forEncryption, Uint8List key, Uint8List iv, Uint8List input,
      {Uint8List? aad}) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(forEncryption,
          AEADParameters(KeyParameter(key), 128, iv, aad ?? Uint8List(0)));
    return cipher.process(input);
  }

  @visibleForTesting
  static Map<String, dynamic> generatePrivateJwkForTest() =>
      _generatePrivateJwk();

  static Map<String, dynamic> _generatePrivateJwk() {
    final n = _params.n;
    BigInt d;
    do {
      d = _bytesToBig(_randomBytes(32)) % n;
    } while (d == BigInt.zero);
    final q = (_params.G * d)!;
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'd': _b64uEncode(_bigToBytes(d, 32)),
      'x': _b64uEncode(_bigToBytes(q.x!.toBigInteger()!, 32)),
      'y': _b64uEncode(_bigToBytes(q.y!.toBigInteger()!, 32)),
    };
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }

  static Uint8List _b64uDecode(String s) =>
      base64Url.decode(base64Url.normalize(s));

  static String _b64uEncode(List<int> b) =>
      base64Url.encode(b).replaceAll('=', '');

  static BigInt _bytesToBig(Uint8List b) {
    var r = BigInt.zero;
    for (final v in b) {
      r = (r << 8) | BigInt.from(v);
    }
    return r;
  }

  static Uint8List _bigToBytes(BigInt v, int length) {
    final out = Uint8List(length);
    var t = v;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (t & BigInt.from(0xff)).toInt();
      t = t >> 8;
    }
    return out;
  }
}
