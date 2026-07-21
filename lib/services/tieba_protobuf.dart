import 'dart:typed_data';
import 'dart:convert';

class ProtobufWriter {
  final BytesBuilder _buffer = BytesBuilder();

  void writeField(int fieldNumber, int wireType, dynamic value) {
    final tag = (fieldNumber << 3) | wireType;
    _writeVarint(tag);
    switch (wireType) {
      case 0:
        _writeVarint(value as int);
        break;
      case 2:
        if (value is String) {
          final bytes = utf8.encode(value);
          _writeVarint(bytes.length);
          _buffer.add(bytes);
        } else if (value is Uint8List) {
          _writeVarint(value.length);
          _buffer.add(value);
        } else if (value is List<int>) {
          _writeVarint(value.length);
          _buffer.add(value);
        }
        break;
      case 5:
        _buffer.addByte(value & 0xFF);
        _buffer.addByte((value >> 8) & 0xFF);
        _buffer.addByte((value >> 16) & 0xFF);
        _buffer.addByte((value >> 24) & 0xFF);
        break;
      case 1:
        for (var i = 0; i < 8; i++) {
          _buffer.addByte((value >> (i * 8)) & 0xFF);
        }
        break;
    }
  }

  void writeInt32(int fieldNumber, int value) =>
      writeField(fieldNumber, 0, value);
  void writeInt64(int fieldNumber, int value) =>
      writeField(fieldNumber, 0, value);
  void writeString(int fieldNumber, String value) =>
      writeField(fieldNumber, 2, value);
  void writeMessage(int fieldNumber, Uint8List messageBytes) =>
      writeField(fieldNumber, 2, messageBytes);

  Uint8List toBytes() => _buffer.toBytes();

  void _writeVarint(int value) {
    while (value > 0x7F) {
      _buffer.addByte((value & 0x7F) | 0x80);
      value >>= 7;
    }
    _buffer.addByte(value & 0x7F);
  }
}

class ProtobufReader {
  final Uint8List _data;
  int _pos = 0;

  ProtobufReader(this._data);
  bool get hasMore => _pos < _data.length;

  (int, int)? readTag() {
    if (!hasMore) return null;
    final tag = _readVarint();
    return (tag >> 3, tag & 0x07);
  }

  int readVarint() => _readVarint();

  String readString() {
    final length = _readVarint();
    final bytes = _data.sublist(_pos, _pos + length);
    _pos += length;
    return utf8.decode(bytes);
  }

  Uint8List readBytes() {
    final length = _readVarint();
    final bytes = _data.sublist(_pos, _pos + length);
    _pos += length;
    return bytes;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        _readVarint();
        break;
      case 2:
        final len = _readVarint();
        _pos += len;
        break;
      case 5:
        _pos += 4;
        break;
      case 1:
        _pos += 8;
        break;
    }
  }

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _data[_pos++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }
}
