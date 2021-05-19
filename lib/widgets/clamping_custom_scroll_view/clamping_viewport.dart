// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ClampingViewport extends Viewport {
  ClampingViewport({
    Key? key,
    AxisDirection axisDirection = AxisDirection.down,
    AxisDirection? crossAxisDirection,
    double anchor = 0.0,
    required ViewportOffset offset,
    Key? center,
    double? cacheExtent,
    List<Widget> slivers = const <Widget>[],
  })  : _anchor = anchor,
        super(
          key: key,
          axisDirection: axisDirection,
          crossAxisDirection: crossAxisDirection,
          offset: offset,
          center: center,
          cacheExtent: cacheExtent,
          slivers: slivers,
        );

  final double _anchor;

  @override
  double get anchor => _anchor;

  @override
  RenderViewport createRenderObject(BuildContext context) =>
      ClampingRenderViewport(
        axisDirection: axisDirection,
        crossAxisDirection: crossAxisDirection ??
            Viewport.getDefaultCrossAxisDirection(context, axisDirection),
        anchor: anchor,
        offset: offset,
        cacheExtent: cacheExtent,
      );
}

// Differences from [RenderViewport] are marked with a //***** Differences
// comment.
class ClampingRenderViewport extends RenderViewport {
  /// Creates a viewport for [RenderSliver] objects.
  ClampingRenderViewport({
    AxisDirection axisDirection = AxisDirection.down,
    required AxisDirection crossAxisDirection,
    required ViewportOffset offset,
    double anchor = 0.0,
    List<RenderSliver>? children,
    RenderSliver? center,
    double? cacheExtent,
  })  : _anchor = anchor,
        super(
            axisDirection: axisDirection,
            crossAxisDirection: crossAxisDirection,
            offset: offset,
            center: center,
            cacheExtent: cacheExtent,
            children: children);

  static const int _maxLayoutCycles = 10;

  double _anchor;

  // Out-of-band data computed during layout.
  late double _minScrollExtent;
  late double _maxScrollExtent;
  bool _hasVisualOverflow = false;

  /// This value is set during layout based on the [CacheExtentStyle].
  ///
  /// When the style is [CacheExtentStyle.viewport], it is the main axis extent
  /// of the viewport multiplied by the requested cache extent, which is still
  /// expressed in pixels.
  double? _calculatedCacheExtent;

  @override
  double get anchor => _anchor;

  // *** Difference from [RenderViewport].
  double correctedOffset = 0.0;
  bool isLessMainAxisExtent = false;

  // *** End of difference from [RenderViewport].

  @override
  set anchor(double value) {
    if (value == _anchor) return;
    _anchor = value;
    markNeedsLayout();
  }

  @override
  void performResize() {
    super.performResize();
    // TODO: Figure out why this override is needed as a result of
    // https://github.com/flutter/flutter/pull/61973 and see if it can be
    // removed somehow.
    switch (axis) {
      case Axis.vertical:
        offset.applyViewportDimension(size.height);
        break;
      case Axis.horizontal:
        offset.applyViewportDimension(size.width);
        break;
    }
  }

  @override
  Rect describeSemanticsClip(RenderSliver child) {
    if (_calculatedCacheExtent == null) {
      return semanticBounds;
    }

    switch (axis) {
      case Axis.vertical:
        return Rect.fromLTRB(
          semanticBounds.left,
          semanticBounds.top - _calculatedCacheExtent!,
          semanticBounds.right,
          semanticBounds.bottom + _calculatedCacheExtent!,
        );
      default:
        return Rect.fromLTRB(
          semanticBounds.left - _calculatedCacheExtent!,
          semanticBounds.top,
          semanticBounds.right + _calculatedCacheExtent!,
          semanticBounds.bottom,
        );
    }
  }

  @override
  void performLayout() {
    if (center == null) {
      assert(firstChild == null);
      _minScrollExtent = 0.0;
      _maxScrollExtent = 0.0;
      _hasVisualOverflow = false;
      offset.applyContentDimensions(0.0, 0.0);
      return;
    }
    assert(center!.parent == this);

    double mainAxisExtent;
    double crossAxisExtent;
    switch (axis) {
      case Axis.vertical:
        mainAxisExtent = size.height;
        crossAxisExtent = size.width;
        break;
      case Axis.horizontal:
        mainAxisExtent = size.width;
        crossAxisExtent = size.height;
        break;
    }

    final centerOffsetAdjustment = center!.centerOffsetAdjustment;

    double correction;
    var count = 0;
    do {
      // *** Difference from [RenderViewport].
      correction = _attemptLayout(mainAxisExtent, crossAxisExtent,
          offset.pixels + centerOffsetAdjustment + correctedOffset);
      // *** End of difference from [RenderViewport].
      if (correction != 0.0) {
        offset.correctBy(correction);
      } else {
        // *** Difference from [RenderViewport].
        final scrollExtent = _maxScrollExtent - _minScrollExtent;
        if (!isLessMainAxisExtent && scrollExtent < mainAxisExtent) {
          isLessMainAxisExtent = true;
          correctedOffset = (mainAxisExtent * anchor) + _minScrollExtent;
          continue;
        }

        final top =
            _minScrollExtent + mainAxisExtent * anchor - correctedOffset;
        final bottom = _maxScrollExtent -
            mainAxisExtent * (1.0 - anchor) -
            correctedOffset;
        final maxScrollOffset = math.max(math.min(0.0, top), bottom);
        final minScrollOffset = math.min(top, maxScrollOffset);

        final centerScrollExtent = center!.geometry!.scrollExtent *
            (correctedOffset.isNegative ? -1 : 1);
        final clampScrollExtent = centerScrollExtent.clamp(
          math.min(minScrollOffset, maxScrollOffset),
          math.max(minScrollOffset, maxScrollOffset),
        );
        if (!isLessMainAxisExtent &&
            clampScrollExtent != centerScrollExtent &&
            count < 1) {
          correctedOffset = clampScrollExtent.toDouble();
          count += 1;
          continue;
        }
        if (offset.applyContentDimensions(minScrollOffset, maxScrollOffset)) {
          break;
        }
        // *** End of difference from [RenderViewport].
      }
      count += 1;
    } while (count < _maxLayoutCycles);
    assert(() {
      if (count >= _maxLayoutCycles) {
        assert(count != 1);
        throw FlutterError(
            'A RenderViewport exceeded its maximum number of layout cycles.\n'
            'RenderViewport render objects, during layout, can retry if either their '
            'slivers or their ViewportOffset decide that the offset should be corrected '
            'to take into account information collected during that layout.\n'
            'In the case of this RenderViewport object, however, this happened $count '
            'times and still there was no consensus on the scroll offset. This usually '
            'indicates a bug. Specifically, it means that one of the following three '
            'problems is being experienced by the RenderViewport object:\n'
            ' * One of the RenderSliver children or the ViewportOffset have a bug such'
            ' that they always think that they need to correct the offset regardless.\n'
            ' * Some combination of the RenderSliver children and the ViewportOffset'
            ' have a bad interaction such that one applies a correction then another'
            ' applies a reverse correction, leading to an infinite loop of corrections.\n'
            ' * There is a pathological case that would eventually resolve, but it is'
            ' so complicated that it cannot be resolved in any reasonable number of'
            ' layout passes.');
      }
      return true;
    }());
  }

