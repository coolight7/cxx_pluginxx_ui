#pragma once

/// 客户端能力（能力段）与解析上限
///
/// 客户端**如实上报**自己能画什么：客户端的 `caps` 决定 `adapt()` 把描述降级成
/// 什么样（见 adapt.h）。库不写"if 终端"这类判断，只看能力。
///
/// 能力段的 JSON 形态（客户端发布通道各自实现，内容由本库生成）：
/// ```jsonc
/// {
///   "apiVersion": 1,
///   "kind": "gui",                        // tui / gui（只用于粗判断）
///   "blocks": ["Text", "Divider", "…"],   // 实际支持的块
///   "controls": ["buttons", "select", "…"],
///   "cell": { "width": 8, "height": 20 }, // 终端才有；GUI 省略（1u = 1 逻辑像素）
///   "gap": 12,                            // 本客户端的默认行距
///   "icons": ["play", "pause"],           // 可选：认识的图标名
///   "percent": true, "aspect": true,      // 尺寸形态支持
///   "limits": { … }
/// }
/// ```
#include "pluginxx/ui/gen/blocks.g.h"
#include "pluginxx/ui/item.h"

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace pluginxx {
namespace ui {

/// 每个字符格相当于多少 u（只有格子模型的客户端才有意义）
struct CellSize {
    double width  = gen::kDefaultCellWidth;
    double height = gen::kDefaultCellHeight;
};

/// 解析与渲染上限（**当前版本全部为 0 = 不限制**，保留结构只为能力段 JSON 兼容）
struct Limits {
    int         maxDepth         = 0;
    std::size_t maxItems         = 0;
    std::size_t maxTextBytes     = 0;
    std::size_t maxDocumentBytes = 0;
    std::size_t maxTableRows     = 0;
    int         maxTableColumns  = 0;
    std::size_t maxTreeNodes     = 0;
    std::size_t maxDataPoints    = 0;
};

/// 客户端能力
struct Capabilities {
    /// 组件词汇版本（客户端按自己的实现如实上报）
    int apiVersion = gen::kUiApiVersion;

    /// 渲染类型：tui / gui（只用于粗判断，例如"终端不给图片"；细判断一律用 blocks）
    std::string kind = "gui";

    /// 支持的组件（规范名；比较时忽略大小写）
    std::vector<std::string> blocks;
    /// 支持的控件形态
    std::vector<std::string> controls;
    /// 每个字符格相当于多少 u（终端上报自己的格大小；GUI 不使用）
    CellSize cell;
    /// 本客户端的默认行距（Gap.size 缺省时用它）
    double gap = gen::kDefaultGap;
    /// 认识的图标名（可选；插件据此选择 Icon.name）
    std::vector<std::string> icons;
    /// 是否支持 percent 尺寸
    bool percent = true;
    /// 是否支持 aspect（纵横比）
    bool aspect = true;
    /// 上限
    Limits limits;

    bool supportsBlock(std::string_view name) const;
    bool supportsControl(std::string_view name) const;
    bool supportsIcon(std::string_view name) const;

    /// 横向 u → 列数（四舍五入；`atLeastOne` 表示正数至少占 1 格）
    int colsOf(double u, bool atLeastOne = false) const;
    /// 纵向 u → 行数（四舍五入；`atLeastOne` 表示正数至少占 1 格）
    int rowsOf(double u, bool atLeastOne = false) const;

    /// 全部组件与控件都支持（GUI 客户端的默认能力）
    static Capabilities full();
    /// 最小实现：只有 Text（适配的收敛终点）
    static Capabilities minimal();
};

inline bool Capabilities::supportsBlock(const std::string_view name) const {
    for (const std::string& v : blocks) {
        if (detail::iequals(v, name)) {
            return true;
        }
    }
    return false;
}

inline bool Capabilities::supportsControl(const std::string_view name) const {
    for (const std::string& v : controls) {
        if (detail::iequals(v, name)) {
            return true;
        }
    }
    return false;
}

inline bool Capabilities::supportsIcon(const std::string_view name) const {
    return std::any_of(icons.begin(), icons.end(), [name](const std::string& v) {
        return v == name;
    });
}

inline int Capabilities::colsOf(const double u, const bool atLeastOne) const {
    const double unit = cell.width > 0.0 ? cell.width : gen::kDefaultCellWidth;
    const double raw  = u / unit;
    const int    n    = static_cast<int>(raw + 0.5);
    if (atLeastOne && u > 0.0 && n < 1) {
        return 1;
    }
    return n < 0 ? 0 : n;
}

inline int Capabilities::rowsOf(const double u, const bool atLeastOne) const {
    const double unit = cell.height > 0.0 ? cell.height : gen::kDefaultCellHeight;
    const double raw  = u / unit;
    const int    n    = static_cast<int>(raw + 0.5);
    if (atLeastOne && u > 0.0 && n < 1) {
        return 1;
    }
    return n < 0 ? 0 : n;
}

} // namespace ui
} // namespace pluginxx
