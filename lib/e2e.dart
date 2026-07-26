import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'web_api.dart';

/// Message encryption — Dart port of `manavizha/lib/e2e.ts`.
///
/// ECDH P-256 key agreement + AES-256-GCM, byte-compatible with the web's
/// WebCrypto output: the AES key is the raw x-coordinate of the shared point
/// (32 bytes), the IV is 12 random bytes, and the 16-byte GCM tag is appended
/// to the ciphertext. Base64 (standard) for ciphertext/iv, base64url
/// (unpadded) for JWK fields — exactly what `btoa` / JWK produce on the web.
///
/// The key pair lives in `user_keys` (public_key + private_key JWK) so web and
/// mobile share one messaging identity. If the server only has a public key
/// (published by a pre-key-sync web browser), mobile does NOT take over the
/// identity — the browser uploads its private key on the member's next web
/// visit, after which mobile picks it up and the whole history opens here.
class E2E {
  E2E._();

  static final ECDomainParameters _params = ECDomainParameters('prime256v1');

  static Map<String, dynamic>? _ownPrivJwk;
  static DateTime? _ownFetchedAt;
  static final Map<String, Map<String, dynamic>?> _pubCache = {};

  /// Derived AES key per conversation partner — EC point multiplication is
  /// the expensive step (tens of ms in pure Dart), so cache it; AES-GCM per
  /// message afterwards is negligible.
  static final Map<String, Uint8List> _sharedKeyCache = {};

  /// Forget cached keys (call on logout / account switch).
  static void reset() {
    _ownPrivJwk = null;
    _ownFetchedAt = null;
    _pubCache.clear();
    _sharedKeyCache.clear();
  }

  static Future<Uint8List?> _sharedKeyWith(String otherUserId) async {
    final cached = _sharedKeyCache[otherUserId];
    if (cached != null) return cached;
    final priv = await _getOrCreateOwnKey();
    if (priv == null) return null;
    final otherPub = await _publicKeyOf(otherUserId);
    if (otherPub == null) return null;
    final key = sharedAesKey(priv, otherPub);
    _sharedKeyCache[otherUserId] = key;
    return key;
  }

  // ── Key management ───────────────────────────────────────────────────────

  /// The caller's private key JWK — fetched from the server, generated and
  /// published on first use anywhere. Returns null when unavailable (offline,
  /// or the identity is still owned by an unsynced web browser); negative
  /// results are re-checked after a short TTL.
  static Future<Map<String, dynamic>?> _getOrCreateOwnKey() async {
    if (_ownPrivJwk != null) return _ownPrivJwk;
    final fetchedAt = _ownFetchedAt;
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(minutes: 2)) {
      return null;
    }

    final res = await WebApi.get('/api/keys');
    if (!res.ok) return null;
    _ownFetchedAt = DateTime.now();

    final priv = res.data['privateKey'];
    if (priv is Map && priv['d'] != null) {
      _ownPrivJwk = Map<String, dynamic>.from(priv);
      return _ownPrivJwk;
    }

    final pub = res.data['publicKey'];
    if (pub is Map && pub['x'] != null) {
      // Identity owned by a pre-sync web browser. Don't overwrite it — its
      // private key syncs on the next web visit and history stays readable.
      return null;
    }

    // No key anywhere — this device creates the identity.
    final jwk = _generatePrivateJwk();
    final post = await WebApi.post('/api/keys', {
      'publicKey': {'kty': 'EC', 'crv': 'P-256', 'x': jwk['x'], 'y': jwk['y']},
      'privateKey': jwk,
    });
    if (!post.ok) return null;
    _ownPrivJwk = jwk;
    return jwk;
  }

  static Future<Map<String, dynamic>?> _publicKeyOf(String userId) async {
    if (_pubCache.containsKey(userId)) return _pubCache[userId];
    final res = await WebApi.get('/api/keys', query: {'userId': userId});
    Map<String, dynamic>? jwk;
    final pub = res.ok ? res.data['publicKey'] : null;
    if (pub is Map && pub['x'] != null && pub['y'] != null) {
      jwk = Map<String, dynamic>.from(pub);
    }
    if (res.ok) _pubCache[userId] = jwk;
    return jwk;
  }

  /// Whether [otherUserId] has published a key (i.e. can receive encrypted
  /// messages) — mirrors the web's `canEncryptFor`.
  static Future<bool> canEncryptFor(String otherUserId) async =>
      (await _publicKeyOf(otherUserId)) != null;

  // ── Encrypt / decrypt ────────────────────────────────────────────────────

  /// Returns `(ciphertext, iv)` base64 strings, or null when encryption is
  /// not possible (no keys) — callers fall back to plaintext, like the web.
  static Future<({String ciphertext, String iv})?> encrypt(
      String plaintext, String otherUserId) async {
    try {
      final key = await _sharedKeyWith(otherUserId);
      if (key == null) return null;
      final rnd = Random.secure();
      final iv = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
      final cipher =
          gcm(true, key, iv, Uint8List.fromList(utf8.encode(plaintext)));
      return (ciphertext: base64.encode(cipher), iv: base64.encode(iv));
    } catch (e) {
      debugPrint('E2E encrypt: $e');
      return null;
    }
  }

  /// Decrypts a message exchanged with [otherUserId]; null when the content
  /// cannot be decrypted (missing key, tampered data) — callers show an
  /// "Encrypted message" placeholder, like the web.
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
      bool forEncryption, Uint8List key, Uint8List iv, Uint8List input) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(forEncryption, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return cipher.process(input);
  }

  static Map<String, dynamic> _generatePrivateJwk() {
    final n = _params.n;
    final rnd = Random.secure();
    BigInt d;
    do {
      final bytes =
          Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
      d = _bytesToBig(bytes) % n;
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
