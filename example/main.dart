import 'dart:convert';
import 'dart:io';

import 'package:belatuk_http_server/belatuk_http_server.dart';

void main() async {
  var server = await HttpServer.bind('localhost', 8080);
  server.transform(HttpBodyHandler(defaultEncoding: utf8)).listen((body) {
    switch (body.type) {
      case 'text':
        print(body.body);
        break;

      case 'json':
        print(body.body);
        break;

      default:
        throw StateError('bad body type');
    }
    body.request.response.close();
  }, onError: (Object error) {
    throw StateError('bad connection');
  });
}
