import 'dart:async';
import 'dart:developer';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'dart:js';
import 'dart:js_util';
import 'dart:typed_data';
import 'package:js/js.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:better_player/better_player.dart';
import 'package:better_player/src/core/better_player_utils.dart';
// ignore: implementation_imports
import 'package:better_player/src/video_player/video_player_platform_interface.dart';
import 'package:better_player/web_player_plugin/shaka_js_interface.dart'
    as shaka;
// import 'package:better_player/web_player_plugin/shims/dart_ui.dart' as ui;

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = <int, String>{
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = <int, String>{
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage =
    'No further diagnostic information can be determined or provided.';

// const String _kMuxScriptUrl =
//     'https://cdnjs.cloudflare.com/ajax/libs/mux.js/5.10.0/mux.min.js';
// const String _kShakaScriptUrl = kReleaseMode
//     ? 'https://cdnjs.cloudflare.com/ajax/libs/shaka-player/4.3.6/shaka-player.compiled.js'
//     : 'https://cdnjs.cloudflare.com/ajax/libs/shaka-player/4.3.6/shaka-player.compiled.debug.js';

@JS()
class Promise {
  external Promise(
      void executor(
          void resolve([dynamic result]), void reject(dynamic error)));
  external Promise then(void onFulfilled([dynamic result]),
      [void reject(dynamic error)]);
}

class ShakaPlayer {
  ShakaPlayer({
    required html.VideoElement videoElement,
    required String key,
    bool withCredentials = false,
    @visibleForTesting StreamController<VideoEvent>? eventController,
  })  : _videoElement = videoElement,
        _key = key,
        _withCredentials = withCredentials,
        _eventController = eventController ?? StreamController<VideoEvent>();

  final html.VideoElement _videoElement;
  final String _key;
  final bool _withCredentials;
  final StreamController<VideoEvent> _eventController;

  late shaka.Player _player;
  bool _isInitialized = false;
  bool _isBuffering = false;

  BetterPlayerDrmConfiguration? _drmConfiguration;

  String? src;
  String? mimeType;

  bool get _hasDrm =>
      _drmConfiguration?.certificateUrl != null ||
      _drmConfiguration?.licenseUrl != null;

  String get _drmServer {
    switch (_drmConfiguration?.drmType) {
      case BetterPlayerDrmType.widevine:
        return 'com.widevine.alpha';
      case BetterPlayerDrmType.playready:
        return 'com.microsoft.playready';
      case BetterPlayerDrmType.clearKey:
        return 'org.w3.clearkey';
      default:
        return '';
    }
  }

  /// Returns the [Stream] of [VideoEvent]s.
  Stream<VideoEvent> get events => _eventController.stream;

  void setDataSource(DataSource dataSource) async {
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        // Do NOT modify the incoming uri, it can be a Blob, and Safari doesn't
        // like blobs that have changed.
        src = dataSource.uri ?? '';
        switch (dataSource.formatHint) {
          case VideoFormat.dash:
            mimeType = 'application/dash+xml';
            break;
          case VideoFormat.hls:
            mimeType = 'application/x-mpegurl';
            break;
          default:
            null;
        }
        ;
        break;
      case DataSourceType.asset:
        String assetUrl = dataSource.asset!;
        if (dataSource.package != null && dataSource.package!.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        // assetUrl = ui.webOnlyAssetManager.getAssetUrl(assetUrl);
        src = assetUrl;
        break;
      case DataSourceType.file:
        throw UnimplementedError('web player cannot play local files');
    }
    _drmConfiguration = BetterPlayerDrmConfiguration(
      certificateUrl: dataSource.certificateUrl,
      clearKey: dataSource.clearKey,
      drmType: dataSource.drmType,
      headers: dataSource.drmHeaders,
      licenseUrl: dataSource.licenseUrl,
    );
  }

  Future<void> initialize() async {
    try {
      // await _loadScript();
      await _afterLoadScript();
    } on html.Event catch (ex) {
      _eventController.addError(PlatformException(
        code: ex.type,
        message: 'Error loading Shaka Player',
      ));
    } catch (e) {
      throw ErrorDescription(e.toString());
    }
  }

  // Future<dynamic> _loadScript() async {
  //   if (shaka.isNotLoaded) {
  //     await loadScript('muxjs', _kMuxScriptUrl);
  //     await loadScript('shaka', _kShakaScriptUrl);
  //   }
  // }

  Future<void> _afterLoadScript() async {
    try {
      shaka.installPolyfills();
    } catch (e) {
      inspect(e);
    }

    if (shaka.Player.isBrowserSupported()) {
      _player = shaka.Player(_videoElement);

      setupListeners();

      try {
        if (_hasDrm) {
          if (_drmConfiguration?.licenseUrl?.isNotEmpty ?? false) {
            _player.configure(
              jsify({
                "drm": {
                  "servers": {_drmServer: _drmConfiguration!.licenseUrl!}
                }
              }),
            );
          }
        }

        _player.getNetworkingEngine().registerRequestFilter(
            allowInterop((int type, shaka.Request request) {
          // RequestType = {
          //   'manifest': 0,
          //   'segment': 1,
          //   'license': 2,
          //   'app': 3,
          //   'timing': 4,
          //   'serverCertificate': 5,
          // };
          request.allowCrossSiteCredentials = _withCredentials;

          if (type == shaka.RequestType.license) {
            if (_hasDrm && _drmConfiguration?.headers?.isNotEmpty == true) {
              request.headers = jsify((_drmConfiguration!.headers!));
            }

            ByteBuffer? byteBuffer = request.body;
            Uint8List? reqUint8List = byteBuffer?.asUint8List();
            // String base64String =
            //     reqUint8List != null ? base64.encode(reqUint8List) : '';

            final testPromise = Promise(allowInterop((resolve, reject) {
              BetterPlayerUtils.sendHttpPost(
                request.uris[0],
                body: reqUint8List,
              ).then<dynamic>((http.Response? res) {
                Uint8List? resUint8List = res?.bodyBytes;
                String resString = resUint8List != null
                    ? String.fromCharCodes(resUint8List)
                    : '';
                // final headersUpdate = Map<String, String>.from(
                //     _drmConfiguration?.headers ?? Map<String, String>())
                //   ..addAll({'res': resString});
                // final headersUpdate = {'test', 'val'};
                // request.headers = jsify(headersUpdate);

                debugPrint(
                    'got license response: ${resString.substring(0, 100).replaceAll(RegExp(r'\n'), '\\n')}${resString.length > 100 ? '...' : ''}');

                resolve('test');
              }, onError: reject);
            }));

            return testPromise;
          }

          return null;
        }));

        await promiseToFuture<void>(_player.load(src!, null, mimeType));
      } on shaka.Error catch (ex) {
        _onShakaPlayerError(ex);
      }
    } else {
      throw UnsupportedError(
          'web implementation of video_player does not support your browser');
    }
  }

  void _onShakaPlayerError(shaka.Error error) {
    _eventController.addError(PlatformException(
      code: shaka.errorCodeName(error.code),
      message: shaka.errorCategoryName(error.category),
      details: error,
    ));
  }

  @protected
  void setupListeners() {
    _videoElement.onCanPlay.listen((dynamic _) => markAsInitializedIfNeeded());

    _videoElement.onCanPlayThrough.listen((dynamic _) {
      setBuffering(false);
    });

    _videoElement.onPlaying.listen((dynamic _) {
      setBuffering(false);
    });

    _videoElement.onWaiting.listen((dynamic _) {
      setBuffering(true);
      _sendBufferingRangesUpdate();
    });

    // The error event fires when some form of error occurs while attempting to load or perform the media.
    _videoElement.onError.listen((html.Event _) {
      setBuffering(false);
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      final html.MediaError error = _videoElement.error!;

      _eventController.addError(PlatformException(
        code: _kErrorValueToErrorName[error.code]!,
        message: error.message != '' ? error.message : _kDefaultErrorMessage,
        details: _kErrorValueToErrorDescription[error.code],
      ));
    });

    _videoElement.onEnded.listen((dynamic event) {
      setBuffering(false);
      _eventController
          .add(VideoEvent(eventType: VideoEventType.completed, key: _key));
    });

    // Listen for error events.
    _player.addEventListener(
      'error',
      allowInterop((dynamic event) {
        debugPrint('Shaka error: ${event.detail}');
        return _onShakaPlayerError(event.detail);
      }),
    );
  }

  // Sends an [VideoEventType.initialized] [VideoEvent] with info about the wrapped video.
  @protected
  void markAsInitializedIfNeeded() {
    if (!_isInitialized) {
      _isInitialized = true;
      _sendInitialized();
    }
  }

  void _sendInitialized() {
    final Duration? duration = !_videoElement.duration.isNaN
        ? Duration(
            milliseconds: (_videoElement.duration * 1000).round(),
          )
        : null;

    final Size? size = !_videoElement.videoHeight.isNaN
        ? Size(
            _videoElement.videoWidth.toDouble(),
            _videoElement.videoHeight.toDouble(),
          )
        : null;

    _eventController.add(
      VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: size,
          key: _key),
    );
  }

  /// Attempts to play the video.
  ///
  /// If this method is called programmatically (without user interaction), it
  /// might fail unless the video is completely muted (or it has no Audio tracks).
  ///
  /// When called from some user interaction (a tap on a button), the above
  /// limitation should disappear.
  Future<void> play() {
    return _videoElement.play();
    // .catchError((Object e) {
    //   // play() attempts to begin playback of the media. It returns
    //   // a Promise which can get rejected in case of failure to begin
    //   // playback for any reason, such as permission issues.
    //   // The rejection handler is called with a DomException.
    //   // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play
    //   final html.DomException exception = e as html.DomException;
    //   _eventController.addError(PlatformException(
    //     code: exception.name,
    //     message: exception.message,
    //   ));
    // }, test: (Object e) => e is html.DomException);
  }

  /// Pauses the video in the current position.
  void pause() {
    _videoElement.pause();
  }

  /// Controls whether the video should start again after it finishes.
  void setLooping(bool value) {
    _videoElement.loop = value;
  }

  /// Sets the volume at which the media will be played.
  ///
  /// Values must fall between 0 and 1, where 0 is muted and 1 is the loudest.
  ///
  /// When volume is set to 0, the `muted` property is also applied to the
  /// [html.VideoElement]. This is required for auto-play on the web.
  void setVolume(double volume) {
    assert(volume >= 0 && volume <= 1);

    // TODO(ditman): Do we need to expose a "muted" API?
    // https://github.com/flutter/flutter/issues/60721
    _videoElement.muted = !(volume > 0.0);
    _videoElement.volume = volume;
  }

  /// Sets the playback `speed`.
  ///
  /// A `speed` of 1.0 is "normal speed," values lower than 1.0 make the media
  /// play slower than normal, higher values make it play faster.
  ///
  /// `speed` cannot be negative.
  ///
  /// The audio is muted when the fast forward or slow motion is outside a useful
  /// range (for example, Gecko mutes the sound outside the range 0.25 to 4.0).
  ///
  /// The pitch of the audio is corrected by default.
  void setPlaybackSpeed(double speed) {
    assert(speed > 0);
    _videoElement.playbackRate = speed;
  }

  /// Moves the playback head to a new `position`.
  ///
  /// `position` cannot be negative.
  void seekTo(Duration position) {
    assert(!position.isNegative);

    _videoElement.currentTime = position.inMilliseconds.toDouble() / 1000;
  }

  /// Returns the current playback head position as a [Duration].
  Duration getPosition() {
    _sendBufferingRangesUpdate();
    return Duration(milliseconds: (_videoElement.currentTime * 1000).round());
  }

  /// Caches the current "buffering" state of the video.
  ///
  /// If the current buffering state is different from the previous one
  /// ([_isBuffering]), this dispatches a [VideoEvent].
  @protected
  @visibleForTesting
  void setBuffering(bool buffering) {
    if (_isBuffering != buffering) {
      _isBuffering = buffering;
      _eventController.add(VideoEvent(
          eventType: _isBuffering
              ? VideoEventType.bufferingStart
              : VideoEventType.bufferingEnd,
          key: _key));
    }
  }

  // Broadcasts the [html.VideoElement.buffered] status through the [events] stream.
  void _sendBufferingRangesUpdate() {
    _eventController.add(VideoEvent(
        buffered: _toDurationRange(_videoElement.buffered),
        eventType: VideoEventType.bufferingUpdate,
        key: _key));
  }

  // Converts from [html.TimeRanges] to our own List<DurationRange>.
  List<DurationRange> _toDurationRange(html.TimeRanges buffered) {
    final List<DurationRange> durationRange = <DurationRange>[];
    for (int i = 0; i < buffered.length; i++) {
      durationRange.add(DurationRange(
        Duration(milliseconds: (buffered.start(i) * 1000).round()),
        Duration(milliseconds: (buffered.end(i) * 1000).round()),
      ));
    }
    return durationRange;
  }

  void dispose() {
    _player.destroy();
    _videoElement.removeAttribute('src');
    _videoElement.load();
  }

  Future<void> setTrackParameters(int? width, int? height, int? bitrate) async {
    _videoElement.width = width ?? 350;
    _videoElement.height = height ?? 250;
  }

  Future<DateTime?> getAbsolutePosition() async {
    return DateTime.fromMillisecondsSinceEpoch(_videoElement.duration.toInt());
  }
}

Future<dynamic> loadScript(String packageName, String url) async {
  if (context['define']['amd'] != null) {
    return loadScriptUsingRequireJS(packageName, url);
  } else {
    return loadScriptUsingScriptTag(url);
  }
}

Future<dynamic> loadScriptUsingScriptTag(String url) async {
  html.ScriptElement script = html.ScriptElement()
    ..type = 'text/javascript'
    ..src = url
    ..async = true
    ..defer = false;

  html.document.head!.append(script);

  return script.onLoad.first;
}

Future<dynamic> loadScriptUsingRequireJS(String packageName, String url) async {
  final Completer completer = Completer<void>();
  final String eventName = '_${packageName}Loaded';

  context.callMethod('addEventListener',
      <dynamic>[eventName, allowInterop((dynamic _) => completer.complete())]);

  html.ScriptElement script = html.ScriptElement()
    ..type = 'text/javascript'
    ..async = false
    ..defer = false
    ..text = ''
        'require(["$url"], (package) => {'
        'window.$packageName = package;'
        'const event = new Event("$eventName");'
        'dispatchEvent(event);'
        '})'
        '';

  html.document.head!.append(script);

  return completer.future;
}
