import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'core/account.dart';
import 'core/api.dart';
import 'core/store.dart';
import 'core/wenku.dart';
import 'core/wenku_web.dart';
import 'ios/ios_app.dart';

/// 让 dio 与图片加载（dart:io HttpClient）统一走代理，失败时回退直连。
class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.proxy);

  final String proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY $proxy; DIRECT';
}

/// Android 和 iOS 用同一套界面（按 iOS 26 设计稿实现，代码在 lib/ios）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStores();
  await AccountService.instance.load();
  await WenkuService.instance.load();
  WenkuService.web = WenkuWebFetcher.instance;
  final proxy = ReaderPrefs.instance.proxy;
  if (proxy.isNotEmpty) HttpOverrides.global = _ProxyOverrides(proxy);
  // 先发出测速请求，不阻塞首帧；请求会等它算完再挑线路。
  MangaApi.instance.warmUp().ignore();
  // 界面按竖屏手机设计；内容画到系统栏后面，悬浮标签栏自己避让手势条。
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 预热 Liquid Glass 着色器：只做磁盘到内存的读取，不阻塞首帧。
  // 只有 iOS 用液体玻璃，安卓走毛玻璃，不需要预载着色器。
  if (Platform.isIOS) await LiquidGlassWidgets.initialize();
  // 边栏的渐进模糊是同一个库里的独立 shader，两端都在用（顶栏、标签栏），
  // 不预载的话首帧会先退化成均匀模糊、下一帧才变成渐变。
  await ProgressiveBlur.preload();
  runApp(const IosApp());
}
