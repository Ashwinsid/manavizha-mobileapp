import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:manavizha_app/e2e.dart';

/// Sealed-key format tests. Cross-checks with the web's WebCrypto code run
/// when E2E_WEB_VECTORS / E2E_DART_VECTORS point at vector files (see
/// `e2e_vectors.mjs`).
void main() {
  const uid = '6f1c2a1e-0000-4000-8000-000000000001';

  test('seal / unseal round trip, wrong secret and wrong user rejected', () async {
    final jwk = E2E.generatePrivateJwkForTest();
    final pub = {'kty': 'EC', 'crv': 'P-256', 'x': jwk['x'], 'y': jwk['y']};
    final w = await E2E.wrapForTest(uid, jwk, ChatKeyMode.password, 'secret-1');

    expect(w['mode'], 'password');
    expect(w.containsKey('d'), isFalse);
    expect(jsonEncode(w).contains(jwk['d'] as String), isFalse);

    final back = await E2E.unwrapForTest(uid, w, 'secret-1', pub);
    expect(back?['d'], jwk['d']);
    expect(await E2E.unwrapForTest(uid, w, 'secret-2', pub), isNull);
    expect(await E2E.unwrapForTest('$uid-x', w, 'secret-1', pub), isNull);
  });

  final webVectors = Platform.environment['E2E_WEB_VECTORS'];
  test('unseals a web-made blob and decrypts a web-made message', () async {
    final v = jsonDecode(File(webVectors!).readAsStringSync()) as Map;
    final jwk = await E2E.unwrapForTest(
        v['uid'] as String,
        Map<String, dynamic>.from(v['wrapped'] as Map),
        v['secret'] as String,
        Map<String, dynamic>.from(v['publicKey'] as Map));
    expect(jwk?['d'], v['d']);

    final m = v['message'] as Map;
    final key = E2E.sharedAesKey(Map<String, dynamic>.from(m['receiverPriv'] as Map),
        Map<String, dynamic>.from(m['senderPub'] as Map));
    final plain = E2E.gcm(false, key, base64.decode(m['iv'] as String),
        base64.decode(m['ciphertext'] as String));
    expect(utf8.decode(plain), m['text']);
  }, skip: webVectors == null ? 'set E2E_WEB_VECTORS' : false);

  final dartVectors = Platform.environment['E2E_DART_VECTORS'];
  test('writes Dart-made vectors for the web check', () async {
    const secret = 'Pässwörd ✓ 123';
    final a = E2E.generatePrivateJwkForTest();
    final b = E2E.generatePrivateJwkForTest();
    final iv = Uint8List.fromList(List.generate(12, (i) => i * 7));
    const text = 'வணக்கம் — hello from Flutter';
    final ct = E2E.gcm(true, E2E.sharedAesKey(a, b), iv,
        Uint8List.fromList(utf8.encode(text)));
    File(dartVectors!).writeAsStringSync(jsonEncode({
      'uid': uid,
      'secret': secret,
      'publicKey': {'kty': 'EC', 'crv': 'P-256', 'x': a['x'], 'y': a['y']},
      'd': a['d'],
      'wrapped': await E2E.wrapForTest(uid, a, ChatKeyMode.passphrase, secret),
      'message': {
        'text': text,
        'ciphertext': base64.encode(ct),
        'iv': base64.encode(iv),
        'senderPub': {'x': a['x'], 'y': a['y']},
        'receiverPriv': b,
      },
    }));
  }, skip: dartVectors == null ? 'set E2E_DART_VECTORS' : false);
}
