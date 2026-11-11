import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart' show Space;

/// 全 App 的中性色板：纯黑白灰，没有任何主题色。
///
/// 以前这里有一个暖棕强调色（`#914638`），而阅读设置面板用的是另一套灰蓝，
/// 两个界面并排时色相打架。现在「强调」不再靠颜色表达，只靠三件事：
/// 实心反相（黑底白字 / 白底黑字）、描边、字重。所以 [accent] 直接等于 [ink]，
/// 任何原来取 accent 的地方都会自动变成主文字色，不会残留色相。
///
/// 深色模式是浅色模式的严格反相，不是另一套色板。
class IosColors {
  IosColors._();

  /// 当前是否深色模式，由 [IosApp] 根据「外观设置」和系统外观决定。
  static bool isDark = false;

  static Color get bg => isDark ? dBg : const Color(0xFFF7F7F8);
  static Color get surface => isDark ? dSurface : const Color(0xFFFFFFFF);
  static Color get ink => isDark ? dInk : const Color(0xFF17181C);
  static Color get muted => isDark ? dMuted : const Color(0xFF6C6D75);
  static Color get faint => isDark ? dFaint : const Color(0xFFEFEFF1);
  static Color get line => isDark ? dLine : const Color(0xFFE4E4E8);

  /// 强调 = 主文字色。不再有独立色相，详见类注释。
  static Color get accent => ink;

  /// 需要在深色块（例如封面上的角标）上写字时用它。
  static Color get accentSoft => faint;
  static Color get tab => isDark ? dMuted : const Color(0xFF5A5B62);

  /// 实心按钮上的文字：浅色模式黑底白字，深色模式白底黑字。
  static Color get onAccent => isDark ? const Color(0xFF16171A) : const Color(0xFFFFFFFF);

  /// 反相块（选中项、实心按钮）的底色。
  static Color get invert => isDark ? const Color(0xFFF2F2F4) : const Color(0xFF17181C);

  static const dBg = Color(0xFF111214);
  static const dSurface = Color(0xFF1D1E21);
  static const dInk = Color(0xFFF4F4F6);
  static const dMuted = Color(0xFF9C9DA5);
  static const dLine = Color(0xFF2E2F34);
  static const dFaint = Color(0xFF242529);
}

/// 系统栏：状态栏和 Android 导航栏都透明，内容画到后面。浅色页面用深色图标。
const kLightChrome = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

/// 普通页面的系统栏：跟随深色模式。
SystemUiOverlayStyle get pageChrome => IosColors.isDark ? kDarkChrome : kLightChrome;

/// 深色页面（漫画阅读器、深色纸张）用浅色图标。
const kDarkChrome = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

/// 小说正文用系统宋体（iOS 自带 Songti SC），Android 回退到 serif（Noto Serif CJK）。
const kIosSerif = TextStyle(fontFamily: 'Songti SC', fontFamilyFallback: ['STSong', 'serif']);

/// 应用主题。两端都按 iOS 平台处理：回弹滚动、右滑返回、Cupertino 控件。
ThemeData buildAppTheme() => ThemeData(
      platform: TargetPlatform.iOS,
      brightness: IosColors.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: IosColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: IosColors.accent,
        brightness: IosColors.isDark ? Brightness.dark : Brightness.light,
        primary: IosColors.accent,
        surface: IosColors.bg,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      cupertinoOverrideTheme: CupertinoThemeData(primaryColor: IosColors.accent, brightness: IosColors.isDark ? Brightness.dark : Brightness.light),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      }),
    );

/// 「减少透明度」：开启后玻璃控件改为实底。设置变化时依赖它的控件会重建。
class GlassScope extends InheritedNotifier<ValueNotifier<bool>> {
  const GlassScope({super.key, required ValueNotifier<bool> reduce, required super.child}) : super(notifier: reduce);

  static final reduce = ValueNotifier<bool>(false);

  static bool reduced(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GlassScope>();
    return (scope?.notifier?.value ?? false) || MediaQuery.highContrastOf(context);
  }

  static void set(bool v) {
    ReaderPrefs.instance.reduceTransparency = v;
    reduce.value = v;
  }
}

