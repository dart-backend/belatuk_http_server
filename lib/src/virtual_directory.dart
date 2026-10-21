// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:belatuk_http_server/src/has_current_iterator.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';

// Used for signal a directory redirecting, where a tailing slash is missing.
class _DirectoryRedirect {
  const _DirectoryRedirect();
}

/// A [VirtualDirectory] can serve files and directory-listing from a root path,
/// to [HttpRequest]s.
///
/// The [VirtualDirectory] providing secure handling of request uris and
/// file-system links, correct mime-types and custom error pages.
class VirtualDirectory {
  final String root;

  /// Whether to allow listing files in a directories.
  ///
  /// When true the response to a request for a directory will be an HTML
  /// document with a table of links to all files within the directory, along
  /// with their size and last modified time. The default behavior can be
  /// overridden by setting a [directoryHandler].
  bool allowDirectoryListing = false;

  /// Whether to allow reading resources via a link.
  bool followLinks = true;

  /// Whether to prevent access outside of [root] via relative paths or links.
  bool jailRoot = true;

  final List<String> _pathPrefixSegments;

  final RegExp _invalidPathRegExp = RegExp('[\\/\x00]');

  void Function(HttpRequest)? _errorCallback;
  void Function(Directory, HttpRequest)? _dirCallback;

  static List<String> _parsePathPrefix(String? pathPrefix) {
    if (pathPrefix == null) return <String>[];
    return Uri(path: pathPrefix).pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
  }

  /// Create a new [VirtualDirectory] for serving static file content of the
  /// path [root].
  ///
  /// The [root] is not required to exist. If the [root] doesn't exist at time of
  /// a request, a 404 response is generated.
  ///
  /// If [pathPrefix] is set, [pathPrefix] will indicate the expected path prefix
  /// of incoming requests. When locating the resource on disk, the prefix will
  /// be trimmed from the requests uri, before locating the actual resource.
  /// If the requests uri doesn't start with [pathPrefix], a 404 response is
  /// generated.
  VirtualDirectory(this.root, {String? pathPrefix})
    : _pathPrefixSegments = _parsePathPrefix(pathPrefix);

  /// Serve a [Stream] of [HttpRequest]s, in this [VirtualDirectory].
  StreamSubscription<HttpRequest> serve(Stream<HttpRequest> requests) =>
      requests.listen(serveRequest);

  /// Serve a single [HttpRequest], in this [VirtualDirectory].
  Future serveRequest(HttpRequest request) async {
    List<String> pathSegments;
    try {
      pathSegments = request.uri.pathSegments;
    } on FormatException {
      // The path has percent-escapes that are not valid UTF-8.
      _serveErrorPage(HttpStatus.badRequest, request);
      return request.response.done;
    }
    var iterator = HasCurrentIterator(pathSegments.iterator);
    iterator.moveNext();
    for (var segment in _pathPrefixSegments) {
      if (!iterator.hasCurrent || iterator.current != segment) {
        _serveErrorPage(HttpStatus.notFound, request);
        return request.response.done;
      }
      iterator.moveNext();
    }

    var entity = await _locateResource('.', iterator);
    if (entity is File) {
      serveFile(entity, request);
    } else if (entity is Directory) {
      if (allowDirectoryListing) {
        _serveDirectory(entity, request);
      } else {
        _serveErrorPage(HttpStatus.notFound, request);
      }
    } else if (entity is _DirectoryRedirect) {
      _unawaited(
        request.response.redirect(
          request.uri.replace(path: '${request.uri.path}/'),
          status: HttpStatus.movedPermanently,
        ),
      );
    } else {
      assert(entity == null);
      _serveErrorPage(HttpStatus.notFound, request);
    }
    return request.response.done;
  }

  /// Overrides the default directory listing.
  ///
  /// When invoked the [callback] should response through the [HttpRequest] with
  /// a directory listing.
  set directoryHandler(void Function(Directory, HttpRequest) callback) {
    _dirCallback = callback;
  }

