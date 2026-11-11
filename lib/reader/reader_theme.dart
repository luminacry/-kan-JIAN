import 'package:flutter/widgets.dart';

import '../ios/ios_theme.dart';

/// 阅读器专用色板与尺寸令牌。
///
/// **中性色**：和 [IosColors] 同一套黑白灰，没有色相。以前这里是「灰蓝」，
/// 而主界面是「暖棕」，两个界面并能看出两套主题色在打架；现在「选中」
/// 只靠描边、反相和字重表达，不靠颜色。
///
/// 两条规则：
/// - **文字控件反相**（胶囊、按钮）：选中就是实心主文字色 + 底色文字，
///   对比最强，也最容易一眼看出选了哪个。
/// - **图标控件描边**（阅读方式瓦片）：图标本身有层次，反相会把它压平，
///   所以改成浅底 + 1.5px 主文字色描边 + 对勾。
///
/// 因为要跟着主题切换，这些是 getter 不是 const，调用处也就不能写 `const`。
class ReaderPalette {
  ReaderPalette._();

  static bool get _dark => IosColors.isDark;

  // ── 底层 ──

  /// 阅读页背板（图片周边）。
  ///
  /// 深色下是纯黑而不是 `#101113`：整页适应时页面上下会各留一条 letterbox
  /// （比例差一点点就有一百来像素）。深灰 + 状态栏图标压在上面，读起来像
  /// 「内容没铺满」；纯黑把这两条变成有意为之的黑框，图标也融进去。
  static Color get reader => _dark ? const Color(0xFF000000) : const Color(0xFFEFEFF1);

  /// 设置面板、顶部栏、底部栏。
  static Color get sheet => _dark ? const Color(0xFF1B1C1F) : const Color(0xFFFFFFFF);

  /// 漫画纸面底色（图片还没到位时露出来的那层）。
  static Color get page => _dark ? const Color(0xFFFAFAFA) : const Color(0xFFFFFFFF);

  // ── 文字两级 ──
  static Color get text => _dark ? const Color(0xFFF2F2F4) : const Color(0xFF1A1B1F);
  static Color get muted => _dark ? const Color(0xFF9A9BA3) : const Color(0xFF71727A);

  // ── 控件表面 ──

  /// 瓦片、胶囊的未选中底。
  static Color get surface => _dark ? const Color(0xFF26272B) : const Color(0xFFF1F1F3);

  /// 发丝线与默认描边。
  static Color get border => _dark ? const Color(0xFF33343A) : const Color(0xFFE2E2E6);

  // ── 选中态（图标控件用描边，文字控件用反相）──

  /// 选中瓦片的底色：比 surface 高一档，配 [_selectedLine] 描边。
  static Color get selected => _dark ? const Color(0xFF33343A) : const Color(0xFFFFFFFF);

  /// 选中瓦片上的文字。
  static Color get selectedInk => text;

  /// 选中描边：主文字色，1.5px。
  static Color get selectedLine => text;

  // ── 反相块（文字控件的选中态、主按钮）──

  /// 反相底：浅色下是近黑，深色下是近白。
  static Color get invert => text;

  /// 反相块上的文字。
  static Color get onInvert => _dark ? const Color(0xFF17181C) : const Color(0xFFFFFFFF);

  // ── 主按钮 ──

  /// 「完成」按钮：实心反相。
  static Color get button => invert;
  static Color get buttonInk => onInvert;
  static Color get buttonHover => _dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  // ── 滑块 ──
  static Color get track => _dark ? const Color(0xFF35363B) : const Color(0xFFE4E4E8);
  static Color get tick => _dark ? const Color(0xFF6E6F77) : const Color(0xFFB3B4BB);

  /// 滑块已选段与手柄：主文字色。
  static Color get accent => text;
  static Color get thumb => text;

  /// 面板顶部的拖拽把手。
  static Color get grip => _dark ? const Color(0xFF55565E) : const Color(0xFFC6C7CD);

  /// 面板后面压暗画面的遮罩。压得很轻——面板背后要能看见当前页，
  /// 压重了就成了「点进去一片灰」。
  static Color get scrim => const Color(0x14000000);

  // ── 多色图标：纸页三层次（灰阶）──

  /// 前一张纸（压在后面的那张）。
  static Color get iconBack => _dark ? const Color(0xFF5C5D64) : const Color(0xFFC9C9CF);

  /// 正面的纸。
  static Color get iconPaper => _dark ? const Color(0xFF8C8D95) : const Color(0xFFE8E8EC);

  /// 卷角。
  static Color get iconTab => _dark ? const Color(0xFF71727A) : const Color(0xFFD8D8DE);

  /// 纸上的线和箭头。
  static Color get iconInk => _dark ? const Color(0xFF1A1B1F) : const Color(0xFF4A4B53);

  static Color get iconSelectedPaper => _dark ? const Color(0xFFD6D7DC) : const Color(0xFFF7F7F9);
  static Color get iconSelectedBack => _dark ? const Color(0xFF7C7D85) : const Color(0xFFD2D2D8);
  static Color get iconSelectedTab => _dark ? const Color(0xFFA8A9B0) : const Color(0xFFE2E2E7);
  static Color get iconSelectedInk => _dark ? const Color(0xFF17181C) : const Color(0xFF26272C);

  // ── 尺寸（两端一致）──

  /// 阅读方式瓦片：一个只有图标的方块，名字挂在下面。
  static const tile = 66.0;
  static const tileRadius = 16.0;
  static const tileGlyph = 30.0;
  static const tileGap = 6.0;
  static const tileStripGap = 9.0;
  static const tileLabel = 12.0;

  /// 选中描边宽度。图标控件靠它区分，所以要比发丝线明显。
  static const selectedStroke = 1.5;

  /// 胶囊。
  static const choiceHeight = 44.0;
  static const choiceRadius = 13.0;

  /// 顶部提示面板圆角。
  static const sheetRadius = 27.0;

  /// 完成按钮。
  static const buttonRadius = 15.0;

  /// 滑块轨道与手柄。
  static const trackHeight = 4.0;
  static const thumbSize = 16.0;
  static const tickSize = 3.0;
}
