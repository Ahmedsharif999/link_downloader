import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محمّل اللينكات',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomePage(),
    );
  }
}

class DownloadItem {
  final String name;
  final String path;
  DownloadItem(this.name, this.path);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _dio = Dio();
  final List<DownloadItem> _items = [];
  double? _progress;
  bool _busy = false;

  static const _extByType = {
    'application/pdf': '.pdf',
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'video/mp4': '.mp4',
    'video/webm': '.webm',
    'audio/mpeg': '.mp3',
  };

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _controller.text = data!.text!.trim());
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }  Future<String> _fileName(String url) async {
    final uri = Uri.parse(url);
    var name = uri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : '';
    if (!name.contains('.')) {
      var ext = '';
      try {
        final head = await _dio.head(url);
        final type =
            (head.headers.value('content-type') ?? '').split(';').first;
        ext = _extByType[type.trim()] ?? '';
      } catch (_) {}
      if (name.isEmpty) name = 'file_${DateTime.now().millisecondsSinceEpoch}';
      name += ext;
    }
    return name;
  }

  Future<void> _download() async {
    final url = _controller.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _toast('اللينك مش صحيح، لازم يبدأ بـ http أو https');
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
    });

    try {
      final name = await _fileName(url);
      final ext = name.toLowerCase().split('.').last;
      final isVideo = ['mp4', 'webm', 'mov', 'mkv', '3gp'].contains(ext);
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
      final toGallery = isVideo || isImage;

      Directory dir;
      if (toGallery) {
        dir = await getTemporaryDirectory();
      } else {
        dir = (Platform.isAndroid
                ? await getExternalStorageDirectory()
                : null) ??
            await getApplicationDocumentsDirectory();
      }
      final path = '${dir.path}/$name';

      await _dio.download(
        url,
        path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) setState(() => _progress = received / total);
        },
      );

      if (toGallery) {
        if (!await Gal.hasAccess()) await Gal.requestAccess();
        if (isVideo) {
          await Gal.putVideo(path);
        } else {
          await Gal.putImage(path);
        }
      }

      setState(() {
        _items.insert(0, DownloadItem(name, path));
        _controller.clear();
      });
      _toast(toGallery ? 'تم الحفظ في المعرض ✅' : 'تم التحميل ✅');
    } catch (e) {
      _toast('التحميل فشل، اتأكد إن اللينك مباشر وشغال');
    } finally {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('abo zahra')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'الصق اللينك هنا',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download),
                label: const Text('تحميل'),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('لسه مفيش تحميلات'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: const Icon(Icons.insert_drive_file),
                          title: Text(item.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => OpenFilex.open(item.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
