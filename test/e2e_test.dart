import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:manavizha_app/e2e.dart';

/// Cross-implementation compatibility test.
///
/// `test/e2e_vectors.json` is produced by WebCrypto (see the session notes /
/// scratchpad `gen_vectors.mjs`) performing exactly what the web app's
/// `lib/e2e.ts` does: ECDH P-256 deriveKey → AES-256-GCM encrypt. If Dart
/// derives the identical AES key and decrypts the WebCrypto ciphertext, the
/// two apps can read each other's messages.
void main() {
  final vectors = jsonDecode(
    File('test/e2e_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  Map<String, dynamic> jwk(String name) =>
      Map<String, dynamic>.from(vectors[name] as Map);

  test('ECDH shared key matches WebCrypto exactly', () {
    final expectedKey = base64.decode(vectors['aesKeyB64'] as String);

    final keyFromA = E2E.sharedAesKey(jwk('aPriv'), jwk('bPub'));
    final keyFromB = E2E.sharedAesKey(jwk('bPriv'), jwk('aPub'));

    expect(keyFromA, equals(expectedKey));
    // ECDH symmetry: both sides derive the same secret.
    expect(keyFromB, equals(expectedKey));
  });

  test('decrypts a WebCrypto-encrypted message', () {
    final key = E2E.sharedAesKey(jwk('bPriv'), jwk('aPub'));
    final plain = E2E.gcm(
      false,
      key,
      Uint8List.fromList(base64.decode(vectors['iv'] as String)),
      Uint8List.fromList(base64.decode(vectors['ciphertext'] as String)),
    );
    expect(utf8.decode(plain), equals(vectors['plaintext']));
  });

  test('Dart-encrypted message round-trips (WebCrypto-shaped output)', () {
    final key = E2E.sharedAesKey(jwk('aPriv'), jwk('bPub'));
    const message = 'Reply from the mobile app — நன்றி!';
    final iv = Uint8List.fromList(List.generate(12, (i) => i * 7 % 256));

    final cipher =
        E2E.gcm(true, key, iv, Uint8List.fromList(utf8.encode(message)));
    // WebCrypto shape: ciphertext length = plaintext length + 16-byte tag.
    expect(cipher.length, utf8.encode(message).length + 16);

    final plain = E2E.gcm(false, key, iv, cipher);
    expect(utf8.decode(plain), equals(message));
  });

  test('tampered ciphertext fails authentication', () {
    final key = E2E.sharedAesKey(jwk('bPriv'), jwk('aPub'));
    final cipher = Uint8List.fromList(
        base64.decode(vectors['ciphertext'] as String));
    cipher[0] ^= 0xFF;
    expect(
      () => E2E.gcm(
        false,
        key,
        Uint8List.fromList(base64.decode(vectors['iv'] as String)),
        cipher,
      ),
      throwsA(anything),
    );
  });
}
