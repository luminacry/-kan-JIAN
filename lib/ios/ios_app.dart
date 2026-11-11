import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/account.dart';
import '../core/config.dart';
import '../core/installer.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/update_service.dart';
import '../ui/format.dart' show formatBytes;
import '../ui/icons.dart';
import '../ui/tokens.dart' show Dock, ScrollEdge;
import 'ios_detail.dart';
import 'ios_discover.dart';
import 'ios_mine.dart';
import 'ios_novel.dart';
import 'ios_reader.dart';
import 'ios_search.dart';
import 'ios_shelf.dart';
import '../core/wenku_web.dart';
import '../ui/motion.dart';
import '../ui/edge_blur.dart';
import 'ios_theme.dart';
import 'ios_wenku_novel.dart';

class IosApp extends StatefulWidget {
  const IosApp({super.key});

  @override
  State<IosApp> createState() => _IosAppState();
}

/// 根据「外观设置」和系统外观决定深浅色；切换时整棵树重建，当前页面和导航栈都保留。
class _IosAppState extends State<IosApp> with WidgetsBindingObserver {
  final _prefs = ReaderPrefs.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prefs.addListener(_apply);
    GlassScope.reduce.value = _prefs.reduceTransparency;
    IosColors.isDark = _wantDark;
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefs.removeListener(_apply);
    super.dispose();
  }

  bool get _wantDark => switch (_prefs.appearance) {
    1 => false,
    2 => true,
    _ => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
  };

  @override
  void didChangePlatformBrightness() => _apply();

  void _apply() {
    final dark = _wantDark;
    if (dark == IosColors.isDark || !mounted) return;
    IosColors.isDark = dark;
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
    // 颜色是静态取值，没有依赖关系可通知，所以把所有元素都标脏重建一次。
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    setState(() {});
    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '栞间',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 根部挂一个 1×1 的隐藏 WebView：轻小说源站拦下 HTTP 客户端时用它取页面。
      // iOS 外面再包一层 Liquid Glass（让玻璃组件能读到 MaterialApp 的明暗模式）；
      // 安卓走毛玻璃，不需要这层。
      builder: (context, child) => _Shell(
        child: Stack(
          children: [
            child!,
            Positioned(left: 0, top: 0, child: WenkuWebFetcher.instance.host()),
          ],
        ),
      ),
      home: const IosShell(),
    );
  }
}

/// iOS 才包 Liquid Glass 的包裹层；安卓只挂 GlassScope（毛玻璃不需要库的上下文）。
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scoped = GlassScope(reduce: GlassScope.reduce, child: child);
    if (!Platform.isIOS) return scoped;
    return LiquidGlassWidgets.wrap(brightnessResolver: Theme.maybeBrightnessOf, child: scoped);
  }
}

class IosShell extends StatefulWidget {
  const IosShell({super.key});

  static final tab = ValueNotifier<int>(0);

  /// 当前页的连续位置（0.0 ~ 2.0），拖拽过程中随手指变化，标签栏选中框据此跟手移动。
  static final pagePos = ValueNotifier<double>(0);

  /// 搜索球的 key。搜索页从它所在的位置「长出来」，所以要拿到它的屏幕矩形。
  static final searchBallKey = GlobalKey();

  /// 测试里关掉启动时的更新检查。
  static bool autoUpdateCheck = true;

  @override
  State<IosShell> createState() => _IosShellState();
}

