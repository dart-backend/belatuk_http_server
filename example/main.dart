import 'dart:convert';
import 'dart:io';

import 'package:belatuk_http_server/belatuk_http_server.dart';

void main() async {
  var server = await HttpServer.bind('localhost', 8080);
  server
      .transform(HttpBodyHandler(defaultEncoding: utf8))
      .listen(
        (body) {
          var response = body.request.response;
          switch (body.type) {
            case 'text':
            case 'json':
              print(body.body);
            default:
              response.statusCode = HttpStatus.unsupportedMediaType;
          }
          response.close();
        },
        onError: (Object error) {
          // The request has already been answered with 400 Bad Request.
          print('Could not parse a request body: $error');
        },
      );
}
