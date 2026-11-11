import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chapter_browser.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../reader/reader_controller.dart';
import '../reader/reader_models.dart';
import '../reader/reader_navigation.dart';
import '../reader/reader_transition.dart';
import '../reader/reader_view.dart';
import '../reader/reading_mode.dart';
import '../reader/reader_chrome.dart';
import '../reader/page_fit.dart';
import '../reader/reader_theme.dart';
import '../ui/icons.dart';
import '../ui/widgets.dart' show revealChapterRow;
import '../ui/motion.dart';
import 'ios_theme.dart';

class IosReaderPage extends StatefulWidget {
  const IosReaderPage({super.key, required this.comic, required this.group, required this.chapterUuid, this.initialPage = 0});

  final ComicBrief comic;
  final String group;
  final String chapterUuid;
  final int initialPage;

  @override
  State<IosReaderPage> createState() => _IosReaderPageState();
}

class _IosReaderPageState extends State<IosReaderPage> {
  final _prefs = ReaderPrefs.instance;
  bool _chrome = true;

  /// 页面亮度单独走通知器。
  ///
  /// 亮度是拖动中每帧都在变的值，如果它和别的设置一样走 `setState`，
  /// 拖一下滑块整个阅读区（含所有图片页）就重建几十次——这就是
  /// 「亮度滑一下很卡」。现在只有压暗那一层 `ColoredBox` 跟着重建。
  final _brightness = ValueNotifier<double>(1);

  /// 阅读区缓存的控件实例。
  ///
  /// `_readerBody()` 每次调用都会新建一个 `ReaderView`。只改亮度或预加载页数时
  /// 这个实例完全没变，返回同一个实例可以让 Flutter 直接跳过整棵子树的重建
  /// （`Element.updateChild` 对同一个 widget 实例是短路返回的）。
  Widget? _body;

  /// 上一次看到的相关偏好，用来判断这次通知要不要重建。
  int _lastMode = 0;
  bool _lastSaver = false;
  int _lastArea = 0;
  int _lastFit = 0;

  /// 图片重新载入用的计数，换 key 强制重建。
  int _retry = 0;

  /// 系统栏的真实高度（不含沉浸态被压成的 0）。
  ///
  /// 隐藏控件时会切 `immersiveSticky`，那一刻 `MediaQuery.padding` 变成 0。
  /// 顶栏底栏都靠它算内边距，直接用会在切回来的第一帧先顶到屏幕边缘、
  /// 下一帧再跳下来。这里记下最后一次看到的值，两条栏始终按它排。
  double _insetTop = 0;
  double _insetBottom = 0;

  /// 阅读引擎：管当前话与前后话的载入。
  late final ReaderController _ctl = ReaderController(pathWord: widget.comic.pathWord, group: widget.group)
    ..addListener(_onEngine);

  /// 首次进入时的手势提示：看到第一张图后弹一次，3 秒自动淡出。
  bool _tip = false;
  Timer? _tipTimer;

  bool get _saver => _prefs.mangaSaver;

  ReadingMode get _mode => ReadingMode.fromPreference(_prefs.mangaMode);

  /// 「图片适配」设置。实际用哪一档还要过一遍 [PageFit.resolve]（auto 会跟着阅读方式走）。
  PageFit get _fit => PageFit.fromValue(_prefs.mangaFit);

  /// 当前话的页（已应用省流画质）。
  List<String> get _images => [for (final p in _ctl.current?.pages ?? const <ReaderPage>[]) imageUrlFor(p.url, saver: _saver)];