/// 玻璃材质：iOS 用 Liquid Glass（着色器折射），安卓用毛玻璃；减少透明度时都退回实底。
///
/// 只用于导航、工具和暂态面板，内容层保持实底。全 App 的玻璃都走这一个组件
/// （标签栏、浮动按钮、底部面板、阅读工具条），所以换材质只需要改这里。
///
/// **两端分开**：iOS 走 `liquid_glass_widgets` 的 [AdaptiveGlass]（Impeller 着色器，
/// 有折射、色散和高光）；安卓没有 Impeller 那套 `toImageSync` 背景抓取，库在安卓上
/// 只剩 2D 轻量路径或纯模糊，观感反而不如原来的毛玻璃，所以安卓保留
/// `BackdropFilter` + 半透明填充 + 细亮边的老实现。
///
/// iOS 上**必须显式选 `premium` 档**：库的默认值是 `standard`，走的是 2D 轻量着色器，
/// 只有模糊和高光，没有真正的折射——看上去和毛玻璃没区别。
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 22, this.dark = false, this.padding, this.shadow = true, this.quality = GlassQuality.premium});

  final Widget child;
  final double radius;
  final bool dark;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  /// 渲染档位，仅 iOS 生效。[GlassQuality.premium] 有折射；[GlassQuality.standard]
  /// 只有模糊，用在会跟着列表滚动的玻璃上（每帧抓背景纹理代价太高）。
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final reduce = GlassScope.reduced(context);
    final dark = this.dark || IosColors.isDark;
    final r = BorderRadius.circular(radius);
    final content = padding == null ? child : Padding(padding: padding!, child: child);

    // 减少透明度：不参与折射，直接用实底，和 iOS「降低透明度」的行为一致。
    if (reduce) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: shadow ? [BoxShadow(color: dark ? const Color(0x59000000) : const Color(0x1F1A1A28), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? IosColors.dSurface : const Color(0xFFF2F2F6),
              borderRadius: r,
              border: Border.all(color: dark ? const Color(0x2EFFFFFF) : const Color(0x8CFFFFFF), width: .8),
            ),
            child: content,
          ),
        ),
      );
    }

    // 安卓：毛玻璃。模糊 22 + 半透明填充 + 细亮边，和 0.3.6 之前一致。
    if (!Platform.isIOS) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: shadow ? [BoxShadow(color: dark ? const Color(0x59000000) : const Color(0x1F1A1A28), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: dark ? const Color(0xAD292A31) : const Color(0xB0F8F8FB),
                borderRadius: r,
                border: Border.all(color: dark ? const Color(0x2EFFFFFF) : const Color(0x8CFFFFFF), width: .8),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return AdaptiveGlass(
      quality: quality,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      // 这组数值是给 premium 档调的：premium 直接用原值（只有 standard 档会做归一化
      // 把 thickness 乘 0.4、lightIntensity 乘 0.6），所以光和色散要按 3D 着色的量级给。
      //
      // 2026-11 这一轮整体加强折射与透明：
      // - thickness 26 → 44：玻璃越厚弯折越强，边缘的"厚透镜"感才出来
      // - refractiveIndex 1.2 → 1.45：折射偏移更明显（1.0 是完全不弯折）
      // - chromaticAberration .12 → .34：色散翻倍，边缘开始有彩虹分离
      // - glassColor 不透明度 0x38/0x40 → 0x1A/0x22：染色更淡，背景透出更多
      // - lightIntensity 1.5 → 1.9：高光更亮，和更透的底子配
      // 注意 blur 保持中等偏低：糊太狠会把折射的位移藏掉，看起来就只是毛玻璃。
      settings: LiquidGlassSettings(
        blur: 7,
        thickness: 44,
        // 深色下用暗色染色，浅色下用极淡的白色，保留折射的同时压住背景杂色。
        glassColor: dark ? const Color(0x1A292A31) : const Color(0x22F8F8FB),
        lightIntensity: 1.9,
        refractiveIndex: 1.45,
        chromaticAberration: .34,
        saturation: 1.6,
        shadowElevation: shadow ? 1.0 : 0.0,
      ),
      child: content,
    );
  }
}

/// 按下时轻微缩放、变淡，替代 Material 水波纹。
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.haptic = false, this.semanticLabel, this.dimWhenDisabled = true, this.pressedScale = .975});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final String? semanticLabel;

  /// 没有 [onTap] 时是否变淡表示不可用。
  final bool dimWhenDisabled;

  /// 按下时的缩放：普通按钮 0.975，底部导航 0.96（设计稿）。
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  // 有自己的读屏标签时，不再把里面的文字重复读一遍。
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.semanticLabel,
        excludeSemantics: widget.semanticLabel != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          onLongPress: widget.onLongPress,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          // 按下 80ms 缩到 0.975、透明度 0.88；松开 180ms 恢复。
          child: AnimatedScale(
            scale: _down ? widget.pressedScale : 1,
            duration: Motion.of(context, _down ? 80 : 180),
            curve: Motion.ease,
            child: AnimatedOpacity(
              opacity: _down ? .88 : (widget.onTap == null && widget.dimWhenDisabled ? .4 : 1),
              duration: Motion.of(context, _down ? 80 : 140),
              child: widget.child,
            ),
          ),
        ),
      );
}

