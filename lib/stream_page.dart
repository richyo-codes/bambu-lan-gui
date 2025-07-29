// import 'package:flutter/material.dart';
// import 'package:flutter_vlc_player/flutter_vlc_player.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class StreamPage extends StatefulWidget {
//   const StreamPage({super.key});

//   @override
//   State<StreamPage> createState() => _StreamPageState();
// }

// class _StreamPageState extends State<StreamPage> {
//   VlcPlayerController? _vlcController;
//   String streamUrl = '';

//   @override
//   void initState() {
//     super.initState();
//     _initializePlayer();
//   }

//   Future<void> _initializePlayer() async {
//     final prefs = await SharedPreferences.getInstance();
//     final url = prefs.getString('rtsp_url') ?? '';
//     final user = prefs.getString('rtsp_user') ?? '';
//     final pass = prefs.getString('rtsp_pass') ?? '';

//     if (url.isNotEmpty) {
//       Uri uri = Uri.parse(url);
//       if (user.isNotEmpty) uri = uri.replace(userInfo: '$user:$pass');
//       setState(() {
//         streamUrl = uri.toString();
//         _vlcController = VlcPlayerController.network(streamUrl, autoPlay: true);
//       });
//     }
//   }

//   @override
//   void dispose() {
//     _vlcController?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('RTSP Stream'), actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () async { await Navigator.pushNamed(context, '/settings'); await _initializePlayer(); })]),
//       body: Center(child: streamUrl.isEmpty ? const Text('Configure RTSP in settings.') : VlcPlayer(controller: _vlcController!, aspectRatio: 16 / 9)),
//     );
//   }
// }