  /// 底部面板和进度用的当前页下标。
  int get _page => _ctl.pageIndex;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefs);
    _lastMode = _prefs.mangaMode;
    _lastSaver = _prefs.mangaSaver;
    _lastArea = _prefs.mangaArea;
    _lastFit = _prefs.mangaFit;
    _brightness.value = _prefs.mangaBrightness;
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
    _ctl.open(widget.chapterUuid, page: widget.initialPage);
    // 第一次进阅读器：图片出来后再弹分区提示，3 秒自动收起，点一下也能关。
    if (!_prefs.mangaTipSeen && _prefs.mangaArea != 0) {
      _tipTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() => _tip = true);
        _tipTimer = Timer(const Duration(seconds: 3), _closeTip);
      });
    }
  }

  void _closeTip() {
    _tipTimer?.cancel();
    _tipTimer = null;
    if (!mounted) return;
    setState(() => _tip = false);
    _prefs.mangaTipSeen = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 沉浸态下系统把 padding 压成 0，只在拿到真实值时才覆盖缓存——
    // 否则收起系统栏的那一刻，我们自己的两条栏会先贴到屏幕边缘再跳回来。
    final p = MediaQuery.paddingOf(context);
    if (p.top > 0) _insetTop = p.top;
    if (p.bottom > 0) _insetBottom = p.bottom;
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _prefs.removeListener(_onPrefs);
    // 退出阅读器时把去抖中的偏好立刻写掉，避免 320ms 内退出丢设置。
    _prefs.flush();
    _brightness.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
    _ctl.removeListener(_onEngine);
    _ctl.dispose();
    super.dispose();
  }

  /// 偏好变化时判断要不要重建整页。
  ///
  /// 只有「影响阅读区结构」的三项（阅读方式、画质、点击区域）需要重建；
  /// 亮度和预加载页数改完立刻返回，阅读区一个像素都不动。
  void _onPrefs() {
    if (!mounted) return;
    _brightness.value = _prefs.mangaBrightness;
    final structural = _prefs.mangaMode != _lastMode ||
        _prefs.mangaSaver != _lastSaver ||
        _prefs.mangaArea != _lastArea ||
        _prefs.mangaFit != _lastFit;
    _lastMode = _prefs.mangaMode;
    _lastSaver = _prefs.mangaSaver;
    _lastArea = _prefs.mangaArea;
    _lastFit = _prefs.mangaFit;
    if (!structural) return;
    _body = null;
    setState(() {});
  }

  void _onEngine() {
    if (!mounted) return;
    _body = null;
    setState(() {});
    _save();
    _precache(_page);
  }

  void _save() {
    // 条漫恢复上次位置的过程中，视口中线扫过的是「路过」的页而不是读到的那一页。
    // 这段时间写盘会把用户真实的位置覆盖成第 1 页——这正是「每次进来都是 1」的来源。
    if (_ctl.restoring) return;
    final c = _ctl.current;
    final pages = c?.pages;
    if (c == null || pages == null || pages.isEmpty || c.locked) return;
    final store = LibraryStore.instance;
    final page = _ctl.pageIndex.clamp(0, pages.length - 1);
    store.recordPosition(
      id: widget.comic.pathWord,
      create: () => ShelfEntry(id: widget.comic.pathWord, kind: ShelfKind.manga, name: widget.comic.name, cover: widget.comic.cover, author: widget.comic.authorText, followed: false),
      chapterUuid: c.chapter.uuid,
      chapterName: c.chapter.name,
      chapterIndex: c.chapter.index,
      group: c.chapter.groupPathWord.isEmpty ? widget.group : c.chapter.groupPathWord,
      page: page,
      pageCount: pages.length,
      progress: (page + 1) / pages.length,
    );
    if (page >= pages.length - 1) store.markRead(widget.comic.pathWord, c.chapter.uuid);
  }

  /// 预取当前页前后各 `mangaPrefetch` 页。反向阅读时「前面」是往回的页，
  /// 所以两个方向都补，代价只是多几张图。
  void _precache(int from) {
    final images = _images;
    final n = _prefs.mangaPrefetch;
    for (var i = from - n; i <= from + n; i++) {
      if (i < 0 || i >= images.length || i == from) continue;
      precacheImage(CachedNetworkImageProvider(images[i], headers: AppConfig.imageHeaders), context).ignore();
    }
  }

  /// 显示 / 隐藏阅读控件，并同步系统栏。
  ///
  /// **控件隐藏时收系统栏，显示时还回去**。一直 edge-to-edge 的代价是：
  /// 整页适应会在页面上下各留一条 letterbox，状态栏图标和手势条正好压在上面，
  /// 读起来像「内容没铺满、上面压了根杠」。沉浸之后那两条就是纯黑框。
  ///
  /// 用 `immersiveSticky` 而不是 `immersive`：前者靠**边缘滑动**唤出系统栏，
  /// 普通点按照常落到阅读区；后者是「下一次触摸唤出系统栏」，那一触会被系统
  /// 吃掉——这就是以前「点好几下设置才出来」的原因。
  void _setChrome(bool show) {
    if (show == _chrome) return;
    setState(() => _chrome = show);
    SystemChrome.setEnabledSystemUIMode(show ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
  }

  /// 换话：交给引擎，它会重建三话窗口。
  void _openChapter(String? uuid) {
    if (uuid != null) _ctl.open(uuid);
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl.current;
    final pages = c?.pages;
    final n = pages?.length ?? 0;
    final pad = MediaQuery.paddingOf(context);
    // 两条栏用缓存值排：沉浸态下 pad 是 0，用它会让栏在切换瞬间跳动。
    final top = _insetTop > 0 ? _insetTop : pad.top;
    final bottom = _insetBottom > 0 ? _insetBottom : pad.bottom;
    return Scaffold(
      backgroundColor: ReaderPalette.reader,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: Motion.of(context, 200),
              switchInCurve: Motion.ease,
              switchOutCurve: Motion.ease,
              // 两套视图叠着淡入淡出，不位移：翻页轴不同，横移会打架。
              //
              // 但纯交叉淡化会让人同时看见两张排版不同的页面（左图 4 格、
              // 右图 6 格），眼睛读成「两个东西在交换」。过渡中给一点模糊，
              // 把两个状态糊在一起，才读得成「一页变成了一页」。
              transitionBuilder: (child, animation) => AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, c) {
                  final v = animation.value;
                  if (v >= 1) return c!;
                  final sigma = 2 * (1 - v) * (Motion.reduced(context) ? 0 : 1);
                  return Opacity(
                    opacity: v,
                    child: sigma <= 0.01 ? c! : ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: c),
                  );
                },
              ),
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [
                  // 旧的在下、新的在上，淡入盖住淡出，中途不会露出背板色。
                  for (final child in previous) child,
                  ?current,
                ],
              ),
              child: KeyedSubtree(key: ValueKey(_mode), child: _readerBody()),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _brightness,
                builder: (context, b, _) => ColoredBox(color: Colors.black.withValues(alpha: (1 - b) * .75)),
              ),
            ),
          ),
          // 顶部栏：整条栏 + 大标题（拷贝漫画式布局）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ChromeReveal(
              visible: _chrome,
              dy: -8,
              child: ReaderTopBar(
                mangaTitle: widget.comic.name,
                chapterTitle: c?.name ?? '',
                onBack: () => Navigator.pop(context),
                topInset: top,
              ),
            ),
          ),
          // 底部控制栏：上一话 · 页码滑块 · 下一话 + 设置 / 目录
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChromeReveal(
              visible: _chrome,
              dy: 8,
              child: ReaderControlBar(
                onSettings: _showSettings,
                onCatalog: c == null ? () {} : () => _showCatalog(c),
                onPrevChapter: c?.chapter.prev == null ? null : () => _openChapter(c!.chapter.prev),
                onNextChapter: c?.chapter.next == null ? null : () => _openChapter(c!.chapter.next),
                currentPage: n == 0 ? 0 : _page + 1,
                totalPages: n,
                onPageChange: (i) => _ctl.jumpTo(i),
                bottomInset: bottom,
              ),
            ),
          ),
          // 控件隐藏时：底部居中显示页码
          if (!_chrome && n > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + 18,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '${_page + 1} / $n',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, color: ReaderPalette.muted, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ),
          if (_tip)
            Positioned.fill(
              child: _GestureTip(area: _prefs.mangaArea, vertical: _mode.isVertical, reversed: _mode.reversed, onTap: _closeTip),
            ),
        ],
      ),
    );
  }

  /// 阅读区：新引擎的 ReaderView，三话连续、支持跨话接续。
  ///
  /// 返回值会缓存：只有阅读方式 / 画质 / 点击区域 / 引擎状态变化时才重建，
  /// 拖亮度或改预加载页数不会碰它。
  Widget _readerBody() {
    if (_body != null) return _body!;
    final body = _buildBody();
    _body = body;
    return body;
  }

  Widget _buildBody() {
    final c = _ctl.current;
    if (c == null || _ctl.loading) {
      return Center(child: CupertinoActivityIndicator(color: ReaderPalette.muted, radius: 12));
    }
    if (_ctl.error != null) {
      return Center(
        child: Unavailable(
          dark: true,
          icon: 'wifiOff',
          title: '这一话没有载入',
          message: _ctl.error!,
          actions: [
            AccentButton(label: '重试', icon: 'refresh', onTap: () => _ctl.retry()),
          ],
        ),
      );
    }
    if (c.locked || (c.pages?.isEmpty ?? true)) return _locked(c);
    return ReaderView(
      controller: _ctl,
      mode: _mode,
      navigation: ReaderNavigation(area: _prefs.mangaArea, mode: _mode),
      onMenu: () => _setChrome(!_chrome),
      pageBuilder: (context, page) => _imagePage(page),
      transitionBuilder: (context, t) => ReaderTransition(
        transition: t,
        // 纵向阅读（含上下翻页）现在也走连续列表，过渡页必须有确定高度，
        // 所以这里传 stacked 而不是 continuous。
        continuous: _mode.stacked,
        onRetry: (ch) => _ctl.retryChapter(ch),
        onCatalog: () => _showCatalog(c),
        onBackToChapter: () => _ctl.jumpTo(0),
        onOpenChapter: (uuid) => _ctl.open(uuid),
      ),
    );
  }

  /// 一页的图片。
  ///
  /// 适配方式由「图片适配」设置决定（见 [PageFit]）。纵向阅读（条漫和上下翻页）
  /// 一律按宽度铺满并让高度跟着原比例走，这样页面自然首尾相接、上下不再出现
  /// 背板色的白边；横向翻页默认整页适应。
  ///
  /// [PageFit.original] 不能用 `BoxFit.none` 直接塞进铺满的容器：`none` 会把
  /// 图片按原始像素居中，小于屏幕时四周留空、大于屏幕时被裁掉。所以这里包一层
  /// `Align`，让它从顶部对齐、超出的部分由外层裁掉，滚动阅读才不会一段悬空。
  Widget _imagePage(ReaderPage page) {
    final url = imageUrlFor(page.url, saver: _saver);
    final size = MediaQuery.sizeOf(context);
    final applies = _fit.resolve(mode: _mode);
    final width = size.width;

    // 铺满宽度的模式必须显式给宽度：图片还没到时先占住位置，加载完成不会顶一下。
    final fillsWidth = applies == PageFit.width;
    final placeholderHeight = fillsWidth ? width * 1.4 : null;

    Widget image = CachedNetworkImage(
      key: ValueKey('$url#$_retry#${applies.name}'),
      imageUrl: url,
      httpHeaders: AppConfig.imageHeaders,
      fit: applies.boxFit,
      width: applies == PageFit.original ? null : (fillsWidth ? width : null),
      fadeInDuration: const Duration(milliseconds: 120),
      progressIndicatorBuilder: (context, _, p) => SizedBox(
        height: placeholderHeight,
        child: Center(child: CupertinoActivityIndicator(color: ReaderPalette.muted)),
      ),
      errorWidget: (context, _, _) => SizedBox(
        height: placeholderHeight,
        child: Center(
          child: TextAction(
            label: '图片没有载入，点按重试',
            color: ReaderPalette.text,
            onTap: () {
              CachedNetworkImage.evictFromCache(url);
              setState(() {
                _retry++;
                _body = null;
              });
            },
          ),
        ),
      ),
    );

    if (applies == PageFit.original) {
      // 原始尺寸：从顶部居中，宽了由外层（ListView）裁掉两边，不做任何缩放。
      image = ClipRect(child: Align(alignment: Alignment.topCenter, child: image));
    } else if (applies == PageFit.height) {
      image = SizedBox(height: size.height, child: Align(alignment: Alignment.topCenter, child: image));
    }

    return image;
  }

  Widget _locked(ReaderChapter c) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glass(
            dark: true,
            radius: 20,
            child: SizedBox.square(
              dimension: 72,
              child: Center(child: AppIcon('lock', size: 26, color: ReaderPalette.text)),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '${widget.comic.name} · ${c.name}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ReaderPalette.muted),
          ),
          const SizedBox(height: 8),
          Text(
            c.locked ? '这一话需要会员' : '这一话暂时没有图片',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ReaderPalette.text),
          ),
          const SizedBox(height: 10),
          Text(
            c.locked ? '源站已将这一话标记为付费内容。\n栞间不会请求本话的图片。' : '源站没有返回这一话的图片，可以换一话试试。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.55, color: ReaderPalette.muted),
          ),
          const SizedBox(height: 26),
          Pressable(
            onTap: () => _showCatalog(c),
            child: Glass(
              dark: true,
              radius: 25,
              child: SizedBox(
                width: 220,
                height: 50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '回到目录',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ReaderPalette.text),
                    ),
                    SizedBox(width: 8),
                    AppIcon('list', size: 18, color: ReaderPalette.text),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Pressable(
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon('chevronLeft', size: 15, color: ReaderPalette.text, stroke: 2),
                  SizedBox(width: 6),
                  Text('返回', style: TextStyle(fontSize: 15, color: ReaderPalette.text)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// 换阅读方式：立即写入，过渡由 [_readerBody] 外面的交叉淡入负责。
  ///
  /// 以前这里是「先压遮罩 140ms → 换 → 再等一帧 → 撤遮罩」。那 140ms 里
  /// 用户已经点了却什么都没发生，读起来就是「卡了一下」；遮罩本身在浅色
  /// 主题下还会闪一下灰。现在点下去立刻换，新旧两套视图 200ms 交叉淡入。
  void _setMode(ReadingMode m) {
    if (m == _mode) return;
    // 只写偏好；`_onPrefs` 会识别出阅读方式变了并重建阅读区。
    _prefs.mangaMode = m.preference;
  }

  void _showSettings() => showAppSheet<void>(
        context,
        // onClose 要收 sheet 自己的 context——外层 context 弹不掉这个路由。
        (sheet) => ReaderSettingsSheet(
          mode: _mode,
          onMode: _setMode,
          prefetch: _prefs.mangaPrefetch,
          // 预加载页数不影响任何可见结构，直接存。
          onPrefetch: (v) => _prefs.mangaPrefetch = v,
          area: _prefs.mangaArea,
          onArea: (v) => _prefs.mangaArea = v,
          onClose: () => Navigator.pop(sheet),
          saver: _prefs.mangaSaver,
          onSaver: (v) => _prefs.mangaSaver = v,
          brightness: _prefs.mangaBrightness,
          // 亮度走通知器，不触发整页重建。
          onBrightness: (v) => _prefs.mangaBrightness = v,
        ),
        scrim: kSheetScrimReader,
      );

  void _showCatalog(ReaderChapter c) => showAppSheet<void>(
    context,
    scrim: kSheetScrimReader,
    (sheet) => _CatalogSheet(
      comic: widget.comic,
      group: c.chapter.groupPathWord.isEmpty ? widget.group : c.chapter.groupPathWord,
      current: c.chapter,
      page: _page,
      pageCount: _images.length,
      onPick: (uuid) {
        Navigator.pop(sheet);
        _ctl.open(uuid);
      },
    ),
  );
}

/// 首次进入阅读器时的分区提示：用半透明色块画出「哪里翻页、哪里切控件」，
/// 3 秒后自动淡出，点一下也能关。
///
/// 形状沿用了 PasteMangaX 的 `ReaderGestureTipsView`：上下分区画成一竖一横的 L 形，
/// 左右分区画成三块竖条，颜色用绿=上一页、红=下一页，和那个项目的取色一致。
class _GestureTip extends StatefulWidget {
  const _GestureTip({required this.area, required this.vertical, required this.reversed, required this.onTap});

  final int area;
  final bool vertical;
  final bool reversed;
  final VoidCallback onTap;

  @override
  State<_GestureTip> createState() => _GestureTipState();
}

class _GestureTipState extends State<_GestureTip> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();

  static const _prev = Color(0x6651CF66);
  static const _next = Color(0x66FF6B6B);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = size.height;
    final w = size.width;
    // 0 关闭：没有分区，全部是「切换控件」。1 自适应：竖向用 L 形，横向用左右。
    final area = widget.area == 1 ? (widget.vertical ? 3 : 2) : widget.area;
    // 反向阅读时上一页/下一页的色块对调。
    final prev = widget.reversed ? _next : _prev;
    final next = widget.reversed ? _prev : _next;
    // 「左 / 右」在反向阅读时互换。
    final left = widget.reversed ? next : prev;
    final right = widget.reversed ? prev : next;

    return FadeTransition(
      opacity: _c,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: const Color(0x59000000))),
            // ── 分区色块：绿=上一页，红=下一页 ──
            switch (area) {
              // 关闭：不画分区，只留中间的说明。
              0 => const SizedBox.shrink(),
              // 左右三分：左 1/3 上一页，右 1/3 下一页，中间切换控件。
              2 => Stack(children: [
                  Positioned(top: 0, bottom: 0, left: 0, width: w / 3, child: ColoredBox(color: left)),
                  Positioned(top: 0, bottom: 0, right: 0, width: w / 3, child: ColoredBox(color: right)),
                ]),
              // L 形：上 1/3、左中 上一页；下 1/3、右中 下一页。
              3 => Stack(children: [
                  Positioned(top: 0, left: 0, right: 0, height: h / 3, child: ColoredBox(color: prev)),
                  Positioned(bottom: 0, left: 0, right: 0, height: h / 3, child: ColoredBox(color: next)),
                  Positioned(top: 0, left: 0, width: 44, height: h / 3, child: ColoredBox(color: prev)),
                ]),
              // 边缘：两侧 1/3 下一页，中间底部 1/3 上一页。
              4 => Stack(children: [
                  Positioned(top: 0, bottom: 0, left: 0, width: w / 3, child: ColoredBox(color: left)),
                  Positioned(top: 0, bottom: 0, right: 0, width: w / 3, child: ColoredBox(color: right)),
                  Positioned(bottom: 0, left: w / 3, width: w / 3, height: h / 3, child: ColoredBox(color: prev)),
                ]),
              // Kindle：左侧 1/3 上一页，其余 2/3 下一页，顶部 1/3 切换控件（不画色块）。
              _ => Stack(children: [
                  Positioned(top: h / 3, bottom: 0, left: 0, width: w / 3, child: ColoredBox(color: left)),
                  Positioned(top: h / 3, bottom: 0, left: w / 3, right: 0, child: ColoredBox(color: right)),
                ]),
            },
            // ── 中间：切换控件 ──
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('中间点按', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: .72))),
                      const SizedBox(height: 4),
                      const Text('显示 / 隐藏控件', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
            // ── 分区文字：跟着上面画出的色块位置走 ──
            ..._regionLabels(area, w, h, prev, next),
            Positioned(
              bottom: 44,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Text('点按任意处关闭提示', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .55))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 各个分区方案下，「上一页 / 下一页」文字该摆在哪。
  List<Widget> _regionLabels(int area, double w, double h, Color prev, Color next) {
    Widget at({double? top, double? bottom, double? left, double? right, required String text}) => Positioned(
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          child: IgnorePointer(child: Center(child: _label(text))),
        );
    return switch (area) {
      0 => const [],
      2 => [
          Positioned(top: 0, bottom: 0, left: 0, width: w / 3, child: Center(child: _label('上一页'))),
          Positioned(top: 0, bottom: 0, right: 0, width: w / 3, child: Center(child: _label('下一页'))),
        ],
      3 => [
          at(top: 96, left: 0, right: 0, text: '上一页'),
          at(bottom: 110, left: 0, right: 0, text: '下一页'),
        ],
      4 => [
          Positioned(top: 0, bottom: 0, left: 0, width: w / 3, child: Center(child: _label('下一页'))),
          Positioned(top: 0, bottom: 0, right: 0, width: w / 3, child: Center(child: _label('下一页'))),
          at(bottom: 150, left: 0, right: 0, text: '上一页'),
        ],
      _ => [
          Positioned(top: h / 3, bottom: 0, left: 0, width: w / 3, child: Center(child: _label('上一页'))),
          at(top: h * .55, left: 0, right: 0, text: '下一页'),
        ],
    };
  }

  Widget _label(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: const Color(0x59000000), borderRadius: BorderRadius.circular(14)),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
      );
}