class _IosShellState extends State<IosShell> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
    if (IosShell.autoUpdateCheck) Future.delayed(const Duration(seconds: 3), _autoCheck);
    // 已登录账号时，打开应用稍后同步一次源站书架和历史（30 分钟内同步过就跳过）。
    if (AccountService.autoSync && AccountService.instance.loggedIn) Future.delayed(const Duration(seconds: 2), AccountService.instance.autoSyncIfDue);
  }

  Future<void> _autoCheck() async {
    final r = await UpdateService.instance.autoCheck();
    if (r != null && mounted) showIosUpdateDialog(context, r);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: IosShell.tab,
    // Android 返回键：在发现 / 我的上先回到书架，再退出应用。
    builder: (context, index, _) => PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) IosShell.tab.value = 0;
      },
      child: Scaffold(
        body: Stack(
          children: [
            // 首次进入：内容由下方 7px 淡入归位（只在启动时播一次）；切换标签用 fade-through。
            Positioned.fill(
              child: FadeSlideIn(
                delayMs: 45,
                child: _TabStack(index: index, children: const [IosShelfPage(), IosDiscoverPage(), IosMinePage()]),
              ),
            ),
            // 底部渐进模糊：让悬浮标签栏下的内容渐次虚化、被底色盖住。
            //
            // 以前这里只是一条「透明 → 92% 底色」的渐变。底色能盖住内容，却
            // 盖不住细节：高对比的漫画封面糊不掉，边缘还能看出形状，读起来就是
            // 一块被压暗的图而不是一层材质。现在改成真模糊 + 渐浓底色，
            // 对应 iOS 26 的 scroll edge effect（`.soft`）。
            //
            // 长度分两段（见 [ScrollEdge]）：标签栏那截均匀糊掉，栏外由
            // [ScrollEdge.tail] 渐次变清楚——和顶部用同一个过渡长度。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: EdgeBlur(
                covered: ScrollEdge.bottomCovered(context),
                tail: ScrollEdge.tail,
                sigma: 18,
                side: EdgeBlurSide.bottom,
                tint: IosColors.bg,
                tintAlpha: .72,
              ),
            ),
            // 顶部渐进模糊：状态栏 + 一段等长的过渡。内容滚上来时从这里开始
            // 虚化，大标题滚到状态栏下面不是被一刀切断，而是慢慢糊进去。
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: EdgeBlur(
                covered: ScrollEdge.topCovered(context),
                tail: ScrollEdge.tail,
                sigma: 10,
                tint: IosColors.bg,
                tintAlpha: .55,
              ),
            ),
            _TabDock(index: index),
          ],
        ),
      ),
    ),
  );
}