/// 44pt 圆形玻璃按钮（返回、更多、关闭等）。
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.icon, required this.onTap, required this.label, this.dark = false, this.size = 44, this.iconSize = 21, this.color});

  final String icon;
  final VoidCallback? onTap;
  final String label;
  final bool dark;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: Glass(
          radius: size / 2,
          dark: dark,
          child: SizedBox.square(
            dimension: size,
            child: Center(child: AppIcon(icon, size: iconSize, color: color ?? (dark ? IosColors.dInk : IosColors.ink), stroke: 1.8)),
          ),
        ),
      );
}

/// 大标题行：34pt 粗体，右侧放玻璃按钮。
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.x2, Space.page - 4, Space.x1),
        child: SizedBox(
          height: 54,
          child: Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -.4, color: IosColors.ink)),
              ),
            ),
            for (final t in trailing) ...[const SizedBox(width: Space.x2), t],
          ]),
        ),
      );
}

/// 柔和分段控件：整宽轨道 + 会滑动的选中块，没有分段之间的竖线和硬边。
///
/// 不用 `CupertinoSlidingSegmentedControl`：它的选中块是方角、分段之间有
/// 系统处理的分隔线，放在「人气排行」标题下显得很硬。这里选中块是圆角、
/// 220ms 滑动过去，只靠底色和字重区分。
class IosSegmented extends StatelessWidget {
  const IosSegmented({super.key, required this.options, required this.selected, required this.onChanged, this.dark = false, this.counts, this.compact = false});

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool dark;
  final List<int?>? counts;

  /// 紧凑版：高度 36、字号 13，用在区块标题右侧那种一行放得下的位置。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 36.0 : 40.0;
    final r = BorderRadius.circular(compact ? 11 : 12);
    return Container(
      height: h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: IosColors.faint, borderRadius: r),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / options.length;
          return Stack(
            children: [
              // 选中块只做位移。之前用 AnimatedPositioned 动 left + width，
              // 每帧都要重新排版；这里宽度是固定的 1/N，只平移，走的是合成。
              AnimatedSlide(
                duration: Motion.of(context, 200),
                curve: Motion.ease,
                offset: Offset(selected.toDouble(), 0),
                child: SizedBox(
                  width: w,
                  height: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: IosColors.surface,
                      borderRadius: BorderRadius.circular((compact ? 11 : 12) - 3),
                      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < options.length; i++)
                    Expanded(
                      child: Pressable(
                        haptic: true,
                        pressedScale: .98,
                        onTap: () {
                          if (i != selected) onChanged(i);
                        },
                        child: Center(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: options[i]),
                              if (counts != null && i < counts!.length && counts![i] != null)
                                TextSpan(text: '  ${counts![i]}', style: TextStyle(fontWeight: FontWeight.w400, color: IosColors.muted)),
                            ]),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: compact ? 13 : 14,
                              fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                              color: i == selected ? IosColors.ink : IosColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 反相开关：关是发丝轨 + 圆点，开是实心主文字色轨 + 反相圆点。
///
/// 不用 `CupertinoSwitch`：那个必须给一个色相当轨道色，而全 App 已经没有
/// 色相了；安卓用户看到 iOS 的开关也会觉得不是自己系统的件。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const _w = 50.0;
  static const _h = 31.0;
  static const _knob = 27.0;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        semanticLabel: value ? '已开启' : '已关闭',
        child: AnimatedContainer(
          duration: Motion.of(context, 200),
          curve: Motion.ease,
          width: _w,
          height: _h,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? IosColors.invert : IosColors.faint,
            borderRadius: BorderRadius.circular(_h / 2),
          ),
          child: AnimatedAlign(
            duration: Motion.of(context, 200),
            curve: Motion.ease,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _knob,
              height: _knob,
              decoration: BoxDecoration(
                color: value ? IosColors.onAccent : IosColors.surface,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))],
              ),
            ),
          ),
        ),
      );
}

