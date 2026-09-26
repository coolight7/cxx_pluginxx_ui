// 纯文本降级（日志 / CLI / 适配时的"退成文本"）
//
// 输出格式与 Dart 绑定逐字节一致（测试用 fixtures/schema_samples.json 对比）：
// 不使用任何语言相关文案，数值一律走 detail::formatNumber。
#include "pluginxx/ui/plain_text.h"

#include "pluginxx/ui/display_width.h"
#include "pluginxx/ui/parse.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace pluginxx {
namespace ui {

namespace {

constexpr int kFallbackDividerWidth = 40;
constexpr int kProgressBarCells     = 10;

/// UTF-8 解码：返回码点与推进的字节数（非法字节按 1 字节跳过，返回 0xFFFD）
std::uint32_t decodeUtf8(const std::string_view text, const std::size_t index, std::size_t& size) {
    const auto byte = [&text](const std::size_t i) {
        return static_cast<std::uint32_t>(static_cast<unsigned char>(text[i]));
    };
    const std::uint32_t first = byte(index);
    if (first < 0x80) {
        size = 1;
        return first;
    }
    if ((first & 0xE0) == 0xC0 && index + 1 < text.size()) {
        size = 2;
        return ((first & 0x1F) << 6) | (byte(index + 1) & 0x3F);
    }
    if ((first & 0xF0) == 0xE0 && index + 2 < text.size()) {
        size = 3;
        return ((first & 0x0F) << 12) | ((byte(index + 1) & 0x3F) << 6) | (byte(index + 2) & 0x3F);
    }
    if ((first & 0xF8) == 0xF0 && index + 3 < text.size()) {
        size = 4;
        return ((first & 0x07) << 18) | ((byte(index + 1) & 0x3F) << 12) |
               ((byte(index + 2) & 0x3F) << 6) | (byte(index + 3) & 0x3F);
    }
    size = 1;
    return 0xFFFD;
}

/// 宽字符（占两列）判定：东亚宽/全角与常见 emoji
bool isWideCodePoint(const std::uint32_t cp) {
    if (cp < 0x1100) {
        return false;
    }
    return (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0x303E) ||
           (cp >= 0x3041 && cp <= 0x33FF) || (cp >= 0x3400 && cp <= 0x4DBF) ||
           (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0xA000 && cp <= 0xA4CF) ||
           (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) ||
           (cp >= 0xFE10 && cp <= 0xFE19) || (cp >= 0xFE30 && cp <= 0xFE6F) ||
           (cp >= 0xFF00 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6) ||
           (cp >= 0x1F300 && cp <= 0x1F64F) || (cp >= 0x1F900 && cp <= 0x1F9FF) ||
           (cp >= 0x20000 && cp <= 0x3FFFD);
}

/// 零宽（组合字符、变体选择符、零宽连接符等）
bool isZeroWidthCodePoint(const std::uint32_t cp) {
    return (cp >= 0x0300 && cp <= 0x036F) || (cp >= 0x200B && cp <= 0x200F) ||
           (cp >= 0x20D0 && cp <= 0x20FF) || (cp >= 0xFE00 && cp <= 0xFE0F) ||
           (cp >= 0xFE20 && cp <= 0xFE2F) || cp == 0xFEFF;
}

/// 文本解析上下文
struct Ctx {
    int               width  = 0; ///< >0 时折行
    const TextLookup* lookup = nullptr;

