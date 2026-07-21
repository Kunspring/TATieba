import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:tieba_app/utils/tieba_cuid.dart';

void main() {
  final md5Hex = md5
      .convert(utf8.encode('com.baidu0000000000000000'))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  print('md5 $md5Hex');

  final src = utf8.encode(md5Hex);
  const stepSize = 5;
  final buffer = BytesBuilder(copy: false)
    ..add(src)
    ..add(Uint8List(stepSize)..fillRange(0, stepSize, 0xFF));
  var sec = (BigInt.one << 40) - BigInt.one;
  print('init sec ${sec.toRadixString(16)}');
  var buffOffset = src.length + stepSize;

  final crc1 = _crc32(buffer.toBytes().sublist(0, buffOffset));
  print('crc1 ${crc1.toRadixString(16)} len $buffOffset');
  sec = _update(sec, crc1, 8, false);
  print('sec after crc1 ${sec.toRadixString(16)}');
  final wb1 = _writeBuffer(sec);
  print('write1 ${wb1.toList()}');
  buffer.add(wb1);
  buffOffset += stepSize;

  final xx1 = _xxhash32(buffer.toBytes().sublist(0, buffOffset));
  print('xx1 ${xx1.toRadixString(16)} len $buffOffset');
  sec = _update(sec, xx1, 0, true);
  print('sec after xx1 ${sec.toRadixString(16)}');
  buffer.add(_writeBuffer(sec));
  buffOffset += stepSize;

  final xx2 = _xxhash32(buffer.toBytes().sublist(0, buffOffset));
  print('xx2 ${xx2.toRadixString(16)}');
  sec = _update(sec, xx2, 1, true);
  buffer.add(_writeBuffer(sec));
  buffOffset += stepSize;

  final crc2 = _crc32(buffer.toBytes().sublist(0, buffOffset));
  print('crc2 ${crc2.toRadixString(16)}');
  sec = _update(sec, crc2, 7, true);
  final result = _writeBuffer(sec);
  print('result bytes ${result.toList()}');
  print('full ${TiebaCuid.cuidGalaxy2('0000000000000000')}');
}

BigInt _update(BigInt sec, int hashVal, int start, bool xorMode) {
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

Uint8List _writeBuffer(BigInt sec) {
  var tmp = sec.toInt();
  return Uint8List.fromList(
    List.generate(5, (i) {
      final b = tmp & 0xFF;
      tmp >>= 8;
      return b;
    }),
  );
}

int _crc32(List<int> data) {
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

int _xxhash32(List<int> input) {
  const prime1 = 0x9E3779B1;
  const prime2 = 0x85EBCA77;
  const prime3 = 0xC2B2AE3D;
  const prime4 = 0x27D4EB2F;
  const prime5 = 0x165667B1;
  const prime32 = 0x85EBCA77;

  var offset = 0;
  final length = input.length;
  var h32 = 0;

  if (length >= 16) {
    final limit = length - 16;
    var v1 = (0 + prime1 + prime2).toSigned(32);
    var v2 = (0 + prime2).toSigned(32);
    var v3 = (0).toSigned(32);
    var v4 = (-prime1).toSigned(32);

    while (offset <= limit) {
      v1 = _xxRound(v1, _readLE32(input, offset));
      offset += 4;
      v2 = _xxRound(v2, _readLE32(input, offset));
      offset += 4;
      v3 = _xxRound(v3, _readLE32(input, offset));
      offset += 4;
      v4 = _xxRound(v4, _readLE32(input, offset));
      offset += 4;
    }

    h32 = _rotl32(v1, 1) + _rotl32(v2, 7) + _rotl32(v3, 12) + _rotl32(v4, 18);
    h32 = h32.toSigned(32);
  } else {
    h32 = (0 + prime5).toSigned(32);
  }

  h32 = (h32 + length).toSigned(32);

  while (offset <= length - 4) {
    h32 = (h32 + _readLE32(input, offset) * prime3).toSigned(32);
    h32 = _rotl32(h32, 17) * prime4;
    h32 = h32.toSigned(32);
    offset += 4;
  }

  while (offset < length) {
    h32 = (h32 + input[offset] * prime5).toSigned(32);
    h32 = _rotl32(h32, 11) * prime32;
    h32 = h32.toSigned(32);
    offset++;
  }

  h32 ^= h32 >> 15;
  h32 = (h32 * prime2).toSigned(32);
  h32 ^= h32 >> 13;
  h32 = (h32 * prime3).toSigned(32);
  h32 ^= h32 >> 16;
  return h32.toUnsigned(32);
}

int _readLE32(List<int> data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

int _rotl32(int value, int shift) {
  return ((value << shift) | (value.toUnsigned(32) >> (32 - shift))).toSigned(
    32,
  );
}

int _xxRound(int acc, int input) {
  const prime2 = 0x85EBCA77;
  const prime1 = 0x9E3779B1;
  acc = (acc + input * prime2).toSigned(32);
  acc = _rotl32(acc, 13);
  acc = (acc * prime1).toSigned(32);
  return acc;
}