/// 三个标签页常驻（保留各自的滚动位置），可左右拖拽切换：跟 iOS 原生分页一样，
/// 拖到一半松手会吸附到最近的一页，首尾有回弹。
///
/// 点标签栏也走同一个 [PageController]，所以点按和拖拽共用一套位置状态，
/// 不会出现「点完又滑回去」的错位。
class _TabStack extends StatefulWidget {
  const _TabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack> {
  late final _pages = PageController(initialPage: widget.index);

  /// 用户是否正用手指拖拽。只有拖拽产生的翻页才写回 [IosShell.tab]；
  /// 程序自己 animateToPage 时不能写回，否则会盖掉外部刚写入的值
  /// （例如返回键把标签设为 0、但上一段动画还没结束）。
  bool _dragging = false;

  /// 当前活着的分页器。安卓的胶囊标签栏要能直接左右拖，而它和这里没有
  /// 父子关系（都在同一个 Stack 里），所以用静态引用把拖动传进来。
  static _TabStackState? _active;

  @override
  void initState() {
    super.initState();
    _active = this;
    // 重建（热重启、测试里换树）时把选中框位置对齐到起始页，不受上次遗留的值影响。
    IosShell.pagePos.value = widget.index.toDouble();
  }

  /// 标签栏横向拖动：直接推分页器的像素位置，松手再吸附。
  ///
  /// 走 `jumpTo` 而不是 `animateToPage`：拖拽期间位置必须跟手，
  /// 动画式的滚动会让手指和页面对不上。
  static void dragBy(double dx) {
    final s = _active;
    if (s == null || !s._pages.hasClients) return;
    final pos = s._pages.position;
    final target = (pos.pixels - dx).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    pos.jumpTo(target);
    final p = target / pos.viewportDimension;
    IosShell.pagePos.value = p.clamp(0.0, 2.0);
  }

  /// 标签栏松手：吸附到最近的一页，并把选中标签写回去。
  static void dragEnd() {
    final s = _active;
    if (s == null || !s._pages.hasClients) return;
    final pos = s._pages.position;
    final target = (pos.pixels / pos.viewportDimension).round().clamp(0, 2);
    final d = Motion.ms(300);
    if (d == Duration.zero) {
      pos.jumpTo(target * pos.viewportDimension);
    } else {
      s._pages.animateToPage(target, duration: d, curve: Motion.ease);
    }
    if (IosShell.tab.value != target) IosShell.tab.value = target;
  }

  @override
  void didUpdateWidget(_TabStack old) {
    super.didUpdateWidget(old);
    if (!_pages.hasClients) return;
    // 已经停在这一页（例如拖拽结束刚写回的同一个值），不用再动。
    if ((_pages.page ?? widget.index.toDouble()).round() == widget.index) return;
    final d = Motion.of(context, 320);
    if (d == Duration.zero) {
      _pages.jumpToPage(widget.index);
    } else {
      _pages.animateToPage(widget.index, duration: d, curve: Motion.ease);
    }
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: (n) {
      if (n is ScrollStartNotification) {
        _dragging = n.dragDetails != null;
      } else if (n is ScrollEndNotification) {
        _dragging = false;
      }
      // 标签栏的选中框跟着页面连续移动（原生就是这样，不是翻完才跳一格）。
      final p = _pages.hasClients ? _pages.page : null;
      if (p != null && IosShell.pagePos.value != p) IosShell.pagePos.value = p;
      return false;
    },
    child: PageView(
      controller: _pages,
      // 预构建相邻的一页：标签切换时内容已经在加载，不用等滑过去才转圈；
      // 读屏软件按页推进也依赖这个。
      allowImplicitScrolling: true,
      // 首尾回弹，和 iOS 的 UIScrollView 一致；Android 上也照样用，界面本来就是 iOS 风。
      physics: const PageScrollPhysics().applyTo(const BouncingScrollPhysics()),
      onPageChanged: (i) {
        if (!_dragging) return;
        if (IosShell.tab.value != i) IosShell.tab.value = i;
      },
      children: [
        for (final child in widget.children)
          // 离开屏幕也保活，滚动位置和已加载的数据不会因为滑走而丢。
          _KeepAlive(child: child),
      ],
    ),
  );
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _TabDock extends StatelessWidget {
  const _TabDock({required this.index});

  final int index;

  static const _items = [('book', 'bookFill', '书架'), ('compass', 'compassFill', '发现'), ('person', 'personFill', '我的')];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      // 高度必须显式给：不给的话胶囊会按内容撑到 ~49，比右边的搜索球（64）矮一截，
      // 看上去就是被压扁的一条。
      height: Dock.height,
      // 抬到系统手势区之上，而不是压进去。以前是 `bottom - 6`，小白条正好盖在
      // 胶囊底部和搜索球下沿。
      bottom: Dock.bottom(context),
      child: ListenableBuilder(
        listenable: LibraryStore.instance,
        builder: (context, _) {
          final hasUpdate = LibraryStore.instance.entries.any((e) => e.hasUpdate);
          // iOS 用库的 GlassTabBar（水母胶囊形变 + 栏上直接拖动）。
          // 安卓用它只会画出 2D 轻量着色器，观感不如原来的毛玻璃，所以走 _frostedDock。
          if (!Platform.isIOS) {
            return ValueListenableBuilder<double>(
              valueListenable: IosShell.pagePos,
              builder: (context, pos, _) => _frostedDock(context, pos.clamp(0, (_items.length - 1).toDouble()), hasUpdate),
            );
          }
          return GlassTabBar.bottom(
            tabs: [
              for (var i = 0; i < _items.length; i++)
                GlassTab(
                  // 图标和文字的颜色由库里按选中状态套 IconTheme / 文字样式，
                  // 所以 AppIcon 不传颜色（它默认取 IconTheme）。
                  icon: AppIcon(_items[i].$1, size: 23, stroke: 1.7),
                  activeIcon: AppIcon(_items[i].$2, size: 23, stroke: 1.7),
                  label: _items[i].$3,
                  semanticLabel: i == 0 && hasUpdate && index != 0 ? '${_items[i].$3}，有更新' : _items[i].$3,
                ),
            ],
            selectedIndex: index,
            onTabSelected: (i) {
              if (IosShell.tab.value != i) IosShell.tab.value = i;
            },
            extraButton: GlassTabBarExtraButton(
              icon: KeyedSubtree(
                key: IosShell.searchBallKey,
                child: AppIcon('search', size: 25, stroke: 1.8),
              ),
              label: '搜索',
              onTap: () => openSearch(context, origin: rectOf(IosShell.searchBallKey.currentContext ?? context)),
            ),
            // 与我们原来的尺寸对齐：左右各 18，高度 64，标签栏和搜索按钮同一条玻璃。
            horizontalPadding: 18,
            verticalPadding: 0,
            spacing: 12,
            barHeight: 64,
            barBorderRadius: 32,
            iconSize: 23,
            labelFontSize: 11,
            selectedIconColor: IosColors.accent,
            unselectedIconColor: IosColors.tab,
            selectedLabelColor: IosColors.accent,
            unselectedLabelColor: IosColors.tab,
            indicatorColor: const Color(0x1A747070),
            indicatorPinchStrength: .4,
            quality: GlassQuality.premium,
          );
        },
      ),
    );
  }

