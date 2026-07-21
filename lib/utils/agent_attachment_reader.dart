import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class AgentAttachmentReadResult {
  final String fileName;
  final String mimeType;
  final String text;
  final bool success;
  final String? error;

  const AgentAttachmentReadResult({
    required this.fileName,
    required this.mimeType,
    required this.text,
    required this.success,
    this.error,
  });
}

abstract final class AgentAttachmentReader {
  AgentAttachmentReader._();

  static const maxFileBytes = 512 * 1024;
  static const maxExtractChars = 48000;

  static const _textExtensions = {
    'txt',
    'md',
    'markdown',
    'json',
    'csv',
    'tsv',
    'xml',
    'html',
    'htm',
    'yaml',
    'yml',
    'log',
    'ini',
    'cfg',
    'conf',
    'dart',
    'py',
    'js',
    'ts',
    'jsx',
    'tsx',
    'java',
    'kt',
    'go',
    'rs',
    'c',
    'cpp',
    'h',
    'cs',
    'sql',
    'sh',
    'bat',
    'ps1',
    'env',
    'toml',
  };

  static Future<AgentAttachmentReadResult> read({
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = name.trim().isEmpty ? '未命名文件' : name.trim();
    final mimeType = mimeFromName(fileName);
    final ext = extension(fileName);

    if (bytes.isEmpty) {
      return _fail(fileName, mimeType, '文件为空或无法读取');
    }
    if (bytes.length > maxFileBytes) {
      return _fail(fileName, mimeType, '文件过大（最大 ${maxFileBytes ~/ 1024}KB）');
    }

    if (_isTextLike(ext, mimeType)) {
      return _readText(fileName, mimeType, bytes);
    }
    if (ext == 'docx') {
      return _readDocx(fileName, mimeType, bytes);
    }
    if (ext == 'pdf') {
      return _fail(fileName, mimeType, 'PDF 暂不支持直接解析，请改用 txt / md / docx');
    }

    return _fail(
      fileName,
      mimeType,
      '暂不支持 .$ext，请换 txt / md / json / csv / docx',
    );
  }

  static String extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot >= name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String mimeFromName(String name) {
    return switch (extension(name)) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'bmp' => 'image/bmp',
      'jpg' || 'jpeg' => 'image/jpeg',
      'pdf' => 'application/pdf',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'json' => 'application/json',
      'csv' => 'text/csv',
      'xml' => 'application/xml',
      'html' || 'htm' => 'text/html',
      'md' || 'markdown' => 'text/markdown',
      _ => 'text/plain',
    };
  }

  static bool isImageName(String name) {
    return switch (extension(name)) {
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'webp' ||
      'heic' ||
      'heif' ||
      'bmp' => true,
      _ => false,
    };
  }

  static String buildOutboundText({
    required String userText,
    required AgentAttachmentReadResult file,
  }) {
    final buf = StringBuffer();
    final trimmed = userText.trim();
    if (trimmed.isNotEmpty) {
      buf.writeln(trimmed);
      buf.writeln();
    }
    buf.writeln('--- 附件：${file.fileName} ---');
    if (file.success && file.text.trim().isNotEmpty) {
      buf.write(file.text.trim());
    } else if (file.error != null && file.error!.trim().isNotEmpty) {
      buf.write('[读取失败：${file.error!.trim()}]');
    } else {
      buf.write('[附件无可用文本内容]');
    }
    return buf.toString().trim();
  }

  static bool _isTextLike(String ext, String mimeType) {
    if (_textExtensions.contains(ext)) return true;
    return mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml';
  }

  static AgentAttachmentReadResult _readText(
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) {
    final decoded = _decodeText(bytes);
    if (decoded == null || decoded.trim().isEmpty) {
      return _fail(fileName, mimeType, '未能解析为文本');
    }
    return AgentAttachmentReadResult(
      fileName: fileName,
      mimeType: mimeType,
      text: _truncate(decoded),
      success: true,
    );
  }

  static AgentAttachmentReadResult _readDocx(
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final entry = archive.files.cast<ArchiveFile?>().firstWhere(
        (f) => f?.name == 'word/document.xml',
        orElse: () => null,
      );
      if (entry == null) {
        return _fail(fileName, mimeType, 'docx 内缺少 document.xml');
      }
      final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final text = _stripXml(xml);
      if (text.trim().isEmpty) {
        return _fail(fileName, mimeType, 'docx 中没有可提取的文字');
      }
      return AgentAttachmentReadResult(
        fileName: fileName,
        mimeType: mimeType,
        text: _truncate(text),
        success: true,
      );
    } catch (_) {
      return _fail(fileName, mimeType, 'docx 解析失败');
    }
  }

  static String? _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static String _stripXml(String xml) {
    final withBreaks = xml
        .replaceAll(RegExp(r'</w:p>'), '\n')
        .replaceAll(RegExp(r'<w:tab[^>]*/>'), '\t')
        .replaceAll(RegExp(r'<w:br[^>]*/>'), '\n');
    final stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
    return stripped
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _truncate(String text) {
    if (text.length <= maxExtractChars) return text;
    return '${text.substring(0, maxExtractChars)}\n\n…（已截断，原文过长）';
  }

  static AgentAttachmentReadResult _fail(
    String fileName,
    String mimeType,
    String error,
  ) {
    return AgentAttachmentReadResult(
      fileName: fileName,
      mimeType: mimeType,
      text: '',
      success: false,
      error: error,
    );
  }
}
