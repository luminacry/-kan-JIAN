import 'package:flutter/widgets.dart';

/// 全局间距刻度。
///
/// 之前每个页面各写各的 `EdgeInsets`，左边距在 16 / 20 / 36 之间跳，
/// 区块上下留白在 6 / 10 / 12 / 22 / 26 之间随机，滚动到底部时又会突然
/// 撞上一大块空白——看上去就是「没有视觉居中」。这里只留一档刻度，
/// 页面只用 [page] 作为唯一外边距，纵向节奏只用下面几个命名值。
class Space {
  Space._();

  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 28.0;
  static const x7 = 36.0;

  /// 全 App 唯一的页面左右外边距。标题、筛选、列表、网格左边缘都落在这一条线。
  static const page = x5;

  /// 大标题下沿到第一个内容块。
  static const afterTitle = x2;

  /// 区块标题的上沿留白（上一个区块的内容到此结束）。
  static const beforeSection = x6;

  /// 区块标题下沿到内容。
  static const afterSection = x3;

  /// 列表中每一行与上一行的最小间隔，也是相邻卡片的间隔。
  static const rowGap = x3;
}

/// 悬浮标签栏的几何。
///
/// 关键点：标签栏必须整体抬到系统手势区（安卓小白条 / iOS Home 指示条）
/// 之上，不能像以前那样 `bottom: inset - 6` 直接压进去——那样手势条会盖住
/// 胶囊底部和「搜索」球。
class Dock {
  Dock._();

  static const height = 64.0;

  /// 胶囊与手势条之间留的距离。
  static const gap = Space.x2;

  /// 系统手势区高度。
  static double inset(BuildContext context) => MediaQuery.paddingOf(context).bottom;

  /// 标签栏底边距屏幕底边的距离。
  static double bottom(BuildContext context) => inset(context) + gap;

  /// 页面内容需要给标签栏让出的高度：标签栏 + 它下面的留白 + 一点呼吸空间。
  static double clearance(BuildContext context) => height + bottom(context) + Space.x4;
}

/// 边栏渐进模糊带的几何。
///
/// 一条规则管两端：**被遮挡的部分 + 同一段柔和过渡**。
///
/// 被遮挡的部分各算各的——顶部只有状态栏，底部是「标签栏 + 它下面的手势区」，
/// 这是屏幕结构决定的，不能强行对齐。真正需要统一的是**过渡段**：不管上面
/// 压着什么，糊到完全清楚都走同一个 [tail]。
///
/// 以前两边各写各的（顶 `+14`、底 `+40`），顶部 38、底部 152，比例 1:4：
/// 顶部刚糊开就到头了，底部却拖着一条 56dp 的尾巴，糊得漫无目的。
class ScrollEdge {
  ScrollEdge._();

  /// 遮挡区之外再柔和过渡多高。两端共用这一个值。
  ///
  /// 28 的依据：它要够长到肉眼能看出「渐次变清楚」而不是一条硬边（<20 会
  /// 读成硬切），又不能长到把内容整块吃掉（>40 时一屏里就没剩多少清楚的地方）。
  static const tail = 28.0;

  /// 顶部被遮住的长度：状态栏本身。
  ///
  /// 顶部没有常驻栏，大标题是跟着列表滚走的，所以遮挡区只有状态栏。
  static double topCovered(BuildContext context) => MediaQuery.paddingOf(context).top;

  /// 底部被遮住的长度：标签栏 + 它下面的留白。
  ///
  /// 用 [Dock.bottom] 而不是整个 [Dock.clearance]：后者还含着给页面留的
  /// 呼吸空间，那是排版用的，不属于被栏体挡住的部分。
  static double bottomCovered(BuildContext context) => Dock.bottom(context) + Dock.height;
}
