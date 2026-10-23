import 'dart:convert';
import 'dart:io';

import 'package:belatuk_http_server/belatuk_http_server.dart';

void main() async {
  var server = await HttpServer.bind('localhost', 8080);
  server
      .transform(HttpBodyHandler(defaultEncoding: utf8))
      .listen(
        (body) {
          // `type` is 'text', 'json', 'form' (urlencoded or multipart) or
          // 'binary'.
          print('${body.type}: ${body.body}');
          body.request.response.close();
        },
        onError: (Object error) {
          // The request has already been answered with 400 Bad Request.
          print('Could not parse a request body: $error');
        },
      );
}
