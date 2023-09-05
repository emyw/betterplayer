@JS('shaka')
library shaka;

import 'dart:html' as html;
import 'dart:js';
// ignore: depend_on_referenced_packages
import 'package:js/js.dart';

@JS()
class Player {
  external Player(html.VideoElement element);

  external static bool isBrowserSupported();

  external bool configure(Object config);
  external Future<void> load(String src, [double? startTime, String? mimeType]);
  external Future<void> destroy();

  external NetworkingEngine getNetworkingEngine();

  external void addEventListener(String event, Function callback);
}

@JS('net.NetworkingEngine')
class NetworkingEngine {
  external dynamic registerRequestFilter(RequestFilter filter);
}

/*
extension NetworkingEngineExt on NetworkingEngine {
  void registerRequestFilter(RequestFilter filter) {
    privateRegisterRequestFilter(allowInterop(filter));
  }
}
*/

class RequestType {
  static const manifest = 0;
  static const segment = 1;
  static const license = 2;
  static const app = 3;
  static const timing = 4;
  static const serverCertificate = 5;
}

typedef RequestFilter = dynamic Function(int requestType, Request request);

/// https://shaka-player-demo.appspot.com/docs/api/shaka.extern.html#.Request
@JS('extern.Request')
class Request {
  external List<String> uris;
  external String method;
  external Object headers;
  external dynamic body;
  external bool allowCrossSiteCredentials;
  external String? licenseRequestType;
  external String? sessionId;
  external String? initDataType;
}

/// https://shaka-player-demo.appspot.com/docs/api/shaka.util.Error.html
@JS('util.Error')
class Error {
  @JS('Code')
  external static dynamic get codes;

  @JS('Category')
  external static dynamic get categories;

  @JS('Severity')
  external static dynamic get severities;

  external int get code;
  external int get category;
  external int get severity;
}

@JS('polyfill.installAll')
external void installPolyfills();

bool get isLoaded => context.hasProperty('shaka');
bool get isNotLoaded => !isLoaded;

String errorCodeName(int code) {
  return _findName(context['shaka']['util']['Error']['Code'], code);
}

String errorCategoryName(int category) {
  return _findName(context['shaka']['util']['Error']['Category'], category);
}

String _findName(JsObject object, int value) {
  final List keys = context['Object'].callMethod('keys', [object]);

  try {
    return keys.firstWhere((dynamic k) => object[k] == value);
  } catch (_) {
    return '';
  }
}
