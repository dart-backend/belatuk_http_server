# AI Context: Belatuk HTTP Server

## Project Overview

`belatuk_http_server` is a **single Dart package** of high-level utility classes that work alongside `dart:io`'s `HttpServer` to serve web content. It is a fork of the archived [`http_server`](https://github.com/dart-lang/http_server) package from the Dart team, maintained under [dart-backend](https://github.com/dart-backend/belatuk_http_server) as part of the Angel3 / Belatuk ecosystem.

The package only works in server-side or command-line Dart, because it depends on `dart:io`. Keep the public API compatible with the original `http_server` package unless a change is deliberately recorded as breaking.

## Package Structure

The public library is `lib/belatuk_http_server.dart`, which exports everything under `lib/src/` except the internal iterator helper:

- **`virtual_directory.dart`**: `VirtualDirectory` serves static files from a root directory. It supports range requests, `If-Modified-Since` caching, following symlinks (optionally jailed to the root), directory listings, and custom directory and error-page handlers.
- **`virtual_host.dart`**: `VirtualHost` routes incoming `HttpRequest`s to different streams by the `Host` header, and accepts several request sources (for example HTTP and HTTPS servers).
- **`http_body.dart`**: `HttpBodyHandler` parses request and response bodies into an `HttpBody` with a `type` of `binary`, `text`, `json` or `form`. Uploaded files are returned as `HttpBodyFileUpload`.
- **`http_multipart_form_data.dart`**: `HttpMultipartFormData` wraps a single `multipart/form-data` part, decoding its headers and content.
- **`has_current_iterator.dart`**: `HasCurrentIterator`, an internal helper used to walk request path segments. It is not exported.

`example/main.dart` shows `HttpBodyHandler` in use.

## Key Dependencies

- **Runtime**: `mime` (multipart parsing and MIME type lookup) and `path`.
- **Development**: `test`, `test_api` and `lints`. Code quality is enforced with `package:lints/recommended.yaml` (see `analysis_options.yaml`).
- **SDK**: Dart `>=3.13.0 <4.0.0`.

## Testing

Run tests with `dart test` and static analysis with `dart analyze`.

- Tests run on the **Dart VM only**. `test/utils.dart` imports `dart:mirrors` and the private `package:test_api/src/backend/invoker.dart`, so the suite cannot run on other platforms, and upgrading `test_api` may break it.
- `testVirtualDir` and similar helpers in `test/utils.dart` run each test twice: once against a real `HttpServer` and once against the fakes in `test/http_fakes.dart` (the second run is named `..., with fakes`). A fix to request handling has to pass in both modes.
- `test/certificates/` holds the TLS certificate chain (root, intermediate and a `localhost` server certificate, valid until 2126) and its key, encrypted with the password `dartdart`, used by the HTTPS tests. `test/pkcert/` is an NSS certificate database (password `dartdart`) kept from the upstream project.

## Development Workflow

- **Master Branch**: `master` is the stable production branch. Open all standard PRs against it.
- **Feature Branches**: Work is done on `feature/<name>` branches (or `fixbug/<name>` for bug fixes), with breaking changes recorded in `CHANGELOG.md`.
- **Tooling**: Run `dart pub get` to install dependencies, `dart format .` to format, `dart analyze` for lints and `dart test` for tests.
- **Changelog**: Every user-facing change gets an entry in `CHANGELOG.md`, written as plain-English statements about the package (not commit messages). Group a release's entries under `### Breaking changes in X.Y.Z` (each entry prefixed `**Breaking:**`), `### New in X.Y.Z` and `### Fixes in X.Y.Z`, in that order, omitting empty sections. Prefix each fix with a bold area label, e.g. `* **VirtualDirectory:** A directory redirect keeps the query string`. Existing entries, up to and including 4.6.0, use plain bullet lists and are left as they are. Commit messages use [Conventional Commits](https://www.conventionalcommits.org/) (`type: description`).
