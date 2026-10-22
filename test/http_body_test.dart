// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belatuk_http_server/belatuk_http_server.dart';
import 'package:test/test.dart';

import 'http_fakes.dart';

Future<void> _testHttpClientResponseBody() async {
  Future<void> check(
    String mimeType,
    List<int> content,
    dynamic expectedBody,
    String type, [
    bool shouldFail = false,
  ]) async {
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.listen(
        (_) {},
        onDone: () {
          request.response.headers.contentType = ContentType.parse(mimeType);
          request.response.add(content);
          request.response.close();
        },
      );
    });

    var client = HttpClient();
    try {
      var request = await client.get('127.0.0.1', server.port, '/');
      var response = await request.close();
      var body = await HttpBodyHandler.processResponse(response);
      expect(shouldFail, isFalse);
      expect(body.type, equals(type));
      expect(body.response, isNotNull);
      switch (type) {
        case 'text':
        case 'json':
          expect(body.body, equals(expectedBody));
          break;

        default:
          fail('bad body type');
      }
    } on TestFailure {
      rethrow;
    } catch (_) {
      if (!shouldFail) rethrow;
    } finally {
      client.close();
      await server.close();
    }
  }

  await check('text/plain', 'body'.codeUnits, 'body', 'text');
  await check('text/plain; charset=utf-8', 'body'.codeUnits, 'body', 'text');
  await check(
    'text/plain; charset=iso-8859-1',
    'body'.codeUnits,
    'body',
    'text',
  );
  await check('text/plain; charset=us-ascii', 'body'.codeUnits, 'body', 'text');
  await check('text/plain; charset=utf-8', [42], '*', 'text');
  await check('text/plain; charset=us-ascii', [142], null, 'text', true);
  await check('text/plain; charset=utf-8', [142], null, 'text', true);

  await check('application/json', '{"val": 5}'.codeUnits, {'val': 5}, 'json');
  await check('application/json', '{ bad json }'.codeUnits, null, 'json', true);
}

