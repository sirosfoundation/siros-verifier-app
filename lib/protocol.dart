import 'dart:typed_data';
import 'package:cbor/cbor.dart';
import 'crypto.dart';

/// Build a DeviceRequest for mDL attributes (given_name, family_name, etc.).
Uint8List buildDeviceRequest() {
  final itemsRequestBytes = Uint8List.fromList(cbor.encode(CborMap({
    CborString('docType'): CborString('org.iso.18013.5.1.mDL'),
    CborString('nameSpaces'): CborMap({
      CborString('org.iso.18013.5.1'): CborMap({
        CborString('given_name'): const CborBool(false),
        CborString('family_name'): const CborBool(false),
        CborString('birth_date'): const CborBool(false),
        CborString('document_number'): const CborBool(false),
        CborString('issuing_country'): const CborBool(false),
        CborString('expiry_date'): const CborBool(false),
      }),
    }),
  })));
  final docRequest = CborMap({
    CborString('itemsRequest'): CborBytes(itemsRequestBytes, tags: [24]),
  });
  final deviceRequest = CborMap({
    CborString('version'): CborString('1.0'),
    CborString('docRequests'): CborList([docRequest]),
  });
  return Uint8List.fromList(cbor.encode(deviceRequest));
}

/// Build SessionEstablishment CBOR:
/// {"eReaderKey": #6.24(eReaderKeyCose), "data": encryptedRequest}
Uint8List buildSessionEstablishment(
    Uint8List eReaderKeyCose, Uint8List encryptedRequest) {
  final se = CborMap({
    CborString('eReaderKey'): CborBytes(eReaderKeyCose, tags: [24]),
    CborString('data'): CborBytes(encryptedRequest),
  });
  return Uint8List.fromList(cbor.encode(se));
}

/// Extract the BLE service UUID from a device engagement CBOR structure.
String extractUuid(Uint8List deBytes) {
  try {
    final decoded = cbor.decode(deBytes) as CborMap;
    final connMethods = decoded[const CborSmallInt(2)] as CborList?;
    if (connMethods == null) throw Exception('No connection methods');
    for (final method in connMethods) {
      final m = method as CborList;
      if ((m[0] as CborSmallInt).value == 2) {
        final options = m[2] as CborMap;
        for (final key in [10, 11]) {
          final uuidItem = options[CborSmallInt(key)];
          if (uuidItem != null) {
            final uuidBytes =
                Uint8List.fromList((uuidItem as CborBytes).bytes);
            final h = uuidBytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join();
            return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
                '${h.substring(12, 16)}-${h.substring(16, 20)}-'
                '${h.substring(20)}';
          }
        }
      }
    }
  } catch (e) {
    if (e is Exception && e.toString().contains('No connection methods')) {
      rethrow;
    }
    // fall through to throw below
  }
  throw Exception('UUID not found');
}

/// Extract the eDeviceKey uncompressed public key bytes from device engagement.
Uint8List extractEDeviceKey(Uint8List deBytes) {
  final decoded = cbor.decode(deBytes) as CborMap;
  final security = decoded[const CborSmallInt(1)] as CborList;
  final coseKeyBytes =
      Uint8List.fromList((security[1] as CborBytes).bytes);
  final coseKey = cbor.decode(coseKeyBytes) as CborMap;
  final x = Uint8List.fromList(
      (coseKey[CborSmallInt(-2)] as CborBytes).bytes);
  final y = Uint8List.fromList(
      (coseKey[CborSmallInt(-3)] as CborBytes).bytes);
  return concat([Uint8List.fromList([0x04]), x, y]);
}

/// Parse credential fields from a decrypted DeviceResponse.
Map<String, String> parseCredentials(Uint8List decrypted) {
  final fields = <String, String>{};
  final deviceResponse = cbor.decode(decrypted) as CborMap;
  final documents =
      deviceResponse[CborString('documents')] as CborList?;
  if (documents == null) return fields;
  for (final doc in documents) {
    final docMap = doc as CborMap;
    final issuerSigned =
        docMap[CborString('issuerSigned')] as CborMap?;
    final nameSpaces =
        issuerSigned?[CborString('nameSpaces')] as CborMap?;
    nameSpaces?.entries.forEach((ns) {
      final items = ns.value as CborList?;
      items?.forEach((item) {
        try {
          final itemBytes = (item as CborBytes).bytes;
          final itemMap =
              cbor.decode(Uint8List.fromList(itemBytes)) as CborMap;
          final key =
              itemMap[CborString('elementIdentifier')].toString();
          final value = itemMap[CborString('elementValue')];
          fields[key] = value.toString();
        } catch (_) {}
      });
    });
  }
  return fields;
}
