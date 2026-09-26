import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto/crypto.dart' show Digest;

/// Streaming SHA-256 for source files.
///
/// A scanned score can be tens of megabytes, and Android's per-app heap is far
/// smaller than that, so the hash is computed as a stream rather than by reading
/// the file into memory. Reading in fixed-size chunks also keeps a single large
/// allocation out of the heap on low-end devices.
abstract final class FileHasher {
  static const int _chunkSize = 64 * 1024;

  /// Returns the lowercase hex SHA-256 of [file].
  ///
  /// The read loop is written out by hand for two reasons.
  ///
  /// First, [crypto.Hash] consumes input chunks as a [Sink] and only produces
  /// its digest once that sink is closed, so `sha256.bind(stream).first` reports
  /// the digest of zero bytes.
  ///
  /// Second, `File.openRead(chunkSize)` does not honour its argument on this SDK
  /// (Dart 3.13.4): a 3-byte file read with a 64 KiB chunk size yields zero
  /// chunks, which would silently hash every file as empty and defeat exact
  /// duplicate detection. Reading through a [RandomAccessFile] keeps the memory
  /// bound explicit and independent of that behaviour.
  static Future<String> sha256(File file) async {
    final collector = _DigestCollector();
    final input = crypto.sha256.startChunkedConversion(collector);
    final handle = await file.open();

    try {
      while (true) {
        final chunk = await handle.read(_chunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
    } finally {
      await handle.close();
    }

    input.close();
    return collector.digest.toString();
  }

  /// Returns the SHA-256 of [bytes], for small in-memory payloads.
  static String sha256Bytes(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}

class _DigestCollector implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}

  Digest get digest {
    final digest = _digest;
    if (digest == null) {
      throw StateError('The hash produced no digest; the stream was empty.');
    }
    return digest;
  }
}