/// 阅读中的目录：深色面板，分组、条目区间、排序与定位。
class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet({required this.comic, required this.group, required this.current, required this.page, required this.pageCount, required this.onPick});

  final ComicBrief comic;
  final String group;
  final Chapter current;
  final int page;
  final int pageCount;
  final ValueChanged<String> onPick;

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  late final _browser = ChapterBrowser(widget.comic.pathWord)..init(preferGroup: widget.group, locateIndex: widget.current.index);
  final _currentKey = GlobalKey();
  final _firstKey = GlobalKey();
  bool _located = false;

  @override
  void initState() {
    super.initState();
    _browser.addListener(_onBrowser);
  }

  void _onBrowser() {
    if (!_located && !_browser.loading && _browser.items != null) {
      _located = true;
      final index = _browser.items!.indexWhere((c) => c.uuid == widget.current.uuid);
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => revealChapterRow(firstKey: _firstKey, targetKey: _currentKey, index: index, rowExtent: 52));
      }
    }
  }

  void _locate() {
    _located = false;
    _browser.locate(widget.current.index, inGroup: widget.group);
    _onBrowser();
  }

  @override
  void dispose() {
    _browser.removeListener(_onBrowser);
    _browser.dispose();
    super.dispose();
  }

  /// 目录面板与阅读设置面板共用一套视觉令牌：实底 [ReaderPalette.sheet] +
  /// 27 的顶圆角 + 拖拽把手，不再走 `Glass`。毛玻璃在这里本来就不合适——
  /// 目录是一张要逐条读的列表，背景透出漫画画面只会让字更难认。
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final maxH = (screenH - pad.top - 120).clamp(0.0, screenH * .86);
    final shape = BorderRadius.vertical(top: Radius.circular(ReaderPalette.sheetRadius));

    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(color: IosColors.isDark ? const Color(0x33000000) : const Color(0x22000000), blurRadius: 22, offset: const Offset(0, -3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: ColoredBox(
          color: ReaderPalette.sheet,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListenableBuilder(
              listenable: _browser,
              builder: (context, _) {
                final items = _browser.items ?? const <Chapter>[];
                final ranges = _browser.ranges;
                final groups = _browser.groups;
                final groupIndex = groups.isEmpty ? 0 : groups.indexWhere((g) => g.pathWord == _browser.group).clamp(0, groups.length - 1);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: ReaderPalette.grip, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 16, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('目录', style: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, letterSpacing: .015, color: ReaderPalette.text)),
                                const SizedBox(height: 2),
                                Text(widget.comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 20 / 13, color: ReaderPalette.muted)),
                              ],
                            ),
                          ),
                          _SheetIcon(icon: 'locate', label: '定位到在读', onTap: _locate),
                          const SizedBox(width: 8),
                          _SheetIcon(icon: 'xmark', label: '关闭', onTap: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                    // 分组：多分卷时退化成和设置面板一样的胶囊行，不再用分段控件——
                    // 分段控件的滑页指示器是 iOS 那套，放在这个面板里显得外来。
                    if (groups.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                        child: SizedBox(
                          height: ReaderPalette.choiceHeight,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 22),
                            itemCount: groups.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (context, i) => ReaderPill(label: groups[i].name, selected: i == groupIndex, onTap: () => _browser.selectGroup(groups[i].pathWord)),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 14, 4),
                      child: Row(
                        children: [
                          Text('条目序号', style: TextStyle(fontSize: 13, height: 20 / 13, color: ReaderPalette.muted)),
                          const Spacer(),
                          Pressable(
                            onTap: _browser.toggleOrder,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon('sort', size: 15, color: ReaderPalette.text, stroke: 1.9),
                                  const SizedBox(width: 4),
                                  Text(_browser.descending ? '降序' : '升序', style: TextStyle(fontSize: 13, height: 20 / 13, color: ReaderPalette.text)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ranges.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
                        child: SizedBox(
                          height: ReaderPalette.choiceHeight,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 22),
                            itemCount: ranges.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (context, i) {
                              final idx = _browser.rangeOrder[i];
                              return ReaderPill(
                                label: ChapterBrowser.rangeLabel(ranges[idx]),
                                selected: idx == _browser.rangeIndex.clamp(0, ranges.length - 1),
                                onTap: () => _browser.selectRange(idx),
                              );
                            },
                          ),
                        ),
                      ),
                    Flexible(
                      fit: FlexFit.loose,
                      child: _browser.error != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: TextAction(label: '目录加载失败，点按重试', color: ReaderPalette.text, onTap: _browser.retry)),
                            )
                          : (_browser.loading || _browser.items == null)
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 60),
                                  child: Center(child: CupertinoActivityIndicator()),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.fromLTRB(14, 6, 14, 16 + pad.bottom),
                                  itemCount: items.length,
                                  itemBuilder: (context, i) {
                                    final ch = items[i];
                                    final isCurrent = ch.uuid == widget.current.uuid;
                                    return KeyedSubtree(
                                      key: i == 0 ? _firstKey : null,
                                      child: _CatalogRow(
                                        key: isCurrent ? _currentKey : null,
                                        chapter: ch,
                                        first: i == 0,
                                        read: LibraryStore.instance.isRead(widget.comic.pathWord, ch.uuid),
                                        current: isCurrent,
                                        page: widget.page,
                                        pageCount: widget.pageCount,
                                        onTap: () => widget.onPick(ch.uuid),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 目录里的面板工具按钮：40 的圆角方钮，和瓦片同一族的表面色。
class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    semanticLabel: label,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: ReaderPalette.surface, borderRadius: BorderRadius.circular(ReaderPalette.choiceRadius)),
      child: Center(child: AppIcon(icon, size: 18, color: ReaderPalette.text, stroke: 1.9)),
    ),
  );
}