  double _attemptLayout(
      double mainAxisExtent, double crossAxisExtent, double correctedOffset) {
    assert(!mainAxisExtent.isNaN);
    assert(mainAxisExtent >= 0.0);
    assert(crossAxisExtent.isFinite);
    assert(crossAxisExtent >= 0.0);
    assert(correctedOffset.isFinite);
    _minScrollExtent = 0.0;
    _maxScrollExtent = 0.0;
    _hasVisualOverflow = false;

    // centerOffset is the offset from the leading edge of the RenderViewport
    // to the zero scroll offset (the line between the forward slivers and the
    // reverse slivers).
    final centerOffset = mainAxisExtent * anchor - correctedOffset;
    final reverseDirectionRemainingPaintExtent =
        centerOffset.clamp(0.0, mainAxisExtent);
    final forwardDirectionRemainingPaintExtent =
        (mainAxisExtent - centerOffset).clamp(0.0, mainAxisExtent);

    switch (cacheExtentStyle) {
      case CacheExtentStyle.pixel:
        _calculatedCacheExtent = cacheExtent;
        break;
      case CacheExtentStyle.viewport:
        _calculatedCacheExtent = mainAxisExtent * cacheExtent!;
        break;
    }

    final fullCacheExtent = mainAxisExtent + 2 * _calculatedCacheExtent!;
    final centerCacheOffset = centerOffset + _calculatedCacheExtent!;
    final reverseDirectionRemainingCacheExtent =
        centerCacheOffset.clamp(0.0, fullCacheExtent);
    final forwardDirectionRemainingCacheExtent =
        (fullCacheExtent - centerCacheOffset).clamp(0.0, fullCacheExtent);

    final leadingNegativeChild = childBefore(center!);

    if (leadingNegativeChild != null) {
      // negative scroll offsets
      final result = layoutChildSequence(
        child: leadingNegativeChild,
        scrollOffset: math.max(mainAxisExtent, centerOffset) - mainAxisExtent,
        overlap: 0.0,
        layoutOffset: forwardDirectionRemainingPaintExtent,
        remainingPaintExtent: reverseDirectionRemainingPaintExtent,
        mainAxisExtent: mainAxisExtent,
        crossAxisExtent: crossAxisExtent,
        growthDirection: GrowthDirection.reverse,
        advance: childBefore,
        remainingCacheExtent: reverseDirectionRemainingCacheExtent,
        cacheOrigin: (mainAxisExtent - centerOffset)
            .clamp(-_calculatedCacheExtent!, 0.0),
      );
      if (result != 0.0) return -result;
    }

    // positive scroll offsets
    return layoutChildSequence(
      child: center,
      scrollOffset: math.max(0.0, -centerOffset),
      overlap:
          leadingNegativeChild == null ? math.min(0.0, -centerOffset) : 0.0,
      layoutOffset: centerOffset >= mainAxisExtent
          ? centerOffset
          : reverseDirectionRemainingPaintExtent,
      remainingPaintExtent: forwardDirectionRemainingPaintExtent,
      mainAxisExtent: mainAxisExtent,
      crossAxisExtent: crossAxisExtent,
      growthDirection: GrowthDirection.forward,
      advance: childAfter,
      remainingCacheExtent: forwardDirectionRemainingCacheExtent,
      cacheOrigin: centerOffset.clamp(-_calculatedCacheExtent!, 0.0),
    );
  }

  @override
  bool get hasVisualOverflow => _hasVisualOverflow;

  @override
  void updateOutOfBandData(
      GrowthDirection growthDirection, SliverGeometry childLayoutGeometry) {
    switch (growthDirection) {
      case GrowthDirection.forward:
        _maxScrollExtent += childLayoutGeometry.scrollExtent;
        break;
      case GrowthDirection.reverse:
        _minScrollExtent -= childLayoutGeometry.scrollExtent;
        break;
    }
    if (childLayoutGeometry.hasVisualOverflow) _hasVisualOverflow = true;
  }

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (parent is RenderObject) {
      (parent! as RenderObject).showOnScreen(
        descendant: descendant ?? this,
        rect: rect,
        duration: duration,
        curve: curve,
      );
    }
  }
}
