import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:siros/crypto.dart';

void main() {
  group('concat', () {
    test('concatenates empty list', () {
      expect(concat([]), equals(Uint8List(0)));
    });

    test('concatenates single array', () {
      final a = Uint8List.fromList([1, 2, 3]);
      expect(concat([a]), equals(Uint8List.fromList([1, 2, 3])));
    });

    test('concatenates multiple arrays', () {
      final a = Uint8List.fromList([1, 2]);
      final b = Uint8List.fromList([3, 4, 5]);
      final c = Uint8List.fromList([6]);
      expect(
          concat([a, b, c]), equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
    });
  });

  group('cborBstr', () {
    test('encodes empty bytes (tiny)', () {
      final result = cborBstr(Uint8List(0));
      expect(result, equals(Uint8List.fromList([0x40])));
    });

    test('encodes short bytes (< 24)', () {
      final data = Uint8List.fromList([0xaa, 0xbb]);
      final result = cborBstr(data);
      // major type 2, length 2 → 0x42
      expect(result, equals(Uint8List.fromList([0x42, 0xaa, 0xbb])));
    });

    test('encodes 23-byte payload (still tiny)', () {
      final data = Uint8List(23);
      final result = cborBstr(data);
      expect(result[0], equals(0x40 | 23));
      expect(result.length, equals(24)); // 1 header + 23 payload
    });

    test('encodes 24-byte payload (1-byte length)', () {
      final data = Uint8List(24);
      final result = cborBstr(data);
      expect(result[0], equals(0x58));
      expect(result[1], equals(24));
      expect(result.length, equals(26)); // 2 header + 24 payload
    });

    test('encodes 255-byte payload (1-byte length)', () {
      final data = Uint8List(255);
      final result = cborBstr(data);
      expect(result[0], equals(0x58));
      expect(result[1], equals(255));
    });

    test('encodes 256-byte payload (2-byte length)', () {
      final data = Uint8List(256);
      final result = cborBstr(data);
      expect(result[0], equals(0x59));
      expect(result[1], equals(1)); // 256 >> 8
      expect(result[2], equals(0)); // 256 & 0xff
    });

    test('encodes 65536-byte payload (4-byte length)', () {
      final data = Uint8List(65536);
      final result = cborBstr(data);
      expect(result[0], equals(0x5a));
      expect(result[1], equals(0));
      expect(result[2], equals(1)); // 65536 >> 16
      expect(result[3], equals(0));
      expect(result[4], equals(0));
    });
  });

  group('tagged24', () {
    test('wraps bytes in CBOR tag 24', () {
      final data = Uint8List.fromList([0x01, 0x02]);
      final result = tagged24(data);
      // d8 18 = tag(24), then bstr encoding of [0x01, 0x02]
      expect(result[0], equals(0xd8));
      expect(result[1], equals(0x18));
      // bstr header: 0x42 (2 bytes)
      expect(result[2], equals(0x42));
      expect(result[3], equals(0x01));
      expect(result[4], equals(0x02));
    });
  });

  group('saltFromTranscript', () {
    test('produces 32-byte salt', () {
      final transcript = Uint8List.fromList([0x83, 0xf6, 0xf6, 0xf6]);
      final salt = saltFromTranscript(transcript);
      expect(salt.length, equals(32));
    });

    test('deterministic — same input produces same salt', () {
      final transcript = Uint8List.fromList(utf8.encode('test-transcript'));
      final salt1 = saltFromTranscript(transcript);
      final salt2 = saltFromTranscript(transcript);
      expect(salt1, equals(salt2));
    });

    test('different inputs produce different salts', () {
      final t1 = Uint8List.fromList(utf8.encode('transcript-a'));
      final t2 = Uint8List.fromList(utf8.encode('transcript-b'));
      expect(saltFromTranscript(t1), isNot(equals(saltFromTranscript(t2))));
    });
  });

  group('buildCoseKey', () {
    test('builds correct COSE_Key map structure', () {
      // 04 || 32-byte x || 32-byte y
      final pubKey = Uint8List(65);
      pubKey[0] = 0x04;
      for (var i = 1; i <= 32; i++) pubKey[i] = i;
      for (var i = 33; i <= 64; i++) pubKey[i] = i;

      final result = buildCoseKey(pubKey);

      // Should start with 0xa4 (map of 4 items)
      expect(result[0], equals(0xa4));
      // kty: EC2 → 01 02
      expect(result[1], equals(0x01));
      expect(result[2], equals(0x02));
      // crv: P-256 → 20 01
      expect(result[3], equals(0x20));
      expect(result[4], equals(0x01));
      // x: bstr(32) → 21 58 20
      expect(result[5], equals(0x21));
      expect(result[6], equals(0x58));
      expect(result[7], equals(0x20));
      // x bytes [1..32]
      expect(result.sublist(8, 40), equals(pubKey.sublist(1, 33)));
      // y: bstr(32) → 22 58 20
      expect(result[40], equals(0x22));
      expect(result[41], equals(0x58));
      expect(result[42], equals(0x20));
      // y bytes [33..64]
      expect(result.sublist(43, 75), equals(pubKey.sublist(33, 65)));
      // total: 1 + 2 + 2 + 3 + 32 + 3 + 32 = 75
      expect(result.length, equals(75));
    });
  });

  group('buildSessionTranscript', () {
    test('builds 3-element CBOR array', () {
      final de = Uint8List.fromList([0x01]);
      final readerKey = Uint8List.fromList([0x02]);
      final result = buildSessionTranscript(de, readerKey);
      // starts with 0x83 (array of 3)
      expect(result[0], equals(0x83));
      // ends with 0xf6 (null)
      expect(result.last, equals(0xf6));
    });

    test('contains tagged device engagement and reader key', () {
      final de = Uint8List.fromList([0xaa]);
      final readerKey = Uint8List.fromList([0xbb]);
      final result = buildSessionTranscript(de, readerKey);
      // Should contain tag 24 markers
      expect(result.contains(0xd8), isTrue);
    });
  });

  group('hkdf', () {
    test('derives key of requested length', () {
      final ikm = Uint8List.fromList(utf8.encode('input key material'));
      final salt = Uint8List(32);
      final info = Uint8List.fromList(utf8.encode('info'));
      final key = hkdf(ikm, salt, info, 32);
      expect(key.length, equals(32));
    });

    test('derives shorter key when requested', () {
      final ikm = Uint8List.fromList(utf8.encode('input key material'));
      final salt = Uint8List(32);
      final info = Uint8List.fromList(utf8.encode('info'));
      final key = hkdf(ikm, salt, info, 16);
      expect(key.length, equals(16));
    });

    test('deterministic — same inputs produce same output', () {
      final ikm = Uint8List.fromList(utf8.encode('input'));
      final salt = Uint8List.fromList(utf8.encode('salt-value-32-bytes-padded!!!!!'));
      final info = Uint8List.fromList(utf8.encode('info'));
      expect(hkdf(ikm, salt, info, 32), equals(hkdf(ikm, salt, info, 32)));
    });

    test('different info labels produce different keys', () {
      final ikm = Uint8List.fromList(utf8.encode('input'));
      final salt = Uint8List(32);
      final info1 = Uint8List.fromList(utf8.encode('SKReader'));
      final info2 = Uint8List.fromList(utf8.encode('SKDevice'));
      expect(hkdf(ikm, salt, info1, 32), isNot(equals(hkdf(ikm, salt, info2, 32))));
    });
  });

  group('deriveSKReader / deriveSKDevice', () {
    test('produces 32-byte keys', () {
      final secret = Uint8List(32);
      final transcript = Uint8List.fromList([0x83, 0xf6, 0xf6, 0xf6]);
      expect(deriveSKReader(secret, transcript).length, equals(32));
      expect(deriveSKDevice(secret, transcript).length, equals(32));
    });

    test('SKReader and SKDevice are different', () {
      final secret = Uint8List.fromList(
          List.generate(32, (i) => i));
      final transcript = Uint8List.fromList([0x83, 0xf6, 0xf6, 0xf6]);
      final skReader = deriveSKReader(secret, transcript);
      final skDevice = deriveSKDevice(secret, transcript);
      expect(skReader, isNot(equals(skDevice)));
    });
  });

  group('AES-GCM encrypt/decrypt', () {
    test('round-trip: decrypt(encrypt(m)) == m', () {
      final key = Uint8List(32);
      for (var i = 0; i < 32; i++) key[i] = i;
      final iv = Uint8List(12);
      final plaintext = Uint8List.fromList(utf8.encode('hello world'));

      final ciphertext = aesGcmEncrypt(key, iv, plaintext);
      expect(ciphertext.length, greaterThan(plaintext.length)); // includes tag

      final decrypted = aesGcmDecrypt(key, iv, ciphertext);
      expect(decrypted, equals(plaintext));
    });

    test('ciphertext differs from plaintext', () {
      final key = Uint8List(32);
      final iv = Uint8List(12);
      final plaintext = Uint8List.fromList(utf8.encode('secret data'));
      final ciphertext = aesGcmEncrypt(key, iv, plaintext);
      expect(ciphertext, isNot(equals(plaintext)));
    });

    test('wrong key fails decryption', () {
      final key1 = Uint8List(32);
      final key2 = Uint8List(32);
      key2[0] = 1;
      final iv = Uint8List(12);
      final plaintext = Uint8List.fromList(utf8.encode('test'));
      final ct = aesGcmEncrypt(key1, iv, plaintext);
      expect(() => aesGcmDecrypt(key2, iv, ct), throwsA(anything));
    });

    test('wrong IV fails decryption', () {
      final key = Uint8List(32);
      final iv1 = Uint8List(12);
      final iv2 = Uint8List(12);
      iv2[0] = 1;
      final plaintext = Uint8List.fromList(utf8.encode('test'));
      final ct = aesGcmEncrypt(key, iv1, plaintext);
      expect(() => aesGcmDecrypt(key, iv2, ct), throwsA(anything));
    });
  });

  group('ecdhSharedSecret', () {
    test('computes 32-byte shared secret', () {
      final domainParams = pc.ECDomainParameters('prime256v1');
      final keyGen = pc.ECKeyGenerator();
      final rng = pc.FortunaRandom();
      final seed = Uint8List(32);
      final src = Random.secure();
      for (var i = 0; i < 32; i++) seed[i] = src.nextInt(256);
      rng.seed(pc.KeyParameter(seed));
      keyGen.init(pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(domainParams), rng));

      final kpA = keyGen.generateKeyPair();
      final kpB = keyGen.generateKeyPair();

      final pubB = Uint8List.fromList(
          (kpB.publicKey as pc.ECPublicKey).Q!.getEncoded(false));

      final shared = ecdhSharedSecret(
          kpA.privateKey as pc.ECPrivateKey, pubB);
      expect(shared.length, equals(32));
    });

    test('both parties derive same shared secret', () {
      final domainParams = pc.ECDomainParameters('prime256v1');
      final keyGen = pc.ECKeyGenerator();
      final rng = pc.FortunaRandom();
      final seed = Uint8List(32);
      final src = Random.secure();
      for (var i = 0; i < 32; i++) seed[i] = src.nextInt(256);
      rng.seed(pc.KeyParameter(seed));
      keyGen.init(pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(domainParams), rng));

      final kpA = keyGen.generateKeyPair();
      final kpB = keyGen.generateKeyPair();

      final pubA = Uint8List.fromList(
          (kpA.publicKey as pc.ECPublicKey).Q!.getEncoded(false));
      final pubB = Uint8List.fromList(
          (kpB.publicKey as pc.ECPublicKey).Q!.getEncoded(false));

      final sharedAB = ecdhSharedSecret(
          kpA.privateKey as pc.ECPrivateKey, pubB);
      final sharedBA = ecdhSharedSecret(
          kpB.privateKey as pc.ECPrivateKey, pubA);
      expect(sharedAB, equals(sharedBA));
    });
  });

  group('end-to-end key derivation', () {
    test('full flow: keygen → ECDH → derive SKReader/SKDevice → encrypt/decrypt', () {
      final domainParams = pc.ECDomainParameters('prime256v1');
      final keyGen = pc.ECKeyGenerator();
      final rng = pc.FortunaRandom();
      final seed = Uint8List(32);
      final src = Random.secure();
      for (var i = 0; i < 32; i++) seed[i] = src.nextInt(256);
      rng.seed(pc.KeyParameter(seed));
      keyGen.init(pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(domainParams), rng));

      final readerKp = keyGen.generateKeyPair();
      final deviceKp = keyGen.generateKeyPair();

      final readerPub = Uint8List.fromList(
          (readerKp.publicKey as pc.ECPublicKey).Q!.getEncoded(false));
      final devicePub = Uint8List.fromList(
          (deviceKp.publicKey as pc.ECPublicKey).Q!.getEncoded(false));

      final sharedSecret = ecdhSharedSecret(
          readerKp.privateKey as pc.ECPrivateKey, devicePub);

      final deCbor = Uint8List.fromList([0xa0]); // empty map placeholder
      final readerKeyCose = buildCoseKey(readerPub);
      final transcript = buildSessionTranscript(deCbor, readerKeyCose);

      final skReader = deriveSKReader(sharedSecret, transcript);
      final skDevice = deriveSKDevice(sharedSecret, transcript);

      // Encrypt with SKReader, verify decryptable
      final iv = Uint8List(12);
      final message = Uint8List.fromList(utf8.encode('device request'));
      final ct = aesGcmEncrypt(skReader, iv, message);
      final pt = aesGcmDecrypt(skReader, iv, ct);
      expect(pt, equals(message));

      // SKDevice derives differently
      expect(skDevice, isNot(equals(skReader)));
      expect(skDevice.length, equals(32));
    });
  });
}
