import 'dart:io';

import 'package:belatuk_http_server/belatuk_http_server.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group('VirtualDirectory', () {
    testVirtualDir('a path with invalid percent-escapes is a bad request', (
      dir,
    ) async {
      var virDir = VirtualDirectory(dir.path);

      var (status, _, _) = await fetchResponse(virDir, '/%FF');
      expect(status, HttpStatus.badRequest);
    });

    testVirtualDir('a directory redirect keeps the query string', (dir) async {
      Directory('${dir.path}/docs').createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      var (status, headers, _) = await fetchResponse(virDir, '/docs?lang=en');
      expect(status, HttpStatus.movedPermanently);
      expect(headers.value(HttpHeaders.locationHeader), '/docs/?lang=en');
    });

    testVirtualDir('a directory redirect stays on this host', (dir) async {
      Directory('${dir.path}/docs').createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      // `//evil.com/docs` parses as host `evil.com` and path `/docs`.
      var (status, headers, _) = await fetchResponse(
        virDir,
        '//evil.com/docs?x=1',
      );
      expect(status, HttpStatus.movedPermanently);
      expect(headers.value(HttpHeaders.locationHeader), '/docs/?x=1');

      // `/.//docs` normalizes to the path `//docs`, which a plain redirect
      // would write as the protocol-relative `////docs/`.
      (status, headers, _) = await fetchResponse(
        virDir,
        '/.//docs',
        rawTarget: true,
      );
      expect(status, HttpStatus.movedPermanently);
      expect(headers.value(HttpHeaders.locationHeader), '/docs/');
    });

    testVirtualDir('a failing error page handler still closes the response', (
      dir,
    ) async {
      var virDir = VirtualDirectory(dir.path)
        ..errorPageHandler = (request) {
          // Throws for a path whose percent-escapes are not valid UTF-8.
          request.uri.pathSegments;
        };

      var (status, _, _) = await fetchResponse(
        virDir,
        '/%FF',
      ).timeout(const Duration(seconds: 5));
      expect(status, HttpStatus.badRequest);
    });

    testVirtualDir('a range larger than an int is handled like any other', (
      dir,
    ) async {
      File('${dir.path}/file').writeAsBytesSync(List.filled(10, 0));
      var virDir = VirtualDirectory(dir.path);

      var (status, headers, _) = await fetchResponse(
        virDir,
        '/file',
        headers: {HttpHeaders.rangeHeader: 'bytes=0-99999999999999999999'},
      );
      expect(status, HttpStatus.partialContent);
      expect(headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-9/10');

      // A start past the end of the file is ignored, as for small values.
      (status, _, _) = await fetchResponse(
        virDir,
        '/file',
        headers: {HttpHeaders.rangeHeader: 'bytes=99999999999999999999-'},
      );
      expect(status, HttpStatus.ok);
    });

    testVirtualDir('a directory listing is modified when a file in it is', (
      dir,
    ) async {
      var file = File('${dir.path}/file')..createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      // HTTP dates have no fraction of a second.
      var later = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000 *
            1000,
        isUtc: true,
      );
      var (status, _, _) = await fetchResponse(
        virDir,
        '/',
        ifModifiedSince: later,
      );
      expect(status, HttpStatus.notModified);

      // The directory itself is unchanged, but the file in it is newer.
      file.setLastModifiedSync(later.add(const Duration(hours: 1)));
      (status, _, _) = await fetchResponse(virDir, '/', ifModifiedSince: later);
      expect(status, HttpStatus.ok);
    });

    testVirtualDir('a HEAD request for a listing has no body', (dir) async {
      File('${dir.path}/file').createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      var (status, headers, body) = await fetchResponse(
        virDir,
        '/',
        method: 'HEAD',
      );
      expect(status, HttpStatus.ok);
      expect(headers.value(HttpHeaders.lastModifiedHeader), isNotNull);
      expect(body, isEmpty);
    });
  });
}
