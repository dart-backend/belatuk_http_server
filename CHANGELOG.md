# Change Log

## 5.0.0

### Breaking changes in 5.0.0

* **Breaking:** Requires Dart 3.13 or later.
* **Breaking:** `HttpBodyHandler` decodes the percent-escapes in an `application/x-www-form-urlencoded` body with the request's charset, the same as the body itself, and only falls back to the default encoding when there is no charset. A client that declares one charset but percent-encodes in another now gets differently decoded values.

### Fixes in 5.0.0

* **VirtualDirectory:** A redirect that adds a directory's trailing slash always stays on the same host. A request such as `//other.host/dir` could previously redirect the client to `other.host`.
* **VirtualDirectory:** A request whose path has percent-escapes that are not valid UTF-8, such as `/%FF`, gets a 400 Bad Request instead of an unhandled error and no response. If a custom `errorPageHandler` throws synchronously, the response is still closed.
* **VirtualDirectory:** A redirect to add a directory's trailing slash keeps the query string in place, instead of appending the slash to it.
* **VirtualDirectory:** `If-Modified-Since` compares modification times to the second, as HTTP dates do, so unchanged files and listings get a 304 Not Modified.
* **VirtualDirectory:** A directory listing's last-modified time is the newest of the directory and its entries, so editing a file in it is no longer served from cache.
* **VirtualDirectory:** Listing a directory no longer blocks the server while each entry is checked. An entry that is removed or cannot be read is left out of the listing, and a listing that fails is a 500 Internal Server Error instead of an empty page. A client that disconnects during a listing no longer causes an uncaught error.
* **VirtualDirectory:** A `HEAD` request for a directory listing gets the headers without the listing.
* **VirtualDirectory:** A `Range` value too large for an integer is handled like any other out-of-range value, instead of making an existing file a 404 Not Found.
* **HttpBodyHandler:** A `multipart/form-data` body with no `boundary`, or a part with no `name`, fails with an `HttpException`, instead of a `TypeError` that escaped as an uncaught error.
* **HttpBodyHandler:** Raw non-ASCII characters in an `application/x-www-form-urlencoded` body, which the client did not percent-encode, are accepted.

## 4.6.0

* Require Dart >= 3.8
* Updated `lints` to 6.0.0
* Updated dependencies to the latest release

## 4.5.1

* Fixed linter warnings

## 4.5.0

* Require Dart >= 3.5
* Updated `lints` to 5.0.0
* Updated `mime` to 2.0.0

## 4.4.0

* Updated `lints` to 4.0.0

## 4.3.0

* Require Dart >= 3.3

## 4.2.0

* Upgraded `lints` to 3.0.0

## 4.1.2

* Fixed `_VirtualDirectoryFileStream` class due to change in Dart 3.0.3

## 4.1.1

* Updated README

## 4.1.0

* Upgraded `test_api` to 0.6.0

## 4.0.0

* Require Dart >= 3.0

## 4.0.0-beta.1

* Require Dart >= 3.0
* Fixed linter warnings

## 3.0.0

* Require Dart >= 2.17
* Fixed analyzer warnings

## 2.1.0

* Updated linter to `package:lints`

## 2.0.2

* Transfered repository to `dart-backend`

## 2.0.1

* Added example

## 2.0.0

* Migrated to `belatuk_http_server`

## 1.0.0

* Migrate to null safety.
* Allow multipart form data with specified encodings that don't require
  decoding.

## 0.9.8+3

* Prepare for `HttpClientResponse` SDK change (implements `Stream<Uint8List>`
  rather than `Stream<List<int>>`).

## 0.9.8+2

* Prepare for `File.openRead()` SDK change in signature.

## 0.9.8+1

* Fix a Dart 2 type issue.

## 0.9.8

* Updates to support Dart 2 constants.

## 0.9.7

* Updates to support Dart 2.0 core library changes (wave
  2.2). See [issue 31847][sdk#31847] for details.

  [sdk#31847]: https://github.com/dart-lang/sdk/issues/31847

## 0.9.6

* Updated the secure networking code to the SDKs version 1.15 SecurityContext api

## 0.9.5+1

* Updated the layout of package contents.

## 0.9.5

* Removed the decoding of HTML entity values (in the form &#xxxxx;) for
  values when parsing multipart/form-post requests.

## 0.9.4

* Fixed bugs in the handling of the Range header
