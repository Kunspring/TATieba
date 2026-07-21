import 'dart:typed_data';

import 'local_file_bytes_io.dart'
    if (dart.library.html) 'local_file_bytes_stub.dart'
    as impl;

Future<Uint8List?> readLocalFileBytes(String path) =>
    impl.readLocalFileBytes(path);
