import 'dart:io';

Future<void> main() async {
  final keep = <String, String>{};
  final files = <File>[File('pubspec.yaml'), ...Directory('lib').listSync().whereType<File>()];
  for (final f in files) {
    keep[f.path] = f.readAsStringSync();
  }
  final create = await Process.start(
    'flutter',
    ['create', '--platforms=android', '--project-name=music_app', '--org=com.example', '.'],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  if (await create.exitCode != 0) exit(1);
  keep.forEach((path, content) => File(path).writeAsStringSync(content));
  final test = Directory('test');
  if (test.existsSync()) test.deleteSync(recursive: true);

  final res = Directory('tool/res');
  for (final f in res.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(res.path.length + 1);
    final target = File('android/app/src/main/res/$rel');
    target.parent.createSync(recursive: true);
    f.copySync(target.path);
  }

  final kotlin = File('tool/MainActivity.kt.txt').readAsStringSync();
  final kotlinDir = Directory('android/app/src/main/kotlin');
  for (final f in kotlinDir.listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('MainActivity.kt')) {
      final pkg = f.readAsLinesSync().firstWhere((l) => l.startsWith('package '));
      f.writeAsStringSync('$pkg\n$kotlin');
    }
  }

  final manifest = File('android/app/src/main/AndroidManifest.xml');
  var xml = manifest.readAsStringSync();
  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="PahaeMusic"');
  const perms = <String, String>{
    'android.permission.INTERNET': '<uses-permission android:name="android.permission.INTERNET"/>',
    'android.permission.READ_MEDIA_AUDIO':
        '<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>',
    'android.permission.READ_EXTERNAL_STORAGE':
        '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>',
    'android.permission.WRITE_EXTERNAL_STORAGE':
        '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>',
    'android.permission.WAKE_LOCK': '<uses-permission android:name="android.permission.WAKE_LOCK"/>',
    'android.permission.FOREGROUND_SERVICE':
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK':
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>',
    'android.permission.POST_NOTIFICATIONS':
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
  };
  for (final e in perms.entries) {
    if (!xml.contains('"${e.key}"')) {
      xml = xml.replaceFirst('<application', '${e.value}\n    <application');
    }
  }
  if (!xml.contains('com.ryanheise.audioservice.AudioService')) {
    xml = xml.replaceFirst('</application>', '''    <service android:name="com.ryanheise.audioservice.AudioService" android:foregroundServiceType="mediaPlayback" android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
    </application>''');
  }
  manifest.writeAsStringSync(xml);

  final get = await Process.start('flutter', ['pub', 'get'], mode: ProcessStartMode.inheritStdio, runInShell: true);
  exit(await get.exitCode);
}
