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
/// **只有顶部有全宽模糊带**，底部没有。
///
/// 参照的那个 App（书库界面）逐像素量过：底部白色胶囊只占距底 36–92dp，
/// 胶囊**外侧**的封面、作者名一直到屏幕底边都是清楚的；被糊掉的「你的故事」
/// 是因为它正好在胶囊玻璃下面，不是有一条全宽渐隐。全宽模糊带压在标签栏
/// 上方，只会平白吃掉一行内容——那正是「下面很长、没必要这么做」。
///
/// 顶部则确实有一条：状态栏那 24dp 里内容一直是糊的，往下糊到状态栏下沿
/// 就断了。参考图里正文从 68dp 开始就是清晰的，所以带子不能探进内容区。
class ScrollEdge {
  ScrollEdge._();

  /// 顶部带高：正好到状态栏下沿，不再往外多铺。
  ///
  /// 之前会给状态栏高度再加一个 28dp 的过渡段，结果压住了「书架」「发现」
  /// 这两个大标题——标题就在状态栏正下方，多出来的每一像素都是拿内容换的。
  ///
  /// 带子内部由 [EdgeBlur] 自己从边缘渐到清楚，所以"到状态栏下沿为止"
  /// 已经包含了那条过渡，不需要再额外留长度。
  static double topCovered(BuildContext context) => MediaQuery.paddingOf(context).top;
}
