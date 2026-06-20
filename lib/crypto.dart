import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

/// Concatenate multiple byte arrays into one.
Uint8List concat(List<Uint8List> arrays) {
  final total = arrays.fold(0, (s, a) => s + a.length);
  final result = Uint8List(total);
  var offset = 0;
  for (final a in arrays) {
    result.setAll(offset, a);
    offset += a.length;
  }
  return result;
}

/// Encode bytes as a CBOR byte string (major type 2).
Uint8List cborBstr(Uint8List bytes) {
  final len = bytes.length;
  if (len < 24) return concat([Uint8List.fromList([0x40 | len]), bytes]);
  if (len < 256) return concat([Uint8List.fromList([0x58, len]), bytes]);
  if (len < 65536) {
    return concat(
        [Uint8List.fromList([0x59, len >> 8, len & 0xff]), bytes]);
  }
  return concat([
    Uint8List.fromList([
      0x5a,
      (len >> 24) & 0xff,
      (len >> 16) & 0xff,
      (len >> 8) & 0xff,
      len & 0xff
    ]),
    bytes
  ]);
}

/// Wrap bytes in CBOR tag 24 (encoded CBOR data item).
Uint8List tagged24(Uint8List bytes) =>
    concat([Uint8List.fromList([0xd8, 0x18]), cborBstr(bytes)]);

/// Derive a 32-byte salt by SHA-256 hashing a tagged session transcript.
Uint8List saltFromTranscript(Uint8List sessionTranscript) {
  final tagged = tagged24(sessionTranscript);
  final sha256 = pc.SHA256Digest();
  final salt = Uint8List(32);
  sha256.update(tagged, 0, tagged.length);
  sha256.doFinal(salt, 0);
  return salt;
}

/// Build a COSE_Key map from an uncompressed EC public key (65 bytes: 04||x||y).
/// Format: {1:2, -1:1, -2:x, -3:y}
Uint8List buildCoseKey(Uint8List pubKeyUncompressed) {
  final x = pubKeyUncompressed.sublist(1, 33);
  final y = pubKeyUncompressed.sublist(33, 65);
  final bytes = <int>[];
  bytes.add(0xa4); // map of 4
  bytes.addAll([0x01, 0x02]); // 1: 2 (kty: EC2)
  bytes.addAll([0x20, 0x01]); // -1: 1 (crv: P-256)
  bytes.addAll([0x21, 0x58, 0x20]); // -2: bstr(32)
  bytes.addAll(x);
  bytes.addAll([0x22, 0x58, 0x20]); // -3: bstr(32)
  bytes.addAll(y);
  return Uint8List.fromList(bytes);
}

/// Build the ISO 18013-5 SessionTranscript:
/// [#6.24(deBytes), #6.24(eReaderKeyCose), null]
Uint8List buildSessionTranscript(
    Uint8List deBytes, Uint8List eReaderKeyCose) {
  final bytes = <int>[];
  bytes.add(0x83); // array(3)
  bytes.addAll(tagged24(deBytes));
  bytes.addAll(tagged24(eReaderKeyCose));
  bytes.add(0xf6); // null
  return Uint8List.fromList(bytes);
}

/// HKDF-SHA256 key derivation.
Uint8List hkdf(Uint8List ikm, Uint8List salt, Uint8List info, int length) {
  final hmac = pc.HMac(pc.SHA256Digest(), 64);
  hmac.init(pc.KeyParameter(salt));
  final prk = Uint8List(32);
  hmac.update(ikm, 0, ikm.length);
  hmac.doFinal(prk, 0);
  hmac.init(pc.KeyParameter(prk));
  final infoWithCounter = concat([info, Uint8List.fromList([0x01])]);
  hmac.update(infoWithCounter, 0, infoWithCounter.length);
  final okm = Uint8List(32);
  hmac.doFinal(okm, 0);
  return okm.sublist(0, length);
}

/// Derive the SKReader key from shared secret and session transcript.
Uint8List deriveSKReader(
    Uint8List sharedSecret, Uint8List sessionTranscript) {
  final salt = saltFromTranscript(sessionTranscript);
  final info = Uint8List.fromList(utf8.encode('SKReader'));
  return hkdf(sharedSecret, salt, info, 32);
}

/// Derive the SKDevice key from shared secret and session transcript.
Uint8List deriveSKDevice(
    Uint8List sharedSecret, Uint8List sessionTranscript) {
  final salt = saltFromTranscript(sessionTranscript);
  final info = Uint8List.fromList(utf8.encode('SKDevice'));
  return hkdf(sharedSecret, salt, info, 32);
}

/// AES-GCM encrypt with 128-bit tag.
Uint8List aesGcmEncrypt(Uint8List key, Uint8List iv, Uint8List plaintext) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params =
      pc.AEADParameters(pc.KeyParameter(key), 128, iv, Uint8List(0));
  cipher.init(true, params);
  return cipher.process(plaintext);
}

/// AES-GCM decrypt with 128-bit tag.
Uint8List aesGcmDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params =
      pc.AEADParameters(pc.KeyParameter(key), 128, iv, Uint8List(0));
  cipher.init(false, params);
  return cipher.process(ciphertext);
}

/// Compute ECDH shared secret on P-256.
Uint8List ecdhSharedSecret(
    pc.ECPrivateKey ourPrivKey, Uint8List theirPubKeyBytes) {
  final domainParams = pc.ECDomainParameters('prime256v1');
  final theirPubKey = domainParams.curve.decodePoint(theirPubKeyBytes)!;
  final theirKey = pc.ECPublicKey(theirPubKey, domainParams);
  final agreement = pc.ECDHBasicAgreement();
  agreement.init(ourPrivKey);
  final sharedSecret = agreement.calculateAgreement(theirKey);
  final secretHex = sharedSecret.toRadixString(16).padLeft(64, '0');
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] =
        int.parse(secretHex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