    std::string text(const TextValue& value) const {
        return value.resolve(lookup != nullptr ? *lookup : TextLookup{});
    }
};

std::string repeat(const char c, const int count) {
    return count > 0 ? std::string(static_cast<std::size_t>(count), c) : std::string();
}

/// 硬折行（按显示列宽切分；宽字符不会被切开）
std::vector<std::string> wrapLines(const std::string_view text, const int width) {
    std::vector<std::string> lines;
    if (width <= 0) {
        lines.emplace_back(text);
        return lines;
    }
    // 先按换行切段，再对每段按显示宽度折行
    std::size_t start = 0;
    while (start <= text.size()) {
        const std::size_t end = text.find('\n', start);
        const std::string_view segment =
            text.substr(start, end == std::string_view::npos ? std::string_view::npos : end - start);
        std::string current;
        int         used = 0;
        for (std::size_t i = 0; i < segment.size();) {
            std::size_t     size = 1;
            const std::uint32_t cp = decodeUtf8(segment, i, size);
            const int w = isZeroWidthCodePoint(cp) ? 0 : (isWideCodePoint(cp) ? 2 : 1);
            if (used + w > width && !current.empty()) {
                lines.push_back(current);
                current.clear();
                used = 0;
            }
            current.append(segment.substr(i, size));
            used += w;
            i += size;
        }
        lines.push_back(current);
        if (end == std::string_view::npos) {
            break;
        }
        start = end + 1;
    }
    return lines;
}

/// 取若干行文本（自动折行），多行用 `\n` 连接
std::string linesOf(const std::string_view text, const Ctx& ctx) {
    const std::vector<std::string> lines = wrapLines(text, ctx.width);
    std::string out;
    for (std::size_t i = 0; i < lines.size(); ++i) {
        if (i > 0) {
            out.push_back('\n');
        }
        out.append(lines[i]);
    }
    return out;
}

std::string indentLines(const std::string& text, const char* prefix) {
    if (text.empty() || prefix == nullptr) {
        return text;
    }
    std::string out;
    out.reserve(text.size() + 8);
    std::size_t start = 0;
    bool        first = true;
    while (true) {
        const std::size_t end = text.find('\n', start);
        if (!first) {
            out.push_back('\n');
        }
        out.append(prefix);
        out.append(text, start, end == std::string::npos ? std::string::npos : end - start);
        first = false;
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return out;
}

std::string padEnd(const std::string& text, const int targetWidth) {
    const int pad = targetWidth - displayWidth(text);
    return pad > 0 ? text + repeat(' ', pad) : text;
}

std::string padStart(const std::string& text, const int targetWidth) {
    const int pad = targetWidth - displayWidth(text);
    return pad > 0 ? repeat(' ', pad) + text : text;
}

std::string alignTo(const std::string& text, const int targetWidth, const std::string_view align) {
    if (align == "end") {
        return padStart(text, targetWidth);
    }
    if (align == "center") {
        const int pad = targetWidth - displayWidth(text);
        if (pad > 0) {
            const int left = pad / 2;
            return repeat(' ', left) + text + repeat(' ', pad - left);
        }
        return text;
    }
    return padEnd(text, targetWidth);
}

/// 单个组件 → 文本行（返回 false 表示"没有内容可显示"，调用方跳过）
bool itemText(const Item& item, const Ctx& ctx, std::string& out);

/// 子块文本（`separator` 为空表示逐行拼接）
std::string childrenText(const std::vector<Item>& children, const Ctx& ctx,
                         const char* separator = nullptr) {
    std::string out;
    bool        first = true;
    for (const Item& child : children) {
        std::string text;
        if (!itemText(child, ctx, text)) {
            continue;
        }
        if (separator == nullptr) {
            if (!first) {
                out.push_back('\n');
            }
        } else if (!first) {
            out.append(separator);
        }
        out.append(text);
        first = false;
    }
    return out;
}

/// 控件当前值的文本形态
std::string controlValueText(const Item& item, const Ctx& ctx) {
    const std::string raw = item.valueJson;
    if (item.control == "checkbox" || item.control == "switch") {
        return raw == "true" ? "true" : "false";
    }
    if (item.control == "buttons" || item.control == "select") {
        for (const ControlOption& option : item.options) {
            if (option.valueJson == raw && !option.label.empty()) {
                return ctx.text(option.label);
            }
        }
    }
    if (raw.size() >= 2 && raw.front() == '"' && raw.back() == '"') {
        return raw.substr(1, raw.size() - 2);
    }
    return raw;
}

bool itemText(const Item& item, const Ctx& ctx, std::string& out) {
    const auto text = [&](const TextValue& value) {
        return ctx.text(value);
    };

    if (item.kind == "Text") {
        const std::string value = text(item.text);
        if (value.empty()) {
            return false;
        }
        std::vector<std::string> lines = wrapLines(value, ctx.width);
        if (item.maxLines > 0 && lines.size() > static_cast<std::size_t>(item.maxLines)) {
            lines.resize(static_cast<std::size_t>(item.maxLines));
        }
        std::string joined;
        for (std::size_t i = 0; i < lines.size(); ++i) {
            if (i > 0) {
                joined.push_back('\n');
            }
            joined.append(lines[i]);
        }
        out = joined;
        return true;
    }
    if (item.kind == "Divider") {
        out = repeat('-', ctx.width > 0 ? ctx.width : kFallbackDividerWidth);
        return true;
    }
    if (item.kind == "Gap") {
        out.clear();
        return true;
    }
    if (item.kind == "Button") {
        std::string label = text(item.label);
        if (label.empty()) {
            return false;
        }
        out = "[" + label + "]";
        return true;
    }
    if (item.kind == "Block") {
        std::string head = text(item.title);
        const std::string body = childrenText(item.children, ctx);
        if (head.empty() && body.empty()) {
            return false;
        }
        out = head.empty() ? body : (body.empty() ? head : head + "\n" + indentLines(body, "  "));
        return true;
    }
    if (item.kind == "Row") {
        out = childrenText(item.children, ctx, " | ");
        return !out.empty();
    }
    if (item.kind == "Column" || item.kind == "Padding" || item.kind == "SizedBox" ||
        item.kind == "Align" || item.kind == "Expanded") {
        out = childrenText(item.children, ctx);
        return !out.empty();
    }
    if (item.kind == "Spacer") {
        return false;
    }
    if (item.kind == "Collapse") {
        const std::string head = std::string(item.expanded ? "[-] " : "[+] ") + text(item.title);
        if (!item.expanded) {
            out = head;
            return true;
        }
        const std::string body = childrenText(item.children, ctx);
        out = body.empty() ? head : head + "\n" + indentLines(body, "  ");
        return true;
    }
    if (item.kind == "KV") {
        int keyWidth = 0;
        for (const KeyValuePair& pair : item.pairs) {
            keyWidth = std::max(keyWidth, displayWidth(text(pair.key)));
        }
        std::string body;
        bool        first = true;
        for (const KeyValuePair& pair : item.pairs) {
            const std::string key   = text(pair.key);
            const std::string value = text(pair.value);
            if (key.empty() && value.empty()) {
                continue;
            }
            if (!first) {
                body.push_back('\n');
            }
            body.append(padEnd(key, keyWidth));
            body.append(item.sep);
            body.append(value);
            first = false;
        }
        out = body;
        return !body.empty();
    }
    if (item.kind == "Table") {
        std::size_t columns = item.columns.size();
        for (const std::vector<TableCell>& row : item.rows) {
            columns = std::max(columns, row.size());
        }
        if (columns == 0) {
            return false;
        }
        std::vector<std::string> headers(columns);
        std::vector<std::string> aligns(columns, "start");
        for (std::size_t c = 0; c < item.columns.size(); ++c) {
            headers[c] = text(item.columns[c].title);
            aligns[c]  = item.columns[c].align;
        }
        std::vector<std::vector<std::string>> cells;
        cells.reserve(item.rows.size());
        for (const std::vector<TableCell>& row : item.rows) {
            std::vector<std::string> line(columns);
            for (std::size_t c = 0; c < row.size(); ++c) {
                line[c] = text(row[c].text);
            }
            cells.push_back(std::move(line));
        }
        // 列宽 = 表头与单元格里最宽的一个
        std::vector<int> widths(columns, 0);
        for (std::size_t c = 0; c < columns; ++c) {
            widths[c] = displayWidth(headers[c]);
        }
        for (const std::vector<std::string>& row : cells) {
            for (std::size_t c = 0; c < columns; ++c) {
                widths[c] = std::max(widths[c], displayWidth(row[c]));
            }
        }
        int total = 0;
        for (const int w : widths) {
            total += w;
        }
        total += static_cast<int>(columns - 1) * 2;

        std::string body;
        if (item.header) {
            for (std::size_t c = 0; c < columns; ++c) {
                if (c > 0) {
                    body.append("  ");
                }
                body.append(alignTo(headers[c], widths[c], aligns[c]));
            }
            body.push_back('\n');
            body.append(repeat('-', total));
        }
        for (const std::vector<std::string>& row : cells) {
            if (!body.empty()) {
                body.push_back('\n');
            }
            for (std::size_t c = 0; c < columns; ++c) {
                if (c > 0) {
                    body.append("  ");
                }
                body.append(alignTo(row[c], widths[c], aligns[c]));
            }
        }
        out = body;
        return !out.empty();
    }
    if (item.kind == "Tree") {
        std::string body;
        // 递归画树：连接线用 ASCII（`|- ` / "`- "），没有连接线时缩进两格
        const std::function<void(const std::vector<TreeNode>&, const std::string&, bool)> walk =
            [&](const std::vector<TreeNode>& nodes, const std::string& prefix, const bool root) {
                for (std::size_t i = 0; i < nodes.size(); ++i) {
                    const TreeNode& node   = nodes[i];
                    const bool      last   = i + 1 == nodes.size();
                    if (!body.empty()) {
                        body.push_back('\n');
                    }
                    if (item.connector) {
                        body.append(prefix);
                        body.append(last ? "`- " : "|- ");
                    } else {
                        body.append(prefix.empty() && root ? "" : prefix + "  ");
                    }
                    body.append(text(node.label));
                    if (!node.children.empty()) {
                        std::string childPrefix = prefix;
                        if (item.connector) {
                            childPrefix.append(last ? "   " : "|  ");
                        }
                        walk(node.children, childPrefix, false);
                    }
                }
            };
        walk(item.nodes, "", true);
        out = body;
        return !out.empty();
    }
    if (item.kind == "Progress") {
        const double total = item.total > 0.0 ? item.total : 100.0;
        int          filled =
            static_cast<int>(std::round(kProgressBarCells * item.value / total + 0.0));
        filled = std::min(std::max(filled, 0), kProgressBarCells);
        std::string bar = "[" + repeat('#', filled) + repeat('-', kProgressBarCells - filled) + "]";
        const std::string label = text(item.label);
        if (item.showValue) {
            bar.append(" ");
            bar.append(detail::formatNumber(item.value));
            bar.append(item.unit);
        }
        out = label.empty() ? bar : label + ": " + bar;
        return true;
    }
    if (item.kind == "Badge") {
        const std::string value = text(item.text);
        if (value.empty()) {
            return false;
        }
        out = "[" + value + "]";
        return true;
    }
    if (item.kind == "Control") {
        const std::string label = text(item.label);
        const std::string value = controlValueText(item, ctx);
        if (label.empty()) {
            out = value;
            return !out.empty();
        }
        out = label + ": " + value;
        return true;
    }
    if (item.kind == "Markdown") {
        if (item.markdown.empty()) {
            return false;
        }
        out = linesOf(item.markdown, ctx);
        return true;
    }
    if (item.kind == "Icon") {
        const std::string value = !item.glyph.empty() ? item.glyph
                                : !item.icon.empty()  ? item.icon
                                : text(item.alt);
        if (value.empty()) {
            return false;
        }
        out = value;
        return true;
    }
    if (item.kind == "Stack") {
        for (auto it = item.children.rbegin(); it != item.children.rend(); ++it) {
            if (itemText(*it, ctx, out)) {
                return true;
            }
        }
        return false;
    }
    if (item.kind == "Image") {
        const std::string alt = text(item.alt);
        if (alt.empty()) {
            return false;
        }
        out = alt;
        return true;
    }
    if (item.kind == "Diff") {
        std::string body;
        if (!item.path.empty()) {
            body.append("@@ ").append(item.path);
        }
        const auto addLines = [&body](const std::string& text, const char* prefix) {
            std::size_t start = 0;
            while (start <= text.size()) {
                const std::size_t end = text.find('\n', start);
                const std::string line =
                    text.substr(start, end == std::string::npos ? std::string::npos : end - start);
                if (!line.empty()) {
                    if (!body.empty()) {
                        body.push_back('\n');
                    }
                    body.append(prefix).append(line);
                }
                if (end == std::string::npos) {
                    break;
                }
                start = end + 1;
            }
        };
        addLines(item.oldStr, "- ");
        addLines(item.newStr, "+ ");
        out = body;
        return !out.empty();
    }
    if (item.kind == "Sparkline") {
        if (item.data.empty()) {
            return false;
        }
        static const char* kBlocks[] = {"\u2581", "\u2582", "\u2583", "\u2584",
                                        "\u2585", "\u2586", "\u2587", "\u2588"};
        static const char* kBars[]   = {"\u258F", "\u258E", "\u258D", "\u258C",
                                        "\u258B", "\u258A", "\u2589", "\u2588"};
        double minValue = item.data.front();
        double maxValue = item.data.front();
        if (item.hasMin) {
            minValue = item.minValue;
        } else {
            for (const double v : item.data) {
                minValue = std::min(minValue, v);
            }
        }
        if (item.hasMax) {
            maxValue = item.maxValue;
        } else {
            for (const double v : item.data) {
                maxValue = std::max(maxValue, v);
            }
        }
        const double span = maxValue > minValue ? maxValue - minValue : 1.0;
        std::string  art;
        for (const double v : item.data) {
            const double ratio = (v - minValue) / span;
            int          level = static_cast<int>(ratio * 7.0 + 0.5);
            level              = std::min(std::max(level, 0), 7);
            art.append(item.glyphStyle == "bar" ? kBars[level] : kBlocks[level]);
        }
        if (item.showLast) {
            art.append(" ");
            art.append(detail::formatNumber(item.data.back()));
        }
        out = art;
        return true;
    }
    if (item.kind == "Diagram") {
        if (item.mermaid.empty()) {
            return false;
        }
        out = linesOf(item.mermaid, ctx);
        return true;
    }
    if (item.kind == "musicxx.Shader") {
        if (item.fallback.empty()) {
            return false;
        }
        out = item.fallback;
        return true;
    }
    // 未知组件：有 fallback 就用它
    if (!item.fallback.empty()) {
        out = item.fallback;
        return true;
    }
    return false;
}

} // namespace

int displayWidth(const std::string_view text) {
    int width = 0;
    for (std::size_t i = 0; i < text.size();) {
        std::size_t         size = 1;
        const std::uint32_t cp   = decodeUtf8(text, i, size);
        if (!isZeroWidthCodePoint(cp)) {
            width += isWideCodePoint(cp) ? 2 : 1;
        }
        i += size;
    }
    return width;
}

std::string plainTextItem(const Item& item, const int width, const TextLookup& lookup) {
    Ctx ctx;
    ctx.width  = width;
    ctx.lookup = lookup ? &lookup : nullptr;
    std::string out;
    if (!itemText(item, ctx, out)) {
        return {};
    }
    return out;
}

std::string plainText(const std::vector<Item>& items, const int width, const TextLookup& lookup) {
    Ctx ctx;
    ctx.width  = width;
    ctx.lookup = lookup ? &lookup : nullptr;
    std::string out;
    bool        first = true;
    for (const Item& item : items) {
        std::string text;
        if (!itemText(item, ctx, text)) {
            continue;
        }
        if (!first) {
            out.push_back('\n');
        }
        out.append(text);
        first = false;
    }
    return out;
}

std::string plainTextDocument(const Document& doc, const int width, const TextLookup& lookup) {
    Ctx ctx;
    ctx.width  = width;
    ctx.lookup = lookup ? &lookup : nullptr;
    std::string out;
    const auto  append = [&out](const std::string& text) {
        if (text.empty()) {
            return;
        }
        if (!out.empty()) {
            out.push_back('\n');
        }
        out.append(text);
    };
    const std::string title = ctx.text(doc.title);
    if (!title.empty()) {
        append(title);
    }
    const std::string subtitle = ctx.text(doc.subtitle);
    if (!subtitle.empty()) {
        append(subtitle);
    }
    for (const Item& item : doc.blocks) {
        std::string text;
        if (!itemText(item, ctx, text)) {
            continue;
        }
        // 注意：空文本也要占一行（Gap 就是"一个空行"），不能按 empty 跳过
        if (!out.empty()) {
            out.push_back('\n');
        }
        out.append(text);
    }
    return out;
}

std::string plainTextJson(const utilxx_base::Json& json, const int width, const TextLookup& lookup) {
    return plainTextDocument(parseDocument(json), width, lookup);
}

} // namespace ui
} // namespace pluginxx
