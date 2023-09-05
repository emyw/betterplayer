import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:better_player_example/constants.dart';
import 'package:better_player_example/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AssetPlayerPage extends StatefulWidget {
  @override
  _AssetPlayerPageState createState() => _AssetPlayerPageState();
}

class _AssetPlayerPageState extends State<AssetPlayerPage> {
  late BetterPlayerController _betterPlayerController;

  @override
  void initState() {
    BetterPlayerConfiguration betterPlayerConfiguration =
        BetterPlayerConfiguration(
      aspectRatio: 16 / 9,
      fit: BoxFit.contain,
    );

    _betterPlayerController = BetterPlayerController(betterPlayerConfiguration);
    _setupDataSource();
    super.initState();
  }

  void _setupDataSource() async {
    var filePath = await Utils.getFileUrl(Constants.fileTestVideoUrl);
    BetterPlayerDataSource? dataSource = null;

    if (kIsWeb) {
      dataSource = BetterPlayerDataSource.file(filePath);
    } else {
      // Store sample video as file
      File file = File(filePath);
      List<int> bytes = file.readAsBytesSync().buffer.asUint8List();
      await file.writeAsBytes(bytes);
      dataSource = BetterPlayerDataSource.file(filePath);
    }
    _betterPlayerController.setupDataSource(dataSource);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Assets player"),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Assets player which plays video from assets.",
              style: TextStyle(fontSize: 16),
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: BetterPlayer(controller: _betterPlayerController),
          ),
        ],
      ),
    );
  }
}