  /// Overrides the default error handle.
  ///
  /// When [callback] is invoked, the `statusCode` property of the response is
  /// set.
  set errorPageHandler(void Function(HttpRequest) callback) {
    _errorCallback = callback;
  }

  Future<Object?> _locateResource(
    String path,
    HasCurrentIterator<String> segments,
  ) async {
    // Don't allow navigating up paths.
    if (segments.hasCurrent && segments.current == '..') {
      return Future.value(null);
    }
    path = normalize(path);
    // If we jail to root, the relative path can never go up.
    if (jailRoot && split(path).first == '..') return Future.value(null);
    String fullPath() => join(root, path);
    var type = await FileSystemEntity.type(fullPath(), followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        if (!segments.hasCurrent) {
          return File(fullPath());
        }
        break;

      case FileSystemEntityType.directory:
        String dirFullPath() => '${fullPath()}$separator';
        if (!segments.hasCurrent) {
          if (path == '.') return Directory(dirFullPath());
          return const _DirectoryRedirect();
        }
        var current = segments.current;
        var hasNext = segments.moveNext();
        if (!hasNext && current == '') {
          return Directory(dirFullPath());
        } else {
          if (_invalidPathRegExp.hasMatch(current)) break;
          return _locateResource(join(path, current), segments);
        }

      case FileSystemEntityType.link:
        if (followLinks) {
          var target = await Link(fullPath()).target();
          var targetPath = normalize(target);
          if (isAbsolute(targetPath)) {
            // If we jail to root, the path can never be absolute.
            if (jailRoot) return null;
            return _locateResource(targetPath, segments);
          } else {
            targetPath = join(dirname(path), targetPath);
            return _locateResource(targetPath, segments);
          }
        }
        break;
      case FileSystemEntityType.notFound:
        break;
      default:
        break;
    }
    // Return `null` on fall-through, to indicate NOT_FOUND.
    return null;
  }

  /// Serve the content of [file] to [request].
  ///
  /// Can be used in overrides of [directoryHandler] to redirect to an index
  /// file.
  ///
  /// In the request contains the [HttpHeaders.ifModifiedSince] header,
  /// [serveFile] will send a [HttpStatus.notModified] response if the file
  /// was not changed.
  ///
  /// Note that if it was unable to read from [file], the [request]s response
  /// is closed with error-code [HttpStatus.notFound].
  void serveFile(File file, HttpRequest request) async {
    var response = request.response;
    // TODO(ajohnsen): Set up Zone support for these errors.
    try {
      var lastModified = await file.lastModified();
      if (_isNotModified(request, lastModified)) {
        response.statusCode = HttpStatus.notModified;
        await response.close();
        return null;
      }

      response.headers.set(HttpHeaders.lastModifiedHeader, lastModified);
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      var length = await file.length();
      var range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        // We only support one range, where the standard support several.
        var matches = RegExp(r'^bytes=(\d*)\-(\d*)$').firstMatch(range);
        // If the range header have the right format, handle it.
        if (matches != null &&
            (matches[1]!.isNotEmpty || matches[2]!.isNotEmpty)) {
          // Serve sub-range.
          int start; // First byte position - inclusive.
          int end; // Last byte position - inclusive.
          if (matches[1]!.isEmpty) {
            start = length - _parseRangeValue(matches[2]!);
            if (start < 0) start = 0;
            end = length - 1;
          } else {
            start = _parseRangeValue(matches[1]!);
            end = matches[2]!.isEmpty
                ? length - 1
                : _parseRangeValue(matches[2]!);
          }
          // If the range is syntactically invalid the Range header
          // MUST be ignored (RFC 2616 section 14.35.1).
          if (start <= end) {
            if (end >= length) {
              end = length - 1;
            }

            if (start >= length) {
              response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
              await response.close();
              return;
            }

            // Override Content-Length with the actual bytes sent.
            response.headers.set(
              HttpHeaders.contentLengthHeader,
              end - start + 1,
            );

            // Set 'Partial Content' status code.
            response
              ..statusCode = HttpStatus.partialContent
              ..headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes $start-$end/$length',
              );

            // Pipe the 'range' of the file.
            if (request.method == 'HEAD') {
              await response.close();
            } else {
              try {
                await file
                    .openRead(start, end + 1)
                    .cast<List<int>>()
                    .pipe(_VirtualDirectoryFileStream(response, file.path));
              } catch (_) {
                // TODO(kevmoo): log errors
              }
            }
            return;
          }
        }
      }