/// 文字页签 + 选中项下方的短下划线，底部一条细分隔线。用于搜索范围和目录分组。
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.options, required this.selected, required this.onChanged, this.counts, this.padding = const EdgeInsets.symmetric(horizontal: 20)});

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final List<int?>? counts;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: IosColors.line, width: .5))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < options.length; i++)
                Pressable(
                  onTap: () {
                    if (i == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 14, right: 14),
                    child: SizedBox(
                      height: 48,
                      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: options[i]),
                            if (counts != null && counts![i] != null)
                              TextSpan(text: '  ${counts![i]}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: IosColors.muted)),
                          ]),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
                            color: i == selected ? IosColors.ink : IosColors.muted,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: i == selected ? 1 : 0,
                            child: Container(width: 22, height: 3, decoration: BoxDecoration(color: IosColors.accent, borderRadius: BorderRadius.circular(2))),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// 横向文字筛选：选中项为浅灰胶囊。
class TextChips extends StatelessWidget {
  const TextChips({super.key, required this.items, required this.selected, required this.onSelect});

  /// (标签, 计数, 是否带更新圆点)
  final List<(String, int?, bool)> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // 首尾用 [Space.page]，和标题、列表、网格落在同一条左边缘线，
          // 也保证划到尽头时最后一个胶囊距右边同样是 page。
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
          itemBuilder: (context, i) {
            final (label, count, dot) = items[i];
            final on = i == selected;
            return Pressable(
              haptic: true,
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: Motion.of(context, 180),
                curve: Motion.ease,
                // 胶囊左右各多 1px，页面有 4 的负向修正时也不会看起来偏。
                padding: const EdgeInsets.symmetric(horizontal: 13),
                // 选中靠字重 + 反相底，不靠色相（全 App 没有强调色）。
                decoration: BoxDecoration(color: on ? IosColors.faint : Colors.transparent, borderRadius: BorderRadius.circular(18)),
                child: Center(
                  widthFactor: 1,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (dot) ...[
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: IosColors.ink, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Text(label, style: TextStyle(fontSize: 15, color: on ? IosColors.ink : IosColors.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                    if (count != null) ...[
                      const SizedBox(width: 5),
                      Text('$count', style: TextStyle(fontSize: 13, color: on ? IosColors.ink : IosColors.muted)),
                    ],
                  ]),
                ),
              ),
            );
          },
        ),
      );
}

/// 区块标题：21pt 粗体 + 计数 + 右侧文字按钮。
class IosSection extends StatelessWidget {
  const IosSection(this.title, {super.key, this.count, this.action, this.onAction, this.actionIcon = 'right', this.note});

  final String title;
  final String? count;
  final String? action;
  final VoidCallback? onAction;
  final String actionIcon;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.beforeSection, Space.page - 4, Space.afterSection),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: IosColors.ink)),
          if (count != null) ...[
            const SizedBox(width: Space.x2),
            Text(count!, style: TextStyle(fontSize: 15, color: IosColors.muted)),
          ],
          const Spacer(),
          if (note != null) Text(note!, style: TextStyle(fontSize: 13, color: IosColors.muted)),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(action!, style: TextStyle(fontSize: 15, color: IosColors.muted)),
                  const SizedBox(width: 2),
                  AppIcon(actionIcon, size: 14, color: IosColors.muted, stroke: 2),
                ]),
              ),
            ),
        ]),
      );
}

/// 圆角分组列表（设置页）。
class InsetGroup extends StatelessWidget {
  const InsetGroup({super.key, this.title, required this.children, this.footer});

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            // 分组标题和卡片内容同一条 page 边线，不再用 36 那种「再缩进一层」
            // 的做法——那会让「偏好设置」和下面每一行都对不上。
            padding: const EdgeInsets.fromLTRB(Space.page + Space.x4, Space.beforeSection, Space.page, Space.x2),
            child: Text(title!, style: TextStyle(fontSize: 13, color: IosColors.muted)),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: Space.page),
          decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              // 有图标的行，分隔线从文字开始；没有图标时从行首的文字边距开始。
              if (i > 0) Padding(padding: EdgeInsets.only(left: children[i] is IosRow && (children[i] as IosRow).icon == null ? 16 : 52), child: Divider(height: 1, thickness: .5, color: IosColors.line)),
              children[i],
            ],
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page + Space.x4, Space.x2, Space.page + Space.x4, 0),
            child: Text(footer!, style: TextStyle(fontSize: 13, height: 1.45, color: IosColors.muted)),
          ),
      ]);
}

class IosRow extends StatelessWidget {
  const IosRow({super.key, this.icon, required this.title, this.subtitle, this.value, this.valueWidget, this.onTap, this.chevron = true, this.destructive = false});