/// 目录条目。行高固定 52，`revealChapterRow` 按这个值算滚动位置，不能改。
///
/// 不复用 `IosChapterRow`：那个是详情页的样式，强调色用的是暖棕，
/// 放在这个灰蓝面板里会跳出来。
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({super.key, required this.chapter, required this.first, required this.read, required this.current, required this.page, required this.pageCount, required this.onTap});

  final Chapter chapter;
  final bool first;
  final bool read;
  final bool current;
  final int page;
  final int pageCount;
  final VoidCallback onTap;

  static const _extent = 52.0;

  @override
  Widget build(BuildContext context) {
    final tag = chapterTag(chapter.name);
    return Pressable(
      onTap: onTap,
      child: Container(
        height: _extent,
        margin: current ? const EdgeInsets.symmetric(vertical: 2) : EdgeInsets.zero,
        padding: EdgeInsets.symmetric(horizontal: current ? 14 : 10),
        decoration: BoxDecoration(
          color: current ? ReaderPalette.selected : null,
          borderRadius: BorderRadius.circular(ReaderPalette.choiceRadius),
          border: first || current ? null : Border(top: BorderSide(color: ReaderPalette.border, width: .5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                '${chapter.index + 1}',
                style: TextStyle(fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()], color: current ? ReaderPalette.selectedInk : ReaderPalette.muted),
              ),
            ),
            Expanded(
              child: Text(
                chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  color: current ? ReaderPalette.selectedInk : (read ? ReaderPalette.muted : ReaderPalette.text),
                ),
              ),
            ),
            if (current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: ReaderPalette.sheet, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  pageCount > 0 ? '在读 ${page.clamp(0, pageCount - 1) + 1}/$pageCount' : '在读',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ReaderPalette.selectedInk, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              )
            else ...[
              if (tag.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: ReaderPalette.surface, borderRadius: BorderRadius.circular(6)),
                  child: Text(tag, style: TextStyle(fontSize: 11, color: ReaderPalette.muted)),
                ),
                const SizedBox(width: 8),
              ],
              AppIcon(read ? 'check' : 'right', size: read ? 15 : 13, color: ReaderPalette.muted, stroke: 2),
            ],
          ],
        ),
      ),
    );
  }
}