      response.headers.set(HttpHeaders.contentLengthHeader, length);
      if (request.method == 'HEAD') {
        await response.close();
      } else {
        try {
          await file.openRead().cast<List<int>>().pipe(
            _VirtualDirectoryFileStream(response, file.path),
          );
        } catch (_) {
          // TODO(kevmoo): log errors
        }
      }
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
    }
  }

  void _serveDirectory(Directory dir, HttpRequest request) async {
    if (_dirCallback != null) {
      _dirCallback!(dir, request);
      return;
    }
    var response = request.response;
    try {
      // Stat every entry first, so the listing's modification time accounts
      // for changes to the files in it, not only to the directory itself.
      var lastModified = (await dir.stat()).modified;
      var entities = await dir.list(followLinks: true).handleError((_) {
        // TODO(kevmoo): log error
      }).toList();
      var entries = <(FileSystemEntity, FileStat)>[];
      // Stat the entries in batches, so a large directory neither waits on
      // each entry in turn nor opens a file handle for every entry at once.
      for (var i = 0; i < entities.length; i += _statBatchSize) {
        var batch = entities.sublist(
          i,
          min(i + _statBatchSize, entities.length),
        );
        var stats = await Future.wait(batch.map(_statOrNull));
        for (var (index, stat) in stats.indexed) {
          // The entry was removed while listing, or could not be read.
          if (stat == null || stat.type == FileSystemEntityType.notFound) {
            continue;
          }
          entries.add((batch[index], stat));
          if (stat.modified.isAfter(lastModified)) lastModified = stat.modified;
        }
      }

      if (_isNotModified(request, lastModified)) {
        response.statusCode = HttpStatus.notModified;
        await response.close();
        return;
      }

      response.headers.contentType = ContentType(
        'text',
        'html',
        parameters: {'charset': 'utf-8'},
      );
      response.headers.set(HttpHeaders.lastModifiedHeader, lastModified);
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      var path = _decodePath(request.uri.path);
      var encodedPath = const HtmlEscape().convert(path);
      var header =
          '''<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Index of $encodedPath</title>
</head>
<body>
<h1>Index of $encodedPath</h1>
<table>
  <tr>
    <td>Name</td>
    <td>Last modified</td>
    <td>Size</td>
  </tr>
''';
      var server = response.headers.value(HttpHeaders.serverHeader);
      server ??= '';
      var footer =
          '''</table>
$server
</body>
</html>
''';

      response.write(header);

      void add(String name, String? modified, Object? size, bool folder) {
        size ??= '-';
        modified ??= '';
        var encodedSize = const HtmlEscape().convert(size.toString());
        var encodedModified = const HtmlEscape().convert(modified);
        var encodedLink = const HtmlEscape(HtmlEscapeMode.attribute)
            .convert(Uri.encodeComponent(name));
        if (folder) {
          encodedLink += '/';
          name += '/';
        }
        var encodedName = const HtmlEscape().convert(name);

        var entry =
            '''  <tr>
    <td><a href="$encodedLink">$encodedName</a></td>
    <td>$encodedModified</td>
    <td style="text-align: right">$encodedSize</td>
  </tr>''';
        response.write(entry);
      }

      if (path != '/') {
        add('..', null, null, true);
      }

      for (var (entity, stat) in entries) {
        var name = basename(entity.path);
        if (entity is File) {
          add(name, stat.modified.toString(), stat.size, false);
        } else if (entity is Directory) {
          add(name, stat.modified.toString(), null, true);
        }
      }

      response.write(footer);
      await response.close();
    } catch (_) {
      // TODO(kevmoo): log error
      try {
        response.statusCode = HttpStatus.internalServerError;
      } on StateError {
        // Part of the listing was already sent.
      }
      await response.close();
    }
  }

  void _serveErrorPage(int error, HttpRequest request) {
    var response = request.response;
    response.statusCode = error;
    if (_errorCallback != null) {
      _errorCallback!(request);
      return;
    }
    response.headers.contentType = ContentType(
      'text',
      'html',
      parameters: {'charset': 'utf-8'},
    );
    // Default error page.
    var path = _decodePath(request.uri.path);
    var encodedPath = const HtmlEscape().convert(path);
    var encodedReason = const HtmlEscape().convert(response.reasonPhrase);
    var encodedError = const HtmlEscape().convert(error.toString());

    var server = response.headers.value(HttpHeaders.serverHeader);
    server ??= '';
    var page =
        '''<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>$encodedReason: $encodedPath</title>
</head>
<body>
<h1>Error $encodedError at '$encodedPath': $encodedReason</h1>
$server
</body>
</html>''';
    response.write(page);
    response.close();
  }
}