Future<void> _testHttpServerRequestBody() async {
  Future<void> check(
    String? mimeType,
    List<int> content,
    dynamic expectedBody,
    String type, {
    bool shouldFail = false,
    Matcher? error,
    Encoding defaultEncoding = utf8,
  }) async {
    if (error != null) shouldFail = true;
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // What the handler produced: the parsed body, or the error it failed with.
    var outcome = Completer<Object>();
    server
        .transform(HttpBodyHandler(defaultEncoding: defaultEncoding))
        .listen(
          (body) {
            outcome.complete(body);
            if (shouldFail) {
              body.request.response.close();
              return;
            }
            expect(body.type, equals(type));
            switch (type) {
              case 'text':
                expect(
                  body.request.headers.contentType!.mimeType,
                  equals('text/plain'),
                );
                expect(body.body, equals(expectedBody));
                break;

              case 'json':
                expect(
                  body.request.headers.contentType!.mimeType,
                  equals('application/json'),
                );
                expect(body.body, equals(expectedBody));
                break;

              case 'binary':
                expect(body.request.headers.contentType, isNull);
                expect(body.body, equals(expectedBody));
                break;

              case 'form':
                var mimeType = body.request.headers.contentType!.mimeType;
                expect(
                  mimeType,
                  anyOf(
                    equals('multipart/form-data'),
                    equals('application/x-www-form-urlencoded'),
                  ),
                );
                expect(
                  body.body.keys.toSet(),
                  equals(expectedBody.keys.toSet()),
                );
                for (var key in expectedBody.keys) {
                  var found = body.body[key];
                  var expected = expectedBody[key];
                  if (found is HttpBodyFileUpload) {
                    expect(
                      found.contentType.toString(),
                      equals(expected['contentType']),
                    );
                    expect(found.filename, equals(expected['filename']));
                    expect(found.content, equals(expected['content']));
                  } else {
                    expect(found, equals(expected));
                  }
                }
                break;

              default:
                throw StateError('bad body type');
            }
            body.request.response.close();
          },
          onError: (Object e) {
            if (!outcome.isCompleted) outcome.complete(e);
          },
        );

    var client = HttpClient();
    try {
      var request = await client.post('127.0.0.1', server.port, '/');
      if (mimeType != null) {
        request.headers.contentType = ContentType.parse(mimeType);
      }
      request.add(content);
      var response = await request.close();
      await response.drain<void>();
      var result = await outcome.future;
      if (shouldFail) {
        expect(
          result,
          isNot(isA<HttpRequestBody>()),
          reason: 'The body should have been rejected.',
        );
        if (error != null) expect(result, error);
        expect(response.statusCode, equals(HttpStatus.badRequest));
      } else {
        // ignore: only_throw_errors
        if (result is! HttpRequestBody) throw result;
        expect(response.statusCode, equals(HttpStatus.ok));
      }
    } finally {
      client.close();
      await server.close();
    }
  }

  await check('text/plain', 'body'.codeUnits, 'body', 'text');
  await check('text/plain; charset=utf-8', 'body'.codeUnits, 'body', 'text');
  await check('text/plain; charset=utf-8', [42], '*', 'text');
  await check(
    'text/plain; charset=us-ascii',
    [142],
    null,
    'text',
    shouldFail: true,
  );
  await check(
    'text/plain; charset=utf-8',
    [142],
    null,
    'text',
    shouldFail: true,
  );

  await check('application/json', '{"val": 5}'.codeUnits, {'val': 5}, 'json');
  await check(
    'application/json',
    '{ bad json }'.codeUnits,
    null,
    'json',
    shouldFail: true,
  );
  // JSON is always UTF-8, whatever charset the request declares.
  await check(
    'application/json; charset=iso-8859-1',
    utf8.encode('{"val": "é"}'),
    {'val': 'é'},
    'json',
  );
  await check(
    'application/json; charset=us-ascii',
    utf8.encode('{"val": "é"}'),
    {'val': 'é'},
    'json',
    defaultEncoding: latin1,
  );
  // A leading byte order mark is ignored.
  await check(
    'application/json',
    [0xEF, 0xBB, 0xBF, ...'{"val": 5}'.codeUnits],
    {'val': 5},
    'json',
  );
  await check(
    'application/json',
    [...'{"val": "'.codeUnits, 0xE9, ...'"}'.codeUnits],
    null,
    'json',
    shouldFail: true,
  );

  await check(null, 'body'.codeUnits, 'body'.codeUnits, 'binary');

  await check(
    'multipart/form-data; boundary=AaB03x',
    '''
--AaB03x\r
Content-Disposition: form-data; name="name"\r
\r
Larry\r
--AaB03x--\r\n'''
        .codeUnits,
    {'name': 'Larry'},
    'form',
  );

  await check(
    'multipart/form-data; boundary=AaB03x',
    '''
--AaB03x\r
Content-Disposition: form-data; name="files"; filename="myfile"\r
Content-Type: application/octet-stream\r
\r
File content\r
--AaB03x--\r\n'''
        .codeUnits,
    {
      'files': {
        'filename': 'myfile',
        'contentType': 'application/octet-stream',
        'content': 'File content'.codeUnits,
      },
    },
    'form',
  );

  await check(
    'multipart/form-data; boundary=AaB03x',
    '''
--AaB03x\r
Content-Disposition: form-data; name="files"; filename="myfile"\r
Content-Type: application/octet-stream\r
\r
File content\r
--AaB03x\r
Content-Disposition: form-data; name="files"; filename="myfile"\r
Content-Type: text/plain\r
\r
File content\r
--AaB03x--\r\n'''
        .codeUnits,
    {
      'files': {
        'filename': 'myfile',
        'contentType': 'text/plain',
        'content': 'File content',
      },
    },
    'form',
  );

  await check(
    'multipart/form-data; boundary=AaB03x',
    '''
--AaB03x\r
Content-Disposition: form-data; name="files"; filename="myfile"\r
Content-Type: application/json\r
\r
File content\r
--AaB03x--\r\n'''
        .codeUnits,
    {
      'files': {
        'filename': 'myfile',
        'contentType': 'application/json',
        'content': 'File content',
      },
    },
    'form',
  );

  await check(
    'application/x-www-form-urlencoded',
    '%E5%B9%B3%3D%E4%BB%AE%E5%90%8D=%E5%B9%B3%E4%BB%AE%E5%90%8D&b'
            '=%E5%B9%B3%E4%BB%AE%E5%90%8D'
        .codeUnits,
    {'平=仮名': '平仮名', 'b': '平仮名'},
    'form',
  );

  await check(
    'application/x-www-form-urlencoded',
    'a=%F8+%26%23548%3B'.codeUnits,
    null,
    'form',
    shouldFail: true,
  );

  await check(
    'application/x-www-form-urlencoded',
    'a=%C0%A0'.codeUnits,
    null,
    'form',
    shouldFail: true,
  );

  await check(
    'application/x-www-form-urlencoded',
    'a=x%A0x'.codeUnits,
    null,
    'form',
    shouldFail: true,
  );

  await check(
    'application/x-www-form-urlencoded',
    'a=x%C0x'.codeUnits,
    null,
    'form',
    shouldFail: true,
  );

  await check(
    'application/x-www-form-urlencoded',
    'a=%C3%B8+%C8%A4'.codeUnits,
    {'a': 'ø Ȥ'},
    'form',
  );
  // Percent-escapes are UTF-8, whatever the charset.
  await check(
    'application/x-www-form-urlencoded; charset=iso-8859-1',
    'name=%C3%A9'.codeUnits,
    {'name': 'é'},
    'form',
    defaultEncoding: latin1,
  );
  // Raw non-ASCII bytes are rejected with 400 Bad Request, whatever the
  // charset.
  for (var (mimeType, raw) in [
    ('application/x-www-form-urlencoded', utf8.encode('name=José')),
    ('application/x-www-form-urlencoded; charset=utf-8', utf8.encode('€=1')),
    (
      'application/x-www-form-urlencoded; charset=iso-8859-1',
      [...'name='.codeUnits, 0xE9],
    ),
    // Part of a character percent-encoded and part not.
    (
      'application/x-www-form-urlencoded; charset=utf-8',
      [...'name='.codeUnits, 0xC3, ...'%A9'.codeUnits],
    ),
  ]) {
    await check(mimeType, raw, null, 'form', error: isA<FormatException>());
  }
  // A percent-escape that is not UTF-8 fails, whatever the charset.
  await check(
    'application/x-www-form-urlencoded; charset=iso-8859-1',
    'name=%E9'.codeUnits,
    null,
    'form',
    shouldFail: true,
  );
  await check(
    'application/x-www-form-urlencoded',
    'name=%E9'.codeUnits,
    null,
    'form',
    shouldFail: true,
    defaultEncoding: latin1,
  );

  await check(
    'multipart/form-data',
    [],
    null,
    'form',
    error: isA<HttpException>(),
  );

  await check(
    'multipart/form-data; boundary=AaB03x',
    utf8.encode(
      '--AaB03x\r\n'
      'Content-Disposition: form-data; filename="a.txt"\r\n'
      '\r\n'
      'content\r\n'
      '--AaB03x--\r\n',
    ),
    null,
    'form',
    error: isA<HttpException>(),
  );

  await check(
    'application/x-www-form-urlencoded',
    'name=Jos%C3%A9&a=b+c'.codeUnits,
    {'name': 'José', 'a': 'b c'},
    'form',
  );

  await check(
    'application/x-www-form-urlencoded',
    'a=%C3%B8+%26%23548%3B'.codeUnits,
    {'a': 'ø &#548;'},
    'form',
    defaultEncoding: latin1,
  );

  await check(
    'application/x-www-form-urlencoded',
    'name=%26'.codeUnits,
    {'name': '&'},
    'form',
    defaultEncoding: latin1,
  );

  await check(
    'application/x-www-form-urlencoded',
    'name=%C3%B8%26'.codeUnits,
    {'name': 'ø&'},
    'form',
    defaultEncoding: latin1,
  );

  await check(
    'application/x-www-form-urlencoded',
    'name=%26%3B'.codeUnits,
    {'name': '&;'},
    'form',
    defaultEncoding: latin1,
  );

  await check(
    'application/x-www-form-urlencoded',
    'name=%26%23548%3B%26%23548%3B'.codeUnits,
    {'name': '&#548;&#548;'},
    'form',
    defaultEncoding: latin1,
  );

  await check('application/x-www-form-urlencoded', 'name=%26'.codeUnits, {
    'name': '&',
  }, 'form');

  await check('application/x-www-form-urlencoded', 'name=%C3%B8%26'.codeUnits, {
    'name': 'ø&',
  }, 'form');

  await check('application/x-www-form-urlencoded', 'name=%26%3B'.codeUnits, {
    'name': '&;',
  }, 'form');

  await check(
    'application/x-www-form-urlencoded',
    'name=%C8%A4%26%23548%3B'.codeUnits,
    {'name': 'Ȥ&#548;'},
    'form',
  );

  await check(
    'application/x-www-form-urlencoded',
    'name=%C8%A4%C8%A4'.codeUnits,
    {'name': 'ȤȤ'},
    'form',
  );
}

void main() {
  test('client response body', _testHttpClientResponseBody);
  test('server request body', _testHttpServerRequestBody);

  test('Does not close stream while requests are pending', () async {
    var data = StreamController<Uint8List>();
    var requests = Stream<HttpRequest>.fromIterable([
      FakeHttpRequest(Uri(), data: data.stream),
    ]);
    var isDone = false;
    requests
        .transform(HttpBodyHandler())
        .listen((_) {}, onDone: () => isDone = true);
    await pumpEventQueue();
    expect(isDone, isFalse);
    await data.close();
    expect(isDone, isTrue);
  });

  test('Closes stream while no requests are pending', () async {
    var requests = Stream<HttpRequest>.empty();
    var isDone = false;
    requests
        .transform(HttpBodyHandler())
        .listen((_) {}, onDone: () => isDone = true);
    await pumpEventQueue();
    expect(isDone, isTrue);
  });
}