  final String? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? valueWidget;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;

  /// 只展示信息、不能点的行（没有箭头也没有操作）照常显示，不按「不可用」变淡。
  bool get _informational => onTap == null && !chevron;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        dimWhenDisabled: !_informational,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              if (icon != null) ...[AppIcon(icon!, size: 22, color: IosColors.muted, stroke: 1.6), const SizedBox(width: 14)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: TextStyle(fontSize: 17, color: destructive ? IosColors.accent : IosColors.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              ?valueWidget,
              if (value != null) Text(value!, style: TextStyle(fontSize: 15, color: IosColors.muted)),
              if (chevron && onTap != null) ...[const SizedBox(width: 6), AppIcon('right', size: 14, color: IosColors.muted, stroke: 2)],
            ]),
          ),
        ),
      );
}

/// 「内容不可用」：图标、标题、说明和操作。
class Unavailable extends StatelessWidget {
  const Unavailable({super.key, required this.icon, required this.title, required this.message, this.actions = const [], this.dark = false, this.iconBackground});

  final String icon;
  final String title;
  final String message;
  final List<Widget> actions;
  final bool dark;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(18)),
            child: Center(child: AppIcon(icon, size: iconBackground == null ? 56 : 28, color: dark ? IosColors.dMuted : (iconBackground == null ? IosColors.muted : IosColors.accent), stroke: 1.3)),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: dark ? IosColors.dInk : IosColors.ink)),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.55, color: dark ? IosColors.dMuted : IosColors.muted)),
          if (actions.isNotEmpty) ...[const SizedBox(height: 22), Wrap(spacing: 14, runSpacing: 10, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: actions)],
        ]),
      );
}

/// 暖棕实心胶囊按钮（每屏唯一的主操作）。
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final String? icon;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          // 实心反相：浅色下黑底白字，深色下白底黑字。全 App 唯一的「主操作」。
          decoration: BoxDecoration(color: IosColors.invert, borderRadius: BorderRadius.circular(23)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: IosColors.onAccent)),
            if (icon != null) ...[const SizedBox(width: Space.x2), AppIcon(icon!, size: 18, color: IosColors.onAccent, stroke: 1.9)],
          ]),
        ),
      );
}

/// 纯文字操作。默认是次要色，只有明确传入 `primary: true` 才用主文字色。
class TextAction extends StatelessWidget {
  const TextAction({super.key, required this.label, required this.onTap, this.color, this.primary = false});

  final String label;
  final VoidCallback? onTap;

  /// 显式指定颜色（例如「清除」这种要用主文字色强调的）。
  final Color? color;

  /// 用主文字色 + 加粗，和 [color] 二选一。
  final bool primary;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              color: color ?? (primary ? IosColors.ink : IosColors.muted),
              fontWeight: primary || color != null ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
}