  /// 安卓的标签栏：毛玻璃胶囊 + 自己算的选中块。
  ///
  /// 和 iOS 一样可以直接在栏上左右拖：拖动交给分页器，松手吸附到最近一页。
  /// 选中块按 `active`（连续位置取整）移动，和 iOS 的跟手机制对齐。
  Widget _frostedDock(BuildContext context, double pos, bool hasUpdate) {
    final active = pos.round().clamp(0, _items.length - 1);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => _TabStackState.dragBy(d.delta.dx),
      onHorizontalDragEnd: (_) => _TabStackState.dragEnd(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          // 撑满 64 高，和右边固定 64 的搜索球一致。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Glass(
                radius: 32,
                padding: const EdgeInsets.all(5),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth / 3;
                    return Stack(
                      children: [
                        // 选中块跟着连续位置走（拖动时也跟手），不是翻完才跳一格。
                        // 只做位移：宽度固定一格，AnimatedSlide 走 transform，
                        // 不像 AnimatedPositioned 那样每帧重排。
                        AnimatedSlide(
                          duration: Motion.of(context, 240),
                          curve: Motion.ease,
                          offset: Offset(pos, 0),
                          child: SizedBox(
                            width: w,
                            height: double.infinity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: const Color(0x1A747070), borderRadius: BorderRadius.circular(27)),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _items.length; i++)
                              Expanded(
                                child: Pressable(
                                  haptic: true,
                                  pressedScale: .96,
                                  semanticLabel: i == 0 && hasUpdate && active != 0 ? '${_items[i].$3}，有更新' : _items[i].$3,
                                  onTap: () => IosShell.tab.value = i,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          AppIcon(i == active ? _items[i].$2 : _items[i].$1, size: 23, color: i == active ? IosColors.accent : IosColors.tab, stroke: 1.7),
                                          if (i == 0 && hasUpdate && active != 0)
                                            Positioned(
                                              top: -1,
                                              right: -3,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: IosColors.ink,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: IosColors.surface, width: 1.5),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _items[i].$3,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 14 / 11,
                                          color: i == active ? IosColors.accent : IosColors.tab,
                                          fontWeight: i == active ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Pressable(
              semanticLabel: '搜索',
              onTap: () => openSearch(context, origin: rectOf(IosShell.searchBallKey.currentContext ?? context)),
              child: Glass(
                radius: 32,
                child: SizedBox.square(
                  dimension: 64,
                  child: Center(
                    child: KeyedSubtree(
                      key: IosShell.searchBallKey,
                      child: AppIcon('search', size: 25, color: IosColors.ink, stroke: 1.8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/* ───────── 导航 ───────── */

ComicBrief briefOfEntry(ShelfEntry e) => ComicBrief(name: e.name, pathWord: e.id, cover: e.cover, authors: [e.author]);

Future<void> iosOpenDetail(BuildContext context, ComicBrief comic) => Navigator.of(context).push(appRoute((_) => IosDetailPage(comic: comic)));

/// 打开搜索页。[origin] 是触发它的控件的屏幕矩形——搜索页从那个点缩放展开，
/// 而不是整页侧滑进来。拿不到就传 null，按屏幕中心缩放。
Future<void> openSearch(BuildContext context, {Rect? origin}) =>
    Navigator.of(context).push(searchRoute((_) => const IosSearchPage(), origin: origin));

Future<void> iosOpenReader(BuildContext context, {required ComicBrief comic, required String group, required String chapterUuid, int initialPage = 0}) =>
    Navigator.of(context).push(readerRoute((_) => IosReaderPage(comic: comic, group: group, chapterUuid: chapterUuid, initialPage: initialPage)));

Future<void> iosOpenNovel(BuildContext context) => Navigator.of(context).push(readerRoute((_) => const IosNovelPage()));

/// 源站的轻小说（书架 id 是 `wenku-<aid>`）。内置示例小说仍走 [iosOpenNovel]。
Future<void> iosOpenWenkuNovel(BuildContext context, {required int aid, String name = ''}) => Navigator.of(context).push(readerRoute((_) => IosWenkuNovelPage(aid: aid, name: name)));

/// 继续阅读：小说进阅读器，漫画有进度进阅读器，否则进详情。
Future<void> iosContinue(BuildContext context, ShelfEntry e) {
  if (e.kind == ShelfKind.novel) {
    final aid = wenkuAidOf(e.id);
    return aid == null ? iosOpenNovel(context) : iosOpenWenkuNovel(context, aid: aid, name: e.name);
  }
  if (e.chapterUuid == null) return iosOpenDetail(context, briefOfEntry(e));
  return iosOpenReader(context, comic: briefOfEntry(e), group: e.group ?? 'default', chapterUuid: e.chapterUuid!, initialPage: e.page);
}

/* ───────── 更新 ───────── */

/// 新版本弹窗：公告取 GitHub Release 的正文，Android 可以在应用内下载并直接安装。
Future<void> showIosUpdateDialog(BuildContext context, UpdateResult r) {
  final release = r.release!;
  final meta = [
    '当前 v${r.current}',
    if (release.packageSize != null) '安装包 ${formatBytes(release.packageSize!)}',
    if (release.publishedAt != null) '${release.publishedAt!.month}月${release.publishedAt!.day}日发布',
  ].join(' · ');
  final notes = plainNotes(release.notes);
  return showAppSheet<void>(context, (_) => _UpdateSheet(release: release, meta: meta, notes: notes.isEmpty ? release.title : notes));
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.release, required this.meta, required this.notes});

  final AppRelease release;
  final String meta;
  final String notes;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  double? _progress;
  bool _downloading = false;
  String? _error;

  /// 只有 Android 且真有安装包时才能应用内下载；其余走浏览器。
  bool get _canInstall => defaultTargetPlatform == TargetPlatform.android && widget.release.packageUrl != null;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      final file = await UpdateService.instance.download(widget.release, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      final opened = await AppInstaller.install(file.path);
      if (!mounted) return;
      setState(() => _downloading = false);
      if (!opened) showIosToast(context, '请允许「安装未知应用」后再点一次下载');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '$e';
      });
    }
  }

  void _openBrowser() {
    Navigator.pop(context);
    launchUrl(Uri.parse(widget.release.downloadUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, MediaQuery.paddingOf(context).bottom + 10),
        child: Glass(
          radius: 30,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Text('发现新版本 v${widget.release.version}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: IosColors.ink)),
              const SizedBox(height: 4),
              Text(widget.meta, style: TextStyle(fontSize: 12, color: IosColors.muted)),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(widget.notes, style: TextStyle(fontSize: 14, height: 1.6, color: IosColors.ink)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(fontSize: 13, color: IosColors.accent)),
                const SizedBox(height: 6),
                Center(
                  child: TextAction(
                    label: '打开 Releases 手动下载',
                    color: IosColors.accent,
                    onTap: () async {
                      Navigator.pop(context);
                      await launchUrl(Uri.parse(AppConfig.githubReleasesPage), mode: LaunchMode.externalApplication);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 5,
                    backgroundColor: IosColors.faint,
                    valueColor: AlwaysStoppedAnimation(IosColors.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _progress == null ? '正在下载…' : '正在下载 ${(_progress! * 100).round()}%',
                    style: TextStyle(fontSize: 13, color: IosColors.muted),
                  ),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: TextAction(
                        label: '跳过此版本',
                        color: IosColors.muted,
                        onTap: () {
                          ReaderPrefs.instance.skipVersion = widget.release.version;
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Pressable(
                      onTap: _canInstall ? _download : _openBrowser,
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(color: IosColors.accent, borderRadius: BorderRadius.circular(23)),
                        child: Center(
                          child: Text(
                            _canInstall ? '下载并安装' : '下载',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: IosColors.onAccent),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_canInstall && !_downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: TextAction(label: '用浏览器下载', color: IosColors.muted, onTap: _openBrowser),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// 「我的」里的手动检查。检查失败时可以直接打开 Releases 页手动下载。
Future<UpdateResult> iosManualUpdateCheck(BuildContext context) async {
  final r = await UpdateService.instance.check();
  if (!context.mounted) return r;
  if (r.status == UpdateStatus.available) {
    await showIosUpdateDialog(context, r);
  } else if (r.status == UpdateStatus.failed) {
    final open = await showAppConfirm(
      context,
      title: '检查更新失败',
      message: '${r.message ?? '无法连接更新服务'}\n\n可以打开项目 Releases 页手动下载。',
      confirm: '打开 Releases',
      cancel: '稍后',
    );
    if (open) await launchUrl(Uri.parse(AppConfig.githubReleasesPage), mode: LaunchMode.externalApplication);
  } else {
    showIosToast(context, switch (r.status) {
      UpdateStatus.upToDate => r.message ?? '已是最新版本 v${r.current}',
      UpdateStatus.noRelease => '仓库还没有发布版本',
      _ => r.message ?? '检查更新失败',
    });
  }
  return r;
}
