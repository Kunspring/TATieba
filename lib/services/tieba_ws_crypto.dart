import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 贴吧 IM WebSocket 加解密（对齐 aiotieba）。
abstract final class TiebaWsCrypto {
  TiebaWsCrypto._();

  static const _pbkdf2Salt = [0xa4, 0x0b, 0xc8, 0x34, 0xd6, 0x95, 0xf3, 0x13];
  static final _rsaPublicKey = RSAPublicKey(
    BigInt.parse(
      '243691398237448911081561968728531555914523337605734159577088637715'
      '064263985161588999932378843838084518933211506437334993623503382576'
      '349644893252166991340652097478623067391932897400416048832590091424'
      '191939408595985152814457280838151351027500978318743098745063091424'
      '864326605212576474551195952893055714550279316135699963158025798799'
      '141936979669702854627201917883128674126237846305676187404950467746'
      '639266666837379716666474481773760399776514930762057558317093018031'
      '708137855096004642404476880128813326989615544108725147260698523974'
      '328834201723026402790882487237529106840182392113399248464518969236'
      '72864869598664677249823',
    ),
    BigInt.from(65537),
  );

  static Uint8List randomAesSecKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(31, (_) => rng.nextInt(256)));
  }

  static Uint8List deriveAesKey(Uint8List secKey) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(_pbkdf2Salt), 5, 32));
    return derivator.process(secKey);
  }

  static Uint8List rsaEncryptSecretKey(Uint8List secKey) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(_rsaPublicKey));
    return engine.process(secKey);
  }

  static Uint8List aesEcbEncrypt(Uint8List aesKey, Uint8List plain) {
    final padded = _pkcs7Pad(plain, 16);
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, KeyParameter(aesKey));
    final out = Uint8List(padded.length);
    for (var i = 0; i < padded.length; i += 16) {
      cipher.processBlock(padded, i, out, i);
    }
    return out;
  }

  static Uint8List aesEcbDecrypt(Uint8List aesKey, Uint8List encrypted) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(false, KeyParameter(aesKey));
    final out = Uint8List(encrypted.length);
    for (var i = 0; i < encrypted.length; i += 16) {
      cipher.processBlock(encrypted, i, out, i);
    }
    return _pkcs7Unpad(out);
  }

  static Uint8List packWsFrame({
    required Uint8List aesKey,
    required Uint8List payload,
    required int cmd,
    required int reqId,
    bool compress = false,
    bool encrypt = true,
  }) {
    var flag = 0x08;
    var data = payload;
    if (compress) {
      flag |= 0x40;
      data = Uint8List.fromList(gzip.encode(data));
    }
    if (encrypt) {
      flag |= 0x80;
      data = aesEcbEncrypt(aesKey, data);
    }
    final header = Uint8List(9);
    header[0] = flag;
    _writeInt32Be(header, 1, cmd);
    _writeInt32Be(header, 5, reqId);
    return Uint8List.fromList([...header, ...data]);
  }

  static (Uint8List body, int cmd, int reqId) parseWsFrame(
    Uint8List aesKey,
    Uint8List frame,
  ) {
    if (frame.length < 9) {
      throw FormatException('WS frame too short');
    }
    final flag = frame[0];
    final cmd = _readInt32Be(frame, 1);
    final reqId = _readInt32Be(frame, 5);
    var data = frame.sublist(9);
    if (flag & 0x80 != 0) {
      data = aesEcbDecrypt(aesKey, data);
    }
    if (flag & 0x40 != 0) {
      data = Uint8List.fromList(gzip.decode(data));
    }
    return (data, cmd, reqId);
  }

  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final pad = blockSize - (data.length % blockSize);
    final out = BytesBuilder(copy: false)..add(data);
    out.add(List.filled(pad, pad));
    return out.toBytes();
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final pad = data.last;
    if (pad <= 0 || pad > data.length) return data;
    return data.sublist(0, data.length - pad);
  }

  static void _writeInt32Be(Uint8List buf, int offset, int value) {
    buf[offset] = (value >> 24) & 0xff;
    buf[offset + 1] = (value >> 16) & 0xff;
    buf[offset + 2] = (value >> 8) & 0xff;
    buf[offset + 3] = value & 0xff;
  }

  static int _readInt32Be(Uint8List buf, int offset) {
    return (buf[offset] << 24) |
        (buf[offset + 1] << 16) |
        (buf[offset + 2] << 8) |
        buf[offset + 3];
  }
}