/// 加载中的占位块（redacted）。
class Redacted extends StatelessWidget {
  const Redacted({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(width: width, height: height, decoration: BoxDecoration(color: IosColors.faint, borderRadius: BorderRadius.circular(radius)));
}

/// 底部的轻提示（玻璃胶囊，1.6 秒后消失）。
void showIosToast(BuildContext context, String text, {bool dark = false}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 110,
      child: IgnorePointer(
        child: Center(
          child: _ToastBody(text: text, dark: dark, onDone: () => entry.remove()),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class _ToastBody extends StatefulWidget {
  const _ToastBody({required this.text, required this.dark, required this.onDone});

  final String text;
  final bool dark;
  final VoidCallback onDone;

  @override
  State<_ToastBody> createState() => _ToastBodyState();
}

class _ToastBodyState extends State<_ToastBody> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.ms(220), reverseDuration: Motion.ms(150));
  late final _in = CurvedAnimation(parent: _c, curve: Motion.ease, reverseCurve: Motion.exit.flipped);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed && !_shown) {
      _shown = true;
      if (Motion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _in,
        builder: (_, c) => Opacity(opacity: _in.value, child: Transform.translate(offset: Offset(0, 8 * (1 - _in.value)), child: c)),
        child: Glass(
          radius: 22,
          dark: widget.dark,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(widget.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: widget.dark ? IosColors.dInk : IosColors.ink, decoration: TextDecoration.none, fontWeight: FontWeight.w500)),
        ),
      );
}

/// 单行输入提示框。iOS 用 Cupertino 弹窗，安卓用 Material 弹窗——
/// 安卓上弹一个 iOS 的系统输入框是很明显的「不是我的系统」的割裂感。
Future<String?> showIosPrompt(BuildContext context, {required String title, String? message, String initial = '', String? placeholder, String confirm = '确定'}) {
  final input = TextEditingController(text: initial);
  final onAndroid = defaultTargetPlatform == TargetPlatform.android;
  final future = !onAndroid
      ? showCupertinoDialog<String>(
          context: context,
          builder: (dialog) => CupertinoAlertDialog(
            title: Text(title),
            content: Column(children: [
              if (message != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text(message)),
              CupertinoTextField(controller: input, placeholder: placeholder, autofocus: true, clearButtonMode: OverlayVisibilityMode.editing),
            ]),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(dialog), child: const Text('取消')),
              CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(dialog, input.text), child: Text(confirm)),
            ],
          ),
        )
      : showDialog<String>(
          context: context,
          builder: (dialog) => Theme(
            // 对话框也要吃全 App 的黑白主题，不能让 Material 默认的紫色飘进来。
            data: buildAppTheme().copyWith(platform: TargetPlatform.android),
            child: AlertDialog(
              backgroundColor: IosColors.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: IosColors.ink)),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (message != null) ...[
                  Text(message, style: TextStyle(fontSize: 14, height: 1.5, color: IosColors.muted)),
                  const SizedBox(height: Space.x3),
                ],
                TextField(
                  controller: input,
                  autofocus: true,
                  style: TextStyle(fontSize: 16, color: IosColors.ink),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: TextStyle(fontSize: 16, color: IosColors.muted),
                    filled: true,
                    fillColor: IosColors.faint,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ]),
              actionsPadding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialog), child: Text('取消', style: TextStyle(fontSize: 15, color: IosColors.muted))),
                TextButton(onPressed: () => Navigator.pop(dialog, input.text), child: Text(confirm, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.ink))),
              ],
            ),
          ),
        );
  return future.whenComplete(() => Future.delayed(const Duration(milliseconds: 400), input.dispose));
}

/// 选择表（操作表）。返回选中的下标，取消返回 null。
/// iOS 用系统操作表，安卓用底部面板 + 列表，两端都不弹对方的件。
Future<int?> showIosChoices(BuildContext context, {String? title, required List<String> options, int? selected, int? destructiveIndex}) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return showCupertinoModalPopup<int>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (var i = 0; i < options.length; i++)
            CupertinoActionSheetAction(
              isDestructiveAction: i == destructiveIndex,
              isDefaultAction: i == selected,
              onPressed: () => Navigator.pop(sheet, i),
              child: Text(i == selected ? '${options[i]}  ✓' : options[i]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(sheet), child: const Text('取消')),
      ),
    );
  }
  return showAppSheet<int>(
    context,
    (sheet) => Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.paddingOf(sheet).bottom + Space.x2),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x2),
                  child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                ),
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) Divider(height: .5, thickness: .5, color: IosColors.line),
                Pressable(
                  onTap: () => Navigator.pop(sheet, i),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                        color: i == destructiveIndex ? IosColors.ink : (i == selected ? IosColors.ink : IosColors.ink),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: Space.x2),
          Pressable(
            onTap: () => Navigator.pop(sheet),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
              child: Text('取消', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: IosColors.muted)),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// 确认对话框（两三个按钮）。iOS 用 Cupertino，安卓用 Material。
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = '确定',
  String cancel = '取消',
  bool destructive = false,
}) async {
  final onAndroid = defaultTargetPlatform == TargetPlatform.android;
  final r = !onAndroid
      ? await showCupertinoDialog<bool>(
          context: context,
          builder: (dialog) => CupertinoAlertDialog(
            title: Text(title),
            content: message == null ? null : Text(message),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(dialog, false), child: Text(cancel)),
              CupertinoDialogAction(
                isDefaultAction: !destructive,
                isDestructiveAction: destructive,
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(confirm),
              ),
            ],
          ),
        )
      : await showDialog<bool>(
          context: context,
          builder: (dialog) => Theme(
            data: buildAppTheme().copyWith(platform: TargetPlatform.android),
            child: AlertDialog(
              backgroundColor: IosColors.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: IosColors.ink)),
              content: message == null ? null : Text(message, style: TextStyle(fontSize: 14, height: 1.5, color: IosColors.muted)),
              actionsPadding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(cancel, style: TextStyle(fontSize: 15, color: IosColors.muted))),
                TextButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(confirm, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.ink)),
                ),
              ],
            ),
          ),
        );
  return r ?? false;
}
