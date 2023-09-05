// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class BetterPlayerUtils {
  static String formatBitrate(int bitrate) {
    if (bitrate < 1000) {
      return "$bitrate bit/s";
    }
    if (bitrate < 1000000) {
      final kbit = (bitrate / 1000).floor();
      return "~$kbit KBit/s";
    }
    final mbit = (bitrate / 1000000).floor();
    return "~$mbit MBit/s";
  }

  static String formatDuration(Duration position) {
    final ms = position.inMilliseconds;

    int seconds = ms ~/ 1000;
    final int hours = seconds ~/ 3600;
    seconds = seconds % 3600;
    final minutes = seconds ~/ 60;
    seconds = seconds % 60;

    final hoursString = hours >= 10
        ? '$hours'
        : hours == 0
            ? '00'
            : '0$hours';

    final minutesString = minutes >= 10
        ? '$minutes'
        : minutes == 0
            ? '00'
            : '0$minutes';

    final secondsString = seconds >= 10
        ? '$seconds'
        : seconds == 0
            ? '00'
            : '0$seconds';

    final formattedTime =
        '${hoursString == '00' ? '' : '$hoursString:'}$minutesString:$secondsString';

    return formattedTime;
  }

  static double calculateAspectRatio(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return width > height ? width / height : height / width;
  }

  static void log(String logMessage) {
    if (!kReleaseMode) {
      // ignore: avoid_print
      print(logMessage);
    }
  }

  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  ///Request data from given uri along with headers. May return null if resource
  ///is not available or on error.
  static Future<String?> getDataFromUrl(
    String url, {
    Map<String, String?>? headers,
    Function? callback,
  }) async {
    try {
      if (kIsWeb) {
        Map<String, String>? headersFixed;
        if (headers != null) {
          headersFixed = Map<String, String>();
          headers.forEach((name, value) {
            if (value != null) headersFixed![name] = value;
          });
        }
        final response = await http.get(
          Uri.parse(url),
          headers: headersFixed,
        );
        return response.body;
      }

      final request = await _httpClient.getUrl(Uri.parse(url));
      if (headers != null) {
        headers.forEach((name, value) => request.headers.add(name, value!));
      }

      final response = await request.close();
      var data = "";
      await response.transform(const Utf8Decoder()).listen((content) {
        data += content.toString();
      }).asFuture<String?>();

      if (callback != null) callback('test');
      return data;
    } catch (exception) {
      log("GetDataFromUrl failed: $exception");
      return null;
    }
  }

  static Future<http.Response?> sendHttpPost(
    String url, {
    Map<String, String?>? headers,
    dynamic? body,
  }) async {
    try {
      Map<String, String>? headersFixed;
      if (headers != null) {
        headersFixed = Map<String, String>();
        headers.forEach((name, value) {
          if (value != null) headersFixed![name] = value;
        });
      }
      final response = await http.post(
        Uri.parse(url),
        headers: headersFixed,
        body: body,
      );
      return response;
    } catch (exception) {
      log("sendHttpPost failed: $exception");
      return null;
    }
  }
}
