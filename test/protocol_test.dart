import 'dart:typed_data';
import 'package:cbor/cbor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siros/protocol.dart';

/// Build a minimal device engagement CBOR structure with a BLE UUID.
Uint8List _buildDeviceEngagement(Uint8List uuid, {int uuidKey = 11}) {
  // COSE_Key: {-2: x(32), -3: y(32)}
  final x = Uint8List(32);
  final y = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    x[i] = i;
    y[i] = 32 + i;
  }
  final coseKeyBytes = Uint8List.fromList(
    cbor.encode(
      CborMap({CborSmallInt(-2): CborBytes(x), CborSmallInt(-3): CborBytes(y)}),
    ),
  );

  final de = CborMap({
    // key 1: security = [cipherSuiteId, coseKeyBytes]
    const CborSmallInt(1): CborList([
      const CborSmallInt(1),
      CborBytes(coseKeyBytes),
    ]),
    // key 2: connectionMethods = [[type=2, version=1, {uuidKey: uuid}]]
    const CborSmallInt(2): CborList([
      CborList([
        const CborSmallInt(2),
        const CborSmallInt(1),
        CborMap({CborSmallInt(uuidKey): CborBytes(uuid)}),
      ]),
    ]),
  });
  return Uint8List.fromList(cbor.encode(de));
}

