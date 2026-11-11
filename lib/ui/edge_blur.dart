import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show ProgressiveBlur, ProgressiveBlurDirection;

/// 模糊贴在哪条边上。
enum EdgeBlurSide { top, bottom }

/// 边栏材质的渐进模糊：越靠边越糊，离开边缘逐渐回到完全清楚。
///
/// 对应 iOS 26 的 scroll edge effect（UIKit 是 `UIScrollView.topEdgeEffect`，
/// SwiftUI 是 `scrollEdgeEffectStyle(_:for:)` 的 `.soft`）：滚动内容经过控制条
/// 时，既不是被一条硬边切断（`.hard`），也不是整块均匀糊掉，而是从清楚平滑
/// 过渡到近乎不透明。
///
/// ## 分两段，不是一个渐变
///
/// 以前一个 [ProgressiveBlur] 铺满整条带子、底色也线性铺满整条，问题出在
/// **带子多长由遮挡物决定**：顶部只有状态栏（38），底部是整个标签栏（152），
/// 于是同一套参数在两处画出完全不同的过渡——顶部刚糊开就到头，底部拖着一大条
/// 尾巴。用户看到的就是「上面太短、下面太长」。
///
/// 现在拆成两段，只有第二段是真正看得出来在过渡的：
/// - [covered]：被栏体遮住的那段，**均匀模糊 + 实底色**。这一段多长由屏幕
///   结构决定（顶部=状态栏，底部=标签栏+手势区），它本来就被压在下面，
///   长一点短一点不影响观感。
/// - [tail]：栏外那段，**渐进模糊 + 底色渐隐**。这一段两端可以、也必须
///   取同一个值——眼睛看到的「过渡有多长」就是它。
///
/// 底部带子仍然比顶部高得多，但多出来的部分全在标签栏胶囊底下，视觉上
/// 两边的过渡长度是相等的。
class EdgeBlur extends StatelessWidget {
  const EdgeBlur({
    super.key,
    required this.covered,
    required this.tail,
    this.sigma = 16,
    this.side = EdgeBlurSide.top,
    this.tint,
    this.tintAlpha = .7,
  });

  /// 被栏体遮住的长度（逻辑像素）。这段均匀模糊、底色不透明。
  final double covered;

  /// 栏外的过渡长度。这段从全糊渐到完全清楚。
  final double tail;

  /// 边缘处的模糊强度（sigma）。
  final double sigma;

  final EdgeBlurSide side;

  /// 压在模糊上面的底色。给 null 就只模糊、不染色。
  final Color? tint;

  /// 底色在遮挡区的不透明度，过渡段里线性降到 0。
  final double tintAlpha;

  double get height => covered + tail;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    final bottom = side == EdgeBlurSide.bottom;
    final ink = tint;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // 遮挡区：均匀模糊。内容本来就是被压在栏体下面的，不该在这里
            // 还留一段"逐渐变清楚"——那样栏体边缘会透出一条清楚的窄带。
            if (covered > 0)
              Positioned(
                left: 0,
                right: 0,
                top: bottom ? null : 0,
                bottom: bottom ? 0 : null,
                height: covered,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: ink == null ? const SizedBox.expand() : ColoredBox(color: ink.withValues(alpha: tintAlpha)),
                  ),
                ),
              ),
            // 过渡段：栏体之外，从全糊渐到清楚。
            if (tail > 0)
              Positioned(
                left: 0,
                right: 0,
                top: bottom ? null : covered,
                bottom: bottom ? covered : null,
                height: tail,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ProgressiveBlur(
                        maxSigma: sigma,
                        direction: bottom ? ProgressiveBlurDirection.bottomToTop : ProgressiveBlurDirection.topToBottom,
                      ),
                    ),
                    if (ink != null)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: bottom ? Alignment.bottomCenter : Alignment.topCenter,
                              end: bottom ? Alignment.topCenter : Alignment.bottomCenter,
                              // 从遮挡区的 tintAlpha 接着往下淡，接缝处没有台阶。
                              colors: [ink.withValues(alpha: tintAlpha), ink.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
