import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belatuk_http_server/belatuk_http_server.dart';
import 'package:test/test.dart';

import 'http_fakes.dart';
import 'utils.dart';

void main() {
  group('VirtualDirectory', () {
    testVirtualDir('a path with invalid percent-escapes is a bad request', (
      dir,
    ) async {
      var virDir = VirtualDirectory(dir.path);

      var (status, _) = await fetchResponse(virDir, '/%FF');
      expect(status, HttpStatus.badRequest);
    });

    testVirtualDir('a directory redirect keeps the query string', (dir) async {
      Directory('${dir.path}/docs').createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      var (status, headers) = await fetchResponse(virDir, '/docs?lang=en');
      expect(status, HttpStatus.movedPermanently);
      expect(headers.value(HttpHeaders.locationHeader), '/docs/?lang=en');
    });

    testVirtualDir('a range larger than an int is handled like any other', (
      dir,
    ) async {
      File('${dir.path}/file').writeAsBytesSync(List.filled(10, 0));
      var virDir = VirtualDirectory(dir.path);

      var (status, headers) = await fetchResponse(
        virDir,
        '/file',
        headers: {HttpHeaders.rangeHeader: 'bytes=0-99999999999999999999'},
      );
      expect(status, HttpStatus.partialContent);
      expect(headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-9/10');

      // A start past the end of the file is ignored, as for small values.
      (status, _) = await fetchResponse(
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
      var (status, _) = await fetchResponse(
        virDir,
        '/',
        ifModifiedSince: later,
      );
      expect(status, HttpStatus.notModified);

      // The directory itself is unchanged, but the file in it is newer.
      file.setLastModifiedSync(later.add(const Duration(hours: 1)));
      (status, _) = await fetchResponse(virDir, '/', ifModifiedSince: later);
      expect(status, HttpStatus.ok);
    });

    testVirtualDir('a HEAD request for a listing has no body', (dir) async {
      File('${dir.path}/file').createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      var (status, headers) = await fetchResponse(virDir, '/', method: 'HEAD');
      expect(status, HttpStatus.ok);
      expect(headers.value(HttpHeaders.lastModifiedHeader), isNotNull);
    });

    // A real server drops a HEAD response's body itself, so only the fakes
    // show whether one was written.
    test('a HEAD request for a listing writes no body, with fakes', () async {
      var dir = Directory.systemTemp.createTempSync('http_server_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/file').createSync();
      var virDir = VirtualDirectory(dir.path)..allowDirectoryListing = true;

      var request = FakeHttpRequest(
        Uri.parse('/'),
        method: 'HEAD',
        data: StreamController<Uint8List>().stream,
      );
      await virDir.serveRequest(request);
      expect(request.response.fakeContent, isEmpty);
    });
  });

  group('HttpBodyHandler', () {
    /// Posts [body] with [contentType], and returns what
    /// [HttpBodyHandler.processRequest] returns or the error it fails with.
    Future<Object?> process(
      String contentType,
      List<int> body, {
      Encoding defaultEncoding = utf8,
    }) async {
      var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var result = Completer<Object?>();
      server.listen((request) async {
        try {
          var body = await HttpBodyHandler.processRequest(
            request,
            defaultEncoding: defaultEncoding,
          );
          await request.response.close();
          result.complete(body);
        } catch (e) {
          result.complete(e);
        }
      });

      var client = HttpClient();
      try {
        var request = await client.post('localhost', server.port, '/');
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
        request.add(body);
        var response = await request.close();
        await response.drain<void>();
        return await result.future;
      } finally {
        client.close();
        await server.close();
      }
    }

    test('a form body is decoded with its charset', () async {
      var result = await process(
        'application/x-www-form-urlencoded; charset=utf-8',
        utf8.encode('raw=€&escaped=%C3%A9'),
        defaultEncoding: latin1,
      );
      expect(result, isA<HttpRequestBody>());
      expect((result as HttpRequestBody).body, {'raw': '€', 'escaped': 'é'});
    });

    Future<Object?> processError(String contentType, String body) =>
        process(contentType, utf8.encode(body));

    test('a multipart body without a boundary is an HttpException', () async {
      expect(
        await processError('multipart/form-data', ''),
        isA<HttpException>(),
      );
    });

    test('a multipart part without a name is an HttpException', () async {
      var body =
          '--AaB03x\r\n'
          'Content-Disposition: form-data; filename="a.txt"\r\n'
          '\r\n'
          'content\r\n'
          '--AaB03x--\r\n';
      expect(
        await processError('multipart/form-data; boundary=AaB03x', body),
        isA<HttpException>(),
      );
    });
  });
}
