import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:hashlib/hashlib.dart' show xxh32;

/// 生成贴吧客户端 `cuid_galaxy2`（对齐 aiotieba / 官方 12.x）。
class TiebaCuid {
  TiebaCuid._();

  static const _prefix = 'com.baidu';
  static const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String cuidGalaxy2(String androidId) {
    if (androidId.length != 16) {
      throw ArgumentError('android_id must be 16 hex chars');
    }
    final md5Hex = crypto.md5
        .convert(utf8.encode('$_prefix$androidId'))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final helios = _heliosHash(utf8.encode(md5Hex));
    return '$md5Hex|V${_base32Encode(helios)}';
  }

  static Uint8List _heliosHash(Uint8List src) {
    const stepSize = 5;
    final buffer = BytesBuilder(copy: false)
      ..add(src)
      ..add(Uint8List(stepSize)..fillRange(0, stepSize, 0xFF));
    var sec = (BigInt.one << 40) - BigInt.one;
    var buffOffset = src.length + stepSize;

    sec = _update(
      sec,
      _crc32(buffer.toBytes().sublist(0, buffOffset)),
      8,
      false,
    );
    buffer.add(_writeBuffer(sec));
    buffOffset += stepSize;

    sec = _update(
      sec,
      xxh32.convert(buffer.toBytes().sublist(0, buffOffset)).number(),
      0,
      true,
    );
    buffer.add(_writeBuffer(sec));
    buffOffset += stepSize;

    sec = _update(
      sec,
      xxh32.convert(buffer.toBytes().sublist(0, buffOffset)).number(),
      1,
      true,
    );
    buffer.add(_writeBuffer(sec));
    buffOffset += stepSize;

    sec = _update(
      sec,
      _crc32(buffer.toBytes().sublist(0, buffOffset)),
      7,
      true,
    );
    return _writeBuffer(sec);
  }

  static BigInt _update(BigInt sec, int hashVal, int start, bool xorMode) {
    final end = start + 32;
    var secTemp = sec;
    final mask = (BigInt.one << end) - BigInt.one;
    var var5 = ((mask & sec) >> start).toInt();
    var5 = xorMode ? (var5 ^ hashVal) : (var5 & hashVal);
    for (var i = 0; i < 32; i++) {
      final opIdx = start + i;
      if ((var5 & (1 << i)) != 0) {
        secTemp |= BigInt.one << opIdx;
      } else {
        secTemp &= ~(BigInt.one << opIdx);
      }
    }
    return secTemp;
  }

  static Uint8List _writeBuffer(BigInt sec) {
    var tmp = sec.toInt();
    return Uint8List.fromList(
      List.generate(5, (i) {
        final b = tmp & 0xFF;
        tmp >>= 8;
        return b;
      }),
    );
  }

  static int _crc32(List<int> data) {
    const polynomial = 0xEDB88320;
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ polynomial : crc >> 1;
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }

  static String _base32Encode(Uint8List data) {
    final out = StringBuffer();
    for (var i = 0; i < data.length; i += 5) {
      final chunk = data.sublist(i, i + 5 > data.length ? data.length : i + 5);
      out.write(_encodeSequence(chunk));
    }
    return out.toString();
  }

  static String _encodeSequence(Uint8List plain) {
    final coded = List.filled(8, '=');
    for (var block = 0; block < 8; block++) {
      final octet = (block * 5) ~/ 8;
      final junk = 8 - 5 - ((5 * block) % 8);
      if (octet >= plain.length) break;
      var c = _shiftRight(plain[octet], junk);
      if (junk < 0 && octet < plain.length - 1) {
        c |= _shiftRight(plain[octet + 1], 8 + junk);
      }
      coded[block] = _base32Alphabet[c & 0x1F];
    }
    return coded.join();
  }

  static int _shiftRight(int byte, int offset) {
    if (offset > 0) return (byte >> offset) & 0xFF;
    return (byte << -offset) & 0xFF;
  }
}