class _VirtualDirectoryFileStream implements StreamConsumer<List<int>> {
  final HttpResponse response;
  final String path;
  List<int>? buffer = [];

  _VirtualDirectoryFileStream(this.response, this.path);

  @override
  Future addStream(Stream<List<int>> stream) {
    stream.listen(
      (data) {
        if (buffer == null) {
          response.add(data);
          return;
        }
        if (buffer!.isEmpty) {
          if (data.length >= defaultMagicNumbersMaxLength) {
            setMimeType(data);
            response.add(data);
            buffer = null;
          } else {
            buffer!.addAll(data);
          }
        } else {
          buffer!.addAll(data);
          if (buffer!.length >= defaultMagicNumbersMaxLength) {
            setMimeType(buffer);
            response.add(buffer!);
            buffer = null;
          }
        }
      },
      onDone: () {
        if (buffer != null) {
          if (buffer!.isEmpty) {
            setMimeType(null);
          } else {
            setMimeType(buffer);
            response.add(buffer!);
          }
        }
        response.close();
      },
      onError: response.addError,
    );
    return response.done;
  }

  @override
  Future close() => Future.value();

  void setMimeType(List<int>? bytes) {
    var mimeType = lookupMimeType(path, headerBytes: bytes);
    if (mimeType != null) {
      response.headers.contentType = ContentType.parse(mimeType);
    }
  }
}

/// Decodes a request [path] for display, keeping it as it is if its
/// percent-escapes are not valid UTF-8.
String _decodePath(String path) {
  try {
    return Uri.decodeComponent(path);
  } on FormatException {
    return path;
  }
}

/// Stats [entity], or returns `null` if it cannot be read.
Future<FileStat?> _statOrNull(FileSystemEntity entity) async {
  try {
    return await entity.stat();
  } on FileSystemException {
    return null;
  }
}

/// Whether a resource last modified at [modified] is unchanged since the
/// request's `If-Modified-Since` date.
///
/// HTTP dates have a resolution of one second, so [modified] is truncated to
/// whole seconds before comparing.
bool _isNotModified(HttpRequest request, DateTime modified) {
  var since = request.headers.ifModifiedSince;
  if (since == null) return false;
  var milliseconds = modified.millisecondsSinceEpoch;
  // Round down to the second, including for times before 1970.
  var seconds = milliseconds - milliseconds % 1000;
  return seconds <= since.millisecondsSinceEpoch;
}

/// How many directory entries to stat at a time when listing a directory.
const _statBatchSize = 64;

/// Parses a byte position from a `Range` header, treating a number too large
/// for an [int] as larger than any file.
int _parseRangeValue(String value) => int.tryParse(value) ?? 0x7FFFFFFFFFFFFFFF;

// Copied from `package:pedantic` to avoid the dep.
void _unawaited(Future<void> f) {}
