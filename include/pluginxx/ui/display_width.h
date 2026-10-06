#pragma once

/// 显示列宽的计算规则（终端渲染与文本降级共用）
///
/// - CJK 与全角符号按 2 列，其余按 1 列；
/// - 组合字符、变体选择符、零宽连接符按 0 列；
/// - 非法 UTF-8 字节按 1 列跳过（不抛异常）。
#include "pluginxx/ui/export.h"

#include <string>
#include <string_view>

namespace pluginxx {
namespace ui {

/// 文本占多少显示列
PLUGINXX_UI_API int displayWidth(std::string_view text);

/// 按显示列宽截断（宽字符安全：不会留下只占一半的宽字符）
/// - 未超宽时原样返回；超宽时保留前若干列并追加省略号（省略号自身宽度也计入）
/// - `ellipsis` 传空串表示直接截断、不追加标记
PLUGINXX_UI_API std::string
    truncateToWidth(std::string_view text, int maxWidth, std::string_view ellipsis = "…");

/// 按显示列宽在右侧补空格（已超宽时原样返回，由调用方自行截断）
PLUGINXX_UI_API std::string padRightToWidth(std::string_view text, int width);

/// 从文本头部取出不超过 `maxWidth` 列的完整前缀（宽字符安全）
/// - `usedWidth` 返回实际占用的显示列宽（<= maxWidth；可为 0）
PLUGINXX_UI_API std::string_view prefixByWidth(std::string_view text, int maxWidth, int& usedWidth);

} // namespace ui
} // namespace pluginxx
