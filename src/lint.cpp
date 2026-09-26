// 开发期检查（不改变描述、不参与渲染）
#include "pluginxx/ui/lint.h"

#include <cstddef>
#include <string>
#include <vector>

namespace pluginxx {
namespace ui {

namespace {

/// 尺寸是否是格的整数倍（终端按格取整时不会吃掉或挤开布局）
void checkCellMultiple(const SizeValue& size, const Capabilities& caps, const std::string& path,
                       const std::string& what, std::vector<LintNote>& out) {
    if (caps.kind != "tui" || !size.isValue() || size.value <= 0.0) {
        return;
    }
    const double cell    = caps.cell.width > 0.0 ? caps.cell.width : gen::kDefaultCellWidth;
    const double ratio   = size.value / cell;
    const double rounded = static_cast<double>(static_cast<int>(ratio + 0.5));
    if (ratio - rounded > 0.001 || rounded - ratio > 0.001) {
        out.push_back(LintNote{
            "",
            path,
            what + " 的 " + detail::formatNumber(size.value) +
                "u 不是格的整数倍，终端会取整（每格 " + detail::formatNumber(cell) + "u）",
        });
    }
}

} // namespace

std::vector<LintNote> lintItem(const Item& item, const Capabilities& caps, std::string path) {
    std::vector<LintNote> out;
    if (path.empty()) {
        path = item.kind.empty() ? "?" : item.kind;
    }

    // u 值是否与格对齐
    checkCellMultiple(item.size, caps, path, item.kind + ".size", out);
    checkCellMultiple(item.width, caps, path, item.kind + ".width", out);
    checkCellMultiple(item.height, caps, path, item.kind + ".height", out);
    checkCellMultiple(item.gap, caps, path, item.kind + ".gap", out);

    // 固定宽度 + flex 混用（固定宽会把 flex 挤成 0）
    if (item.kind == "Row" || item.kind == "Column") {
        bool hasFixed = false;
        bool hasFlex  = false;
        for (const Item& child : item.children) {
            if (child.kind == "Expanded" || child.kind == "Spacer") {
                hasFlex = true;
            }
            if (child.kind == "SizedBox" &&
                ((item.kind == "Row" && child.width.isValue()) ||
                 (item.kind == "Column" && child.height.isValue()))) {
                hasFixed = true;
            }
        }
        if (hasFixed && hasFlex) {
            out.push_back(LintNote{
                item.kind,
                path,
                "同一行/列里既有固定尺寸又有 Expanded/Spacer，固定尺寸可能把 flex 挤成 0",
            });
        }
    }

    // percent 落在高度无界的容器里（会退化成内容尺寸）
    if (caps.percent && item.height.isPercent() &&
        (item.kind == "Column" || item.kind == "Block" || item.kind == "Padding" ||
         item.kind == "Align")) {
        out.push_back(LintNote{
            item.kind,
            path,
            "`height: percent` 落在自动高度的容器里，父容器高度无界时会退化成内容尺寸",
        });
    }

    // 文本块同时给 wrap: false 与 maxLines（互相抵消）
    if (item.kind == "Text" && !item.wrap && item.maxLines > 0) {
        out.push_back(LintNote{
            item.kind,
            path,
            "同时给了 `wrap: false` 与 `maxLines`，两者互相抵消（不折行时 maxLines 没有意义）",
        });
    }

    // 表格列宽合计明显超出可用宽度（固定列宽之和 > 100 列时提示）
    if (item.kind == "Table" && caps.kind == "tui") {
        double fixed = 0.0;
        for (const TableColumn& column : item.columns) {
            if (column.width.isValue()) {
                fixed += column.width.value;
            }
        }
        if (fixed > 0.0 && fixed > caps.cell.width * 100.0) {
            out.push_back(LintNote{
                item.kind,
                path,
                "固定列宽合计 " + detail::formatNumber(fixed) + "u 明显超出常规终端宽度，建议省略列宽",
            });
        }
    }

    for (std::size_t i = 0; i < item.children.size(); ++i) {
        std::vector<LintNote> childNotes = lintItem(
            item.children[i], caps, path + ".children[" + std::to_string(i) + "]"
        );
        out.insert(out.end(), childNotes.begin(), childNotes.end());
    }
    return out;
}

std::vector<LintNote> lintWithCaps(const std::vector<Item>& items, const Capabilities& caps) {
    std::vector<LintNote> out;
    for (std::size_t i = 0; i < items.size(); ++i) {
        std::vector<LintNote> notes =
            lintItem(items[i], caps, "blocks[" + std::to_string(i) + "]");
        out.insert(out.end(), notes.begin(), notes.end());
    }
    return out;
}

} // namespace ui
} // namespace pluginxx