void main() {
  group('extractUuid', () {
    test('extracts UUID from key 11 (peripheral server)', () {
      // 16-byte UUID
      final uuid = Uint8List.fromList([
        0x12,
        0x34,
        0x56,
        0x78,
        0x9a,
        0xbc,
        0xde,
        0xf0,
        0x12,
        0x34,
        0x56,
        0x78,
        0x9a,
        0xbc,
        0xde,
        0xf0,
      ]);
      final de = _buildDeviceEngagement(uuid, uuidKey: 11);
      final result = extractUuid(de);
      expect(result, equals('12345678-9abc-def0-1234-56789abcdef0'));
    });

    test('extracts UUID from key 10 (central client)', () {
      final uuid = Uint8List.fromList(List.generate(16, (i) => i + 0xa0));
      final de = _buildDeviceEngagement(uuid, uuidKey: 10);
      final result = extractUuid(de);
      expect(result.length, equals(36)); // UUID format with dashes
      expect(result.contains('-'), isTrue);
    });

    test('throws on missing connection methods', () {
      final de = Uint8List.fromList(
        cbor.encode(
          CborMap({
            const CborSmallInt(1): CborList([
              const CborSmallInt(1),
              CborBytes(Uint8List(10)),
            ]),
          }),
        ),
      );
      expect(() => extractUuid(de), throwsException);
    });

    test('throws on empty CBOR', () {
      final de = Uint8List.fromList(cbor.encode(CborMap({})));
      expect(() => extractUuid(de), throwsException);
    });
  });

  group('extractEDeviceKey', () {
    test('extracts 65-byte uncompressed public key', () {
      final uuid = Uint8List(16);
      final de = _buildDeviceEngagement(uuid);
      final key = extractEDeviceKey(de);
      expect(key.length, equals(65));
      expect(key[0], equals(0x04)); // uncompressed point marker
    });

    test('x and y coordinates match input', () {
      final uuid = Uint8List(16);
      final de = _buildDeviceEngagement(uuid);
      final key = extractEDeviceKey(de);
      // x was [0..31], y was [32..63]
      for (var i = 0; i < 32; i++) {
        expect(key[1 + i], equals(i));
        expect(key[33 + i], equals(32 + i));
      }
    });
  });

  group('buildDeviceRequest', () {
    test('produces valid CBOR', () {
      final request = buildDeviceRequest();
      expect(request.isNotEmpty, isTrue);
      // Should be decodable as CBOR
      final decoded = cbor.decode(request) as CborMap;
      expect(decoded[CborString('version')].toString(), equals('1.0'));
    });

    test('contains mDL docType', () {
      final request = buildDeviceRequest();
      final decoded = cbor.decode(request) as CborMap;
      final docRequests = decoded[CborString('docRequests')] as CborList;
      expect(docRequests.length, equals(1));
      final docRequest = docRequests[0] as CborMap;
      final itemsRequestTag = docRequest[CborString('itemsRequest')];
      // The itemsRequest is tag 24 wrapping CBOR bytes
      final itemsBytes = (itemsRequestTag as CborBytes).bytes;
      final itemsMap = cbor.decode(Uint8List.fromList(itemsBytes)) as CborMap;
      expect(
        itemsMap[CborString('docType')].toString(),
        equals('org.iso.18013.5.1.mDL'),
      );
    });

    test('requests expected attributes', () {
      final request = buildDeviceRequest();
      final decoded = cbor.decode(request) as CborMap;
      final docRequests = decoded[CborString('docRequests')] as CborList;
      final docRequest = docRequests[0] as CborMap;
      final itemsBytes =
          (docRequest[CborString('itemsRequest')] as CborBytes).bytes;
      final items = cbor.decode(Uint8List.fromList(itemsBytes)) as CborMap;
      final ns = items[CborString('nameSpaces')] as CborMap;
      final mdlNs = ns[CborString('org.iso.18013.5.1')] as CborMap;

      final expectedAttrs = [
        'given_name',
        'family_name',
        'birth_date',
        'document_number',
        'issuing_country',
        'expiry_date',
      ];
      for (final attr in expectedAttrs) {
        expect(
          mdlNs[CborString(attr)],
          isNotNull,
          reason: 'Missing attribute: $attr',
        );
      }
    });
  });

  group('buildSessionEstablishment', () {
    test('produces valid CBOR with eReaderKey and data', () {
      final key = Uint8List.fromList([0x01, 0x02, 0x03]);
      final data = Uint8List.fromList([0x04, 0x05]);
      final result = buildSessionEstablishment(key, data);

      final decoded = cbor.decode(result) as CborMap;
      expect(decoded[CborString('eReaderKey')], isNotNull);
      expect(decoded[CborString('data')], isNotNull);
    });

    test('eReaderKey is tagged with tag 24', () {
      final key = Uint8List.fromList([0xaa]);
      final data = Uint8List.fromList([0xbb]);
      final result = buildSessionEstablishment(key, data);
      final decoded = cbor.decode(result) as CborMap;
      final eReaderKey = decoded[CborString('eReaderKey')] as CborBytes;
      expect(eReaderKey.tags, contains(24));
    });
  });

  group('parseCredentials', () {
    test('returns empty map when no documents', () {
      final response = CborMap({CborString('version'): CborString('1.0')});
      final bytes = Uint8List.fromList(cbor.encode(response));
      expect(parseCredentials(bytes), isEmpty);
    });

    test('returns empty map with null documents', () {
      final response = CborMap({CborString('documents'): const CborNull()});
      final bytes = Uint8List.fromList(cbor.encode(response));
      // CborNull cast to CborList will throw, but parseCredentials
      // checks for null
      expect(parseCredentials(bytes), isEmpty);
    });

    test('parses credential fields from valid response', () {
      // Build a minimal DeviceResponse with one document
      final item1Bytes = Uint8List.fromList(
        cbor.encode(
          CborMap({
            CborString('elementIdentifier'): CborString('given_name'),
            CborString('elementValue'): CborString('Alice'),
          }),
        ),
      );
      final item2Bytes = Uint8List.fromList(
        cbor.encode(
          CborMap({
            CborString('elementIdentifier'): CborString('family_name'),
            CborString('elementValue'): CborString('Smith'),
          }),
        ),
      );

      final response = CborMap({
        CborString('documents'): CborList([
          CborMap({
            CborString('issuerSigned'): CborMap({
              CborString('nameSpaces'): CborMap({
                CborString('org.iso.18013.5.1'): CborList([
                  CborBytes(item1Bytes),
                  CborBytes(item2Bytes),
                ]),
              }),
            }),
          }),
        ]),
      });

      final bytes = Uint8List.fromList(cbor.encode(response));
      final fields = parseCredentials(bytes);
      expect(fields['given_name'], equals('Alice'));
      expect(fields['family_name'], equals('Smith'));
    });

    test('handles malformed items gracefully', () {
      final goodItem = Uint8List.fromList(
        cbor.encode(
          CborMap({
            CborString('elementIdentifier'): CborString('birth_date'),
            CborString('elementValue'): CborString('1990-01-01'),
          }),
        ),
      );
      // Bad item: not a valid CBOR map with expected keys
      final badItem = Uint8List.fromList([0x00, 0x01]);

      final response = CborMap({
        CborString('documents'): CborList([
          CborMap({
            CborString('issuerSigned'): CborMap({
              CborString('nameSpaces'): CborMap({
                CborString('org.iso.18013.5.1'): CborList([
                  CborBytes(badItem),
                  CborBytes(goodItem),
                ]),
              }),
            }),
          }),
        ]),
      });

      final bytes = Uint8List.fromList(cbor.encode(response));
      final fields = parseCredentials(bytes);
      // Should parse the good item and skip the bad one
      expect(fields['birth_date'], equals('1990-01-01'));
      expect(fields.length, equals(1));
    });

    test('handles multiple namespaces', () {
      final item1 = Uint8List.fromList(
        cbor.encode(
          CborMap({
            CborString('elementIdentifier'): CborString('given_name'),
            CborString('elementValue'): CborString('Bob'),
          }),
        ),
      );
      final item2 = Uint8List.fromList(
        cbor.encode(
          CborMap({
            CborString('elementIdentifier'): CborString('vehicle_class'),
            CborString('elementValue'): CborString('B'),
          }),
        ),
      );

      final response = CborMap({
        CborString('documents'): CborList([
          CborMap({
            CborString('issuerSigned'): CborMap({
              CborString('nameSpaces'): CborMap({
                CborString('org.iso.18013.5.1'): CborList([CborBytes(item1)]),
                CborString('org.iso.18013.5.1.aamva'): CborList([
                  CborBytes(item2),
                ]),
              }),
            }),
          }),
        ]),
      });

      final bytes = Uint8List.fromList(cbor.encode(response));
      final fields = parseCredentials(bytes);
      expect(fields.length, equals(2));
      expect(fields['given_name'], equals('Bob'));
      expect(fields['vehicle_class'], equals('B'));
    });
  });
}
