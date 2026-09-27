// 组件描述解析与序列化（JSON ↔ 规范模型）
#include "pluginxx/ui/parse.h"

#include "pluginxx/ui/gen/blocks.g.h"

#include <utilxx_base/json.h>

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace pluginxx {
namespace ui {

namespace {

using utilxx_base::Json;

/// 枚举取值个数（编译期从数组推出）
template<typename T, std::size_t N>
constexpr std::size_t countOf(const T (&)[N]) {
    return N;
}

#define PLUGINXX_UI_ENUM(values) (values), countOf(values)

/// 取字符串字段（缺失/非字符串返回空）
std::string fieldString(const Json& json, const std::string_view key) {
    const Json& value = json[key];
    return value.is_string() ? std::string(value.get_string_view()) : std::string();
}

bool fieldHas(const Json& json, const std::string_view key) {
    return json.is_object() && json.contains(key) && !json[key].is_null();
}

double fieldNumber(const Json& json, const std::string_view key, const double fallback) {
    const Json& value = json[key];
    return value.is_number() ? value.get<double>() : fallback;
}

bool fieldBool(const Json& json, const std::string_view key, const bool fallback) {
    const Json& value = json[key];
    return value.is_bool() ? value.get<bool>() : fallback;
}

/// 枚举字段：忽略大小写匹配生成表，未命中用默认值
std::string fieldEnum(const Json& json, const std::string_view key,
                      const std::string_view* values, const std::size_t count,
                      const std::string_view fallback) {
    const std::string raw = fieldString(json, key);
    if (raw.empty()) {
        return std::string(fallback);
    }
    const std::string_view normalized = detail::enumNormalize(values, count, raw);
    return normalized.empty() ? std::string(fallback) : std::string(normalized);
}

/// 语义色字段（未知取值退回 normal）
std::string fieldTone(const Json& json, const std::string_view key,
                      const std::string_view fallback = "normal") {
    return fieldEnum(json, key, PLUGINXX_UI_ENUM(gen::kEnumTone), fallback);
}

std::string clampTextBytes(const std::string_view text, const std::size_t maxBytes) {
    if (maxBytes == 0 || text.size() <= maxBytes) {
        return std::string(text);
    }
    std::size_t cut = maxBytes;
    // 不切断 UTF-8 码点：回退到首字节
    while (cut > 0 && (static_cast<unsigned char>(text[cut]) & 0xC0) == 0x80) {
        --cut;
    }
    return std::string(text.substr(0, cut));
}

/// 紧凑 JSON 文本（对象/数组/标量都适用；null 返回空串）
std::string jsonText(const Json& value) {
    if (value.is_null()) {
        return {};
    }
    return value.dump();
}

} // namespace

void ParseReport::warn(std::string message) {
    warnings.push_back(std::move(message));
}

namespace {

/// 文本取值：字符串 → 字面文本；对象 → {key, fallback, args}
TextValue textValueOf(const Json& value) {
    TextValue out;
    if (value.is_string()) {
        out.fallback = std::string(value.get_string_view());
        return out;
    }
    if (value.is_object()) {
        out.key      = fieldString(value, "key");
        out.fallback = fieldString(value, "fallback");
        if (fieldHas(value, "args")) {
            out.argsJson = jsonText(value["args"]);
        }
    } else if (value.is_number()) {
        out.fallback = detail::formatNumber(value.get<double>());
    } else if (value.is_bool()) {
        out.fallback = value.get<bool>() ? "true" : "false";
    }
    return out;
}

/// 尺寸取值：数字（u）/ "auto" / {"percent": n}；负值按 0 处理并记警告
SizeValue sizeValueOf(const Json& value, ParseReport* report, const std::string& what) {
    if (value.is_number()) {
        const double v = value.get<double>();
        if (v < 0.0) {
            if (report) {
                report->warn(what + " 给了负值 " + detail::formatNumber(v) + "，按 0 处理");
            }
            return SizeValue::of(0.0);
        }
        return SizeValue::of(v);
    }
    if (value.is_string()) {
        const std::string text = std::string(value.get_string_view());
        if (detail::iequals(text, "auto") || detail::iequals(text, "gap")) {
            return SizeValue::autoValue();
        }
        if (report) {
            report->warn(what + " 的尺寸写法 `" + text + "` 无法识别，按 auto 处理");
        }
        return SizeValue::autoValue();
    }
    if (value.is_object() && value.contains("percent")) {
        const double p = value["percent"].is_number() ? value["percent"].get<double>() : 0.0;
        if (p < 0.0) {
            if (report) {
                report->warn(what + " 的 percent 为负，按 0 处理");
            }
            return SizeValue::percent(0.0);
        }
        return SizeValue::percent(p);
    }
    return SizeValue::autoValue();
}

/// 四边数值：数字（四边相同）或 {all/horizontal/vertical/left/right/top/bottom}（越具体越优先）
Edges edgesOf(const Json& value, ParseReport* report, const std::string& what) {
    if (value.is_number()) {
        const double v = value.get<double>();
        if (v < 0.0) {
            if (report) {
                report->warn(what + " 给了负值 " + detail::formatNumber(v) + "，按 0 处理");
            }
            return Edges::all(0.0);
        }
        return Edges::all(v);
    }
    if (!value.is_object()) {
        return {};
    }
    const auto pick = [&value, report, &what](const char* key, const double fallback) {
        if (!value.contains(key) || !value[key].is_number()) {
            return fallback;
        }
        const double v = value[key].get<double>();
        if (v < 0.0) {
            if (report) {
                report->warn(what + "." + key + " 给了负值，按 0 处理");
            }
            return 0.0;
        }
        return v;
    };
    const double all        = pick("all", 0.0);
    const double horizontal = pick("horizontal", all);
    const double vertical   = pick("vertical", all);
    return Edges{
        pick("left", horizontal),
        pick("top", vertical),
        pick("right", horizontal),
        pick("bottom", vertical),
    };
}

/// 动作：字符串短写 = dispatch；对象按 kind
Action actionOf(const Json& value) {
    Action action;
    if (value.is_string()) {
        action.kind = Action::Kind::Dispatch;
        action.name = std::string(value.get_string_view());
        return action;
    }
    if (!value.is_object()) {
        return action;
    }
    const std::string kind =
        fieldEnum(value, "kind", PLUGINXX_UI_ENUM(gen::kEnumActionKind), "none");
    if (kind == "dispatch") {
        action.kind = Action::Kind::Dispatch;
        action.name = fieldString(value, "name");
    } else if (kind == "route") {
        action.kind  = Action::Kind::Route;
        action.route = fieldString(value, "route");
    } else if (kind == "command") {
        action.kind = Action::Kind::Command;
        action.name = fieldString(value, "name");
    }
    if (fieldHas(value, "args")) {
        action.argsJson = jsonText(value["args"]);
    }
    return action;
}

struct Ctx {
    const Limits* limits = nullptr;
    ParseReport*  report = nullptr;

    void warn(const std::string& message) const {
        if (report) {
            report->warn(message);
        }
    }

    void truncate(const std::string& message) const {
        if (report) {
            report->warn(message);
            report->truncated = true;
        }
    }
};

Item parseBlockImpl(const Json& json, const Ctx& ctx, int depth);

/// 解析子块数组（带数量与层级上限）
std::vector<Item> parseChildren(const Json& json, const Ctx& ctx, const int depth,
                                const std::string& what) {
    std::vector<Item> out;
    if (depth >= ctx.limits->maxDepth) {
        ctx.truncate(what + " 超过层级上限 " + std::to_string(ctx.limits->maxDepth) + "，子块被丢弃");
        return out;
    }
    if (!json.is_array()) {
        return out;
    }
    const std::size_t total = json.size();
    const std::size_t count = std::min(total, ctx.limits->maxItems);
    if (count < total) {
        ctx.truncate(what + " 的子块超过上限 " + std::to_string(ctx.limits->maxItems) + "，已截断");
    }
    out.reserve(count);
    for (std::size_t i = 0; i < count; ++i) {
        out.push_back(parseBlockImpl(json[i], ctx, depth + 1));
    }
    return out;
}

std::vector<TextValue> textListOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<TextValue> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxItems);
    if (count < value.size()) {
        ctx.truncate(what + " 的数量超过上限，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        out.push_back(textValueOf(value[i]));
    }
    return out;
}

std::vector<ControlOption> optionsOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<ControlOption> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxItems);
    if (count < value.size()) {
        ctx.truncate(what + " 的候选项超过上限，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        const Json& node = value[i];
        ControlOption option;
        if (node.is_object()) {
            if (node.contains("value")) {
                option.valueJson = jsonText(node["value"]);
            }
            option.label = textValueOf(node["label"]);
            option.tone  = fieldTone(node, "tone", "");
        } else {
            option.valueJson = jsonText(node);
            option.label     = textValueOf(node);
        }
        out.push_back(std::move(option));
    }
    return out;
}

std::vector<Threshold> thresholdsOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<Threshold> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxItems);
    if (count < value.size()) {
        ctx.truncate(what + " 的阈值超过上限，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        const Json& node = value[i];
        if (!node.is_object()) {
            continue;
        }
        Threshold threshold;
        threshold.at   = fieldNumber(node, "at", 0.0);
        threshold.tone = fieldTone(node, "tone", "accent");
        out.push_back(std::move(threshold));
    }
    return out;
}

std::vector<double> numbersOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<double> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxDataPoints);
    if (count < value.size()) {
        ctx.truncate(what + " 的数据点超过上限，已截断");
    }
    out.reserve(count);
    for (std::size_t i = 0; i < count; ++i) {
        if (value[i].is_number()) {
            out.push_back(value[i].get<double>());
        }
    }
    return out;
}

std::vector<std::string> tonesOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<std::string> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxItems);
    if (count < value.size()) {
        ctx.truncate(what + " 的配色数量超过上限，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        const std::string raw = value[i].is_string() ? std::string(value[i].get_string_view()) : "";
        const std::string_view normalized =
            detail::enumNormalize(PLUGINXX_UI_ENUM(gen::kEnumTone), raw);
        if (!normalized.empty()) {
            out.emplace_back(normalized);
        }
    }
    return out;
}

std::vector<KeyValuePair> pairsOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<KeyValuePair> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxItems);
    if (count < value.size()) {
        ctx.truncate(what + " 的条目超过上限，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        const Json& node = value[i];
        if (!node.is_object()) {
            continue;
        }
        KeyValuePair pair;
        pair.key   = textValueOf(node["k"]);
        pair.value = textValueOf(node["v"]);
        pair.kTone = fieldTone(node, "kTone", "");
        pair.vTone = fieldTone(node, "vTone", "");
        out.push_back(std::move(pair));
    }
    return out;
}

std::vector<TableColumn> columnsOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<TableColumn> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count =
        std::min(value.size(), static_cast<std::size_t>(ctx.limits->maxTableColumns));
    if (count < value.size()) {
        ctx.truncate(what + " 的列数超过上限 " + std::to_string(ctx.limits->maxTableColumns) +
                     "，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        const Json& node = value[i];
        TableColumn column;
        if (node.is_object()) {
            column.title = textValueOf(node["title"]);
            column.align = fieldEnum(node, "align", PLUGINXX_UI_ENUM(gen::kEnumAlignH), "start");
            if (fieldHas(node, "width")) {
                column.width = sizeValueOf(node["width"], ctx.report, what + "[" +
                                                                    std::to_string(i) + "].width");
            }
            column.tone = fieldTone(node, "tone", "");
        } else {
            column.title = textValueOf(node);
        }
        out.push_back(std::move(column));
    }
    return out;
}

std::vector<std::vector<TableCell>> rowsOf(const Json& value, const Ctx& ctx,
                                           const std::string& what) {
    std::vector<std::vector<TableCell>> out;
    if (!value.is_array()) {
        return out;
    }
    const std::size_t count = std::min(value.size(), ctx.limits->maxTableRows);
    if (count < value.size()) {
        ctx.truncate(what + " 的行数超过上限 " + std::to_string(ctx.limits->maxTableRows) +
                     "，已截断");
    }
    for (std::size_t i = 0; i < count; ++i) {
        const Json& row = value[i];
        std::vector<TableCell> cells;
        if (row.is_array()) {
            const std::size_t cellCount = std::min(
                row.size(), static_cast<std::size_t>(ctx.limits->maxTableColumns)
            );
            if (cellCount < row.size()) {
                ctx.truncate(what + "[" + std::to_string(i) + "] 的单元格超过列数上限，已截断");
            }
            for (std::size_t c = 0; c < cellCount; ++c) {
                const Json& node       = row[c];
                TableCell   cell;
                if (node.is_object()) {
                    cell.text   = textValueOf(node["text"]);
                    cell.tone   = fieldTone(node, "tone", "");
                    cell.action = actionOf(node["action"]);
                } else {
                    cell.text = textValueOf(node);
                }
                cells.push_back(std::move(cell));
            }
        }
        out.push_back(std::move(cells));
    }
    return out;
}

TreeNode parseTreeNode(const Json& node, const Ctx& ctx, const int depth,
                       std::size_t* budget) {
    TreeNode out;
    if (!node.is_object() || *budget == 0) {
        return out;
    }
    --(*budget);
    out.label    = textValueOf(node["label"]);
    out.tone     = fieldTone(node, "tone", "");
    out.action   = actionOf(node["action"]);
    if (node.contains("children") && node["children"].is_array() && depth < ctx.limits->maxDepth) {
        const std::size_t count =
            std::min(node["children"].size(), ctx.limits->maxItems);
        if (count < node["children"].size()) {
            ctx.truncate("树节点的子节点超过上限，已截断");
        }
        for (std::size_t i = 0; i < count; ++i) {
            out.children.push_back(parseTreeNode(node["children"][i], ctx, depth + 1, budget));
        }
    }
    return out;
}

std::vector<TreeNode> nodesOf(const Json& value, const Ctx& ctx, const std::string& what) {
    std::vector<TreeNode> out;
    if (!value.is_array()) {
        return out;
    }
    std::size_t budget = ctx.limits->maxTreeNodes;
    const std::size_t count = std::min(value.size(), ctx.limits->maxItems);
    if (count < value.size()) {
        ctx.truncate(what + " 的节点超过上限，已截断");
    }
    for (std::size_t i = 0; i < count && budget > 0; ++i) {
        out.push_back(parseTreeNode(value[i], ctx, 0, &budget));
    }
    if (budget == 0) {
        ctx.truncate(what + " 的节点总数超过上限 " + std::to_string(ctx.limits->maxTreeNodes) +
                     "，已截断");
    }
    return out;
}

/// 解析一个块
Item parseBlockImpl(const Json& json, const Ctx& ctx, const int depth) {
    Item item;
    if (!json.is_object()) {
        // 非对象既不是块也不是文本：返回未识别的空块（客户端跳过）
        item.kind  = "Text";
        item.known = false;
        return item;
    }

    const std::string_view canonical = canonicalKind(fieldString(json, "kind"));
    if (canonical.empty()) {
        item.kind     = "Text";
        item.known    = false;
        item.fallback = fieldString(json, "fallback");
        return item;
    }
    item.kind = std::string(canonical);

    item.id       = fieldString(json, "id");
    item.fallback = fieldString(json, "fallback");
    item.action   = actionOf(json["action"]);

    if (fieldHas(json, "text")) {
        const Json& raw = json["text"];
        if (raw.is_string()) {
            item.text.fallback = clampTextBytes(raw.get_string_view(), ctx.limits->maxTextBytes);
        } else {
            item.text = textValueOf(raw);
        }
    }
    if (item.text.fallback.size() > ctx.limits->maxTextBytes) {
        item.text.fallback = clampTextBytes(item.text.fallback, ctx.limits->maxTextBytes);
        ctx.truncate("文本超过长度上限，已截断");
    }

    if (canonical == "Text") {
        item.textType = fieldEnum(json, "type", PLUGINXX_UI_ENUM(gen::kEnumTextType), "body");
        item.tone     = fieldTone(json, "tone");
        item.bold     = fieldBool(json, "bold", false);
        item.dim      = fieldBool(json, "dim", false);
        item.mono     = fieldBool(json, "mono", false);
        item.wrap     = fieldBool(json, "wrap", true);
        item.maxLines = static_cast<int>(fieldNumber(json, "maxLines", 0.0));
        item.align    = fieldEnum(json, "align", PLUGINXX_UI_ENUM(gen::kEnumAlignH), "start");
        return item;
    }
    if (canonical == "Divider") {
        return item;
    }
    if (canonical == "Gap") {
        item.size = fieldHas(json, "size")
                        ? sizeValueOf(json["size"], ctx.report, "Gap.size")
                        : SizeValue::autoValue();
        return item;
    }
    if (canonical == "Button") {
        item.label    = textValueOf(json["label"]);
        item.variant  = fieldEnum(json, "variant", PLUGINXX_UI_ENUM(gen::kEnumButtonVariant),
                                  "secondary");
        item.icon     = fieldString(json, "icon");
        item.disabled = fieldBool(json, "disabled", false);
        return item;
    }
    if (canonical == "Block") {
        item.title   = textValueOf(json["title"]);
        item.variant = fieldEnum(json, "variant", PLUGINXX_UI_ENUM(gen::kEnumBlockVariant), "card");
        if (fieldHas(json, "padding")) {
            item.padding    = edgesOf(json["padding"], ctx.report, "Block.padding");
            item.hasPadding = true;
        }
        if (fieldHas(json, "margin")) {
            item.margin    = edgesOf(json["margin"], ctx.report, "Block.margin");
            item.hasMargin = true;
        }
        item.children = parseChildren(json["children"], ctx, depth, "Block.children");
        return item;
    }
    if (canonical == "Row" || canonical == "Column") {
        if (fieldHas(json, "gap")) {
            item.gap    = sizeValueOf(json["gap"], ctx.report, item.kind + ".gap");
            item.hasGap = true;
        }
        item.main     = fieldEnum(json, "main", PLUGINXX_UI_ENUM(gen::kEnumMainAxis), "start");
        item.cross    = fieldEnum(json, "cross", PLUGINXX_UI_ENUM(gen::kEnumAlignHV), "start");
        item.children = parseChildren(json["children"], ctx, depth, item.kind + ".children");
        return item;
    }
    if (canonical == "Expanded" || canonical == "Spacer") {
        item.flex = static_cast<int>(fieldNumber(json, "flex", 1.0));
        if (item.flex < 1) {
            ctx.warn(item.kind + ".flex 小于 1 没有意义，按 1 处理");
            item.flex = 1;
        }
        if (canonical == "Expanded") {
            item.children = parseChildren(json["children"], ctx, depth, "Expanded.children");
        }
        return item;
    }
    if (canonical == "SizedBox") {
        if (fieldHas(json, "width")) {
            item.width = sizeValueOf(json["width"], ctx.report, "SizedBox.width");
        }
        if (fieldHas(json, "height")) {
            item.height = sizeValueOf(json["height"], ctx.report, "SizedBox.height");
        }
        item.aspect   = fieldNumber(json, "aspect", 0.0);
        item.children = parseChildren(json["children"], ctx, depth, "SizedBox.children");
        return item;
    }
    if (canonical == "Padding") {
        item.padding    = edgesOf(json["padding"], ctx.report, "Padding.padding");
        item.hasPadding = true;
        item.children   = parseChildren(json["children"], ctx, depth, "Padding.children");
        return item;
    }
    if (canonical == "Align") {
        item.align    = fieldEnum(json, "align", PLUGINXX_UI_ENUM(gen::kEnumAlignHV), "center");
        item.vertical = fieldEnum(json, "vertical", PLUGINXX_UI_ENUM(gen::kEnumAlignHV), "center");
        item.children = parseChildren(json["children"], ctx, depth, "Align.children");
        return item;
    }
    if (canonical == "Collapse") {
        item.title    = textValueOf(json["title"]);
        item.expanded = fieldBool(json, "expanded", true);
        item.children = parseChildren(json["children"], ctx, depth, "Collapse.children");
        return item;
    }
    if (canonical == "KV") {
        item.pairs    = pairsOf(json["pairs"], ctx, "KV.pairs");
        item.sep      = fieldHas(json, "sep") ? fieldString(json, "sep") : std::string(" : ");
        item.keyWidth = fieldHas(json, "keyWidth")
                            ? sizeValueOf(json["keyWidth"], ctx.report, "KV.keyWidth")
                            : SizeValue::autoValue();
        return item;
    }
    if (canonical == "Table") {
        item.header  = fieldBool(json, "header", true);
        item.columns = columnsOf(json["columns"], ctx, "Table.columns");
        item.rows    = rowsOf(json["rows"], ctx, "Table.rows");
        return item;
    }
    if (canonical == "Tree") {
        item.connector = fieldBool(json, "connector", true);
        item.nodes     = nodesOf(json["nodes"], ctx, "Tree.nodes");
        return item;
    }
    if (canonical == "Progress") {
        item.value     = fieldNumber(json, "value", 0.0);
        item.total     = fieldNumber(json, "total", 100.0);
        item.label     = textValueOf(json["label"]);
        item.unit      = fieldHas(json, "unit") ? fieldString(json, "unit") : std::string("%");
        item.showValue = fieldBool(json, "showValue", true);
        item.tone      = fieldTone(json, "tone", "accent");
        item.thresholds = thresholdsOf(json["thresholds"], ctx, "Progress.thresholds");
        if (fieldHas(json, "width")) {
            item.width = sizeValueOf(json["width"], ctx.report, "Progress.width");
        }
        return item;
    }
    if (canonical == "Badge") {
        item.tone = fieldTone(json, "tone", "accent");
        return item;
    }
    if (canonical == "Control") {
        item.control   = fieldEnum(json, "control", PLUGINXX_UI_ENUM(gen::kEnumControlKind), "");
        item.label     = textValueOf(json["label"]);
        item.help      = textValueOf(json["help"]);
        item.options   = optionsOf(json["options"], ctx, "Control.options");
        item.valueJson = fieldHas(json, "value") ? jsonText(json["value"]) : std::string();
        item.disabled  = fieldBool(json, "disabled", false);
        item.integer   = fieldBool(json, "integer", false);
        item.multiline = fieldBool(json, "multiline", false);
        if (fieldHas(json, "min")) {
            item.hasMin   = true;
            item.minValue = fieldNumber(json, "min", 0.0);
        }
        if (fieldHas(json, "max")) {
            item.hasMax   = true;
            item.maxValue = fieldNumber(json, "max", 0.0);
        }
        if (fieldHas(json, "step")) {
            item.hasStep = true;
            item.step    = fieldNumber(json, "step", 0.0);
        }
        return item;
    }
    if (canonical == "Markdown") {
        const std::string_view source =
            json["text"].is_string() ? json["text"].get_string_view() : std::string_view{};
        item.markdown = clampTextBytes(source, ctx.limits->maxTextBytes);
        if (item.markdown.size() < source.size()) {
            ctx.truncate("Markdown 文本超过长度上限，已截断");
        }
        return item;
    }
    if (canonical == "Icon") {
        item.icon  = fieldString(json, "name");
        item.glyph = fieldString(json, "glyph");
        item.tone  = fieldTone(json, "tone");
        item.alt   = textValueOf(json["alt"]);
        if (fieldHas(json, "size")) {
            item.size = sizeValueOf(json["size"], ctx.report, "Icon.size");
        }
        return item;
    }
    if (canonical == "Stack") {
        item.align    = fieldEnum(json, "align", PLUGINXX_UI_ENUM(gen::kEnumAlignHV), "start");
        item.vertical = fieldEnum(json, "vertical", PLUGINXX_UI_ENUM(gen::kEnumAlignHV), "start");
        item.children = parseChildren(json["children"], ctx, depth, "Stack.children");
        return item;
    }
    if (canonical == "Image") {
        item.source   = fieldHas(json, "source") ? fieldString(json, "source") : std::string("file");
        item.src      = fieldString(json, "src");
        item.aspect   = fieldNumber(json, "aspect", 0.0);
        item.radius   = fieldNumber(json, "radius", 0.0);
        item.fit      = fieldEnum(json, "fit", PLUGINXX_UI_ENUM(gen::kEnumImageFit), "contain");
        item.alt      = textValueOf(json["alt"]);
        if (fieldHas(json, "width")) {
            item.width = sizeValueOf(json["width"], ctx.report, "Image.width");
        }
        if (fieldHas(json, "height")) {
            item.height = sizeValueOf(json["height"], ctx.report, "Image.height");
        }
        return item;
    }
    if (canonical == "Diff") {
        item.path   = clampTextBytes(fieldString(json, "path"), ctx.limits->maxTextBytes);
        item.oldStr = clampTextBytes(fieldString(json, "oldStr"), ctx.limits->maxTextBytes);
        item.newStr = clampTextBytes(fieldString(json, "newStr"), ctx.limits->maxTextBytes);
        return item;
    }
    if (canonical == "Sparkline") {
        item.data       = numbersOf(json["data"], ctx, "Sparkline.data");
        item.glyphHeight = static_cast<int>(fieldNumber(json, "height", 1.0));
        item.glyphStyle = fieldEnum(json, "glyphStyle", PLUGINXX_UI_ENUM(gen::kEnumSparkStyle),
                                    "block");
        item.tone       = fieldTone(json, "tone", "accent");
        item.showLast   = fieldBool(json, "showLast", true);
        item.colors     = tonesOf(json["colors"], ctx, "Sparkline.colors");
        if (fieldHas(json, "min")) {
            item.hasMin   = true;
            item.minValue = fieldNumber(json, "min", 0.0);
        }
        if (fieldHas(json, "max")) {
            item.hasMax   = true;
            item.maxValue = fieldNumber(json, "max", 0.0);
        }
        return item;
    }
    if (canonical == "Diagram") {
        item.mermaid = clampTextBytes(fieldString(json, "mermaid"), ctx.limits->maxTextBytes);
        return item;
    }
    if (canonical == "musicxx.Shader") {
        item.bundle           = fieldString(json, "bundle");
        item.speed            = fieldNumber(json, "speed", 1.0);
        item.maxFps           = static_cast<int>(fieldNumber(json, "maxFps", 0.0));
        item.animate          = fieldBool(json, "animate", true);
        item.resolutionScale  = fieldNumber(json, "resolutionScale", 1.0);
        if (fieldHas(json, "args")) {
            item.shaderArgsJson = jsonText(json["args"]);
        }
        return item;
    }
    return item;
}

} // namespace

const BlockMeta* findBlockMeta(const std::string_view kind) {
    if (kind.empty()) {
        return nullptr;
    }
    for (const BlockMeta& meta : gen::kBlockTable) {
        if (detail::iequals(meta.kind, kind)) {
            return &meta;
        }
    }
    return nullptr;
}

bool isKnownBlock(const std::string_view kind) {
    return findBlockMeta(kind) != nullptr;
}

std::string_view canonicalKind(const std::string_view kind) {
    const BlockMeta* meta = findBlockMeta(kind);
    return meta != nullptr ? meta->kind : std::string_view{};
}

Item parseBlock(const Json& json, const Limits& limits, ParseReport* report) {
    const Ctx ctx{&limits, report};
    return parseBlockImpl(json, ctx, 0);
}

std::vector<Item> parseBlocks(const Json& json, const Limits& limits, ParseReport* report) {
    const Ctx ctx{&limits, report};
    const Json* array = &json;
    if (json.is_object()) {
        if (json.contains("blocks")) {
            array = &json["blocks"];
        } else if (json.contains("items")) {
            array = &json["items"];
        }
    }
    // 顶层块的父层记为 -1（顶层块自身算第 1 层）
    return parseChildren(*array, ctx, -1, "blocks");
}

Document parseDocument(const Json& json, const Limits& limits, ParseReport* report) {
    Document doc;
    const Ctx ctx{&limits, report};
    if (json.is_array()) {
        doc.blocks = parseChildren(json, ctx, -1, "blocks");
        return doc;
    }
    if (!json.is_object()) {
        return doc;
    }
    // 文档大小上限（按紧凑 JSON 的字节数计）
    if (limits.maxDocumentBytes > 0) {
        const std::string text = json.dump();
        if (text.size() > limits.maxDocumentBytes) {
            ctx.truncate("界面描述超过大小上限 " + std::to_string(limits.maxDocumentBytes) +
                         " 字节，已按上限解析");
        }
    }
    doc.title    = textValueOf(json["title"]);
    doc.subtitle = textValueOf(json["subtitle"]);
    if (json.contains("blocks")) {
        doc.blocks = parseChildren(json["blocks"], ctx, -1, "blocks");
    } else if (json.contains("items")) {
        doc.blocks = parseChildren(json["items"], ctx, -1, "blocks");
    }
    return doc;
}

// ===== 序列化 =====

namespace {

Json textValueToJson(const TextValue& value) {
    const bool hasKey  = !value.key.empty();
    const bool hasArgs = !value.argsJson.empty();
    if (!hasKey && !hasArgs) {
        return Json(value.fallback);
    }
    Json out = Json::object();
    if (hasKey) {
        out["key"] = value.key;
    }
    if (!value.fallback.empty()) {
        out["fallback"] = value.fallback;
    }
    if (hasArgs) {
        try {
            out["args"] = Json::parse(value.argsJson);
        } catch (...) {
            // 参数文本不合法时忽略（解析阶段已经保证它是合法 JSON 的 dump）
        }
    }
    return out;
}

Json sizeValueToJson(const SizeValue& size) {
    switch (size.mode) {
        case SizeValue::Mode::Value:
            return Json(size.value);
        case SizeValue::Mode::Percent:
            return Json::object({{"percent", Json(size.value)}});
        case SizeValue::Mode::Auto:
        default:
            return Json("auto");
    }
}

Json edgesToJson(const Edges& edges) {
    return Json::object({
        {"left",   Json(edges.left)},
        {"top",    Json(edges.top)},
        {"right",  Json(edges.right)},
        {"bottom", Json(edges.bottom)},
    });
}

Json actionToJson(const Action& action) {
    switch (action.kind) {
        case Action::Kind::Dispatch: {
            if (action.argsJson.empty()) {
                return Json(action.name);
            }
            Json out = Json::object({{"kind", Json("dispatch")}, {"name", Json(action.name)}});
            try {
                out["args"] = Json::parse(action.argsJson);
            } catch (...) {
            }
            return out;
        }
        case Action::Kind::Route:
            return Json::object({{"kind", Json("route")}, {"route", Json(action.route)}});
        case Action::Kind::Command: {
            Json out = Json::object({{"kind", Json("command")}, {"name", Json(action.name)}});
            if (!action.argsJson.empty()) {
                try {
                    out["args"] = Json::parse(action.argsJson);
                } catch (...) {
                }
            }
            return out;
        }
        case Action::Kind::None:
        default:
            return Json();
    }
}

Json dumpBlockImpl(const Item& item);

/// 树节点（递归）
Json dumpTreeNodeImpl(const TreeNode& node) {
    Json out      = Json::object();
    out["label"]  = textValueToJson(node.label);
    if (!node.tone.empty()) {
        out["tone"] = node.tone;
    }
    if (!node.action.empty()) {
        out["action"] = actionToJson(node.action);
    }
    if (!node.children.empty()) {
        Json children = Json::array();
        for (const TreeNode& child : node.children) {
            children.push_back(dumpTreeNodeImpl(child));
        }
        out["children"] = children;
    }
    return out;
}

/// 单槽容器的子块（无子块时不输出）
void putChildren(Json& out, const std::vector<Item>& children) {
    if (children.empty()) {
        return;
    }
    Json array = Json::array();
    for (const Item& child : children) {
        array.push_back(dumpBlockImpl(child));
    }
    out["children"] = array;
}

Json dumpBlockImpl(const Item& item) {
    Json out = Json::object();
    out["kind"] = item.kind;

    if (!item.known && !item.fallback.empty()) {
        out["fallback"] = item.fallback;
        return out;
    }
    if (!item.id.empty()) {
        out["id"] = item.id;
    }

    const auto putText = [&out](const TextValue& value) {
        if (!value.empty()) {
            out["text"] = textValueToJson(value);
        }
    };
    const auto putLabel = [&out](const TextValue& value) {
        if (!value.empty()) {
            out["label"] = textValueToJson(value);
        }
    };

    if (item.kind == "Text") {
        putText(item.text);
        out["type"] = item.textType;
        out["tone"] = item.tone;
        if (item.bold) {
            out["bold"] = true;
        }
        if (item.dim) {
            out["dim"] = true;
        }
        if (item.mono) {
            out["mono"] = true;
        }
        out["wrap"] = item.wrap;
        if (item.maxLines > 0) {
            out["maxLines"] = item.maxLines;
        }
        out["align"] = item.align;
    } else if (item.kind == "Gap") {
        out["size"] = sizeValueToJson(item.size);
    } else if (item.kind == "Button") {
        putLabel(item.label);
        out["variant"] = item.variant;
        if (!item.icon.empty()) {
            out["icon"] = item.icon;
        }
        if (item.disabled) {
            out["disabled"] = true;
        }
    } else if (item.kind == "Block") {
        if (!item.title.empty()) {
            out["title"] = textValueToJson(item.title);
        }
        out["variant"] = item.variant;
        if (item.hasPadding) {
            out["padding"] = edgesToJson(item.padding);
        }
        if (item.hasMargin) {
            out["margin"] = edgesToJson(item.margin);
        }
        putChildren(out, item.children);
    } else if (item.kind == "Row" || item.kind == "Column") {
        if (item.hasGap) {
            out["gap"] = sizeValueToJson(item.gap);
        }
        out["main"]  = item.main;
        out["cross"] = item.cross;
        putChildren(out, item.children);
    } else if (item.kind == "Expanded" || item.kind == "Spacer") {
        out["flex"] = item.flex;
        putChildren(out, item.children);
    } else if (item.kind == "SizedBox") {
        if (!item.width.isAuto()) {
            out["width"] = sizeValueToJson(item.width);
        }
        if (!item.height.isAuto()) {
            out["height"] = sizeValueToJson(item.height);
        }
        if (item.aspect > 0.0) {
            out["aspect"] = item.aspect;
        }
        putChildren(out, item.children);
    } else if (item.kind == "Padding") {
        out["padding"] = edgesToJson(item.padding);
        putChildren(out, item.children);
    } else if (item.kind == "Align") {
        out["align"]    = item.align;
        out["vertical"] = item.vertical;
        putChildren(out, item.children);
    } else if (item.kind == "Collapse") {
        if (!item.title.empty()) {
            out["title"] = textValueToJson(item.title);
        }
        out["expanded"] = item.expanded;
        putChildren(out, item.children);
    } else if (item.kind == "KV") {
        Json pairs = Json::array();
        for (const KeyValuePair& pair : item.pairs) {
            Json node = Json::object();
            node["k"] = textValueToJson(pair.key);
            node["v"] = textValueToJson(pair.value);
            if (!pair.kTone.empty()) {
                node["kTone"] = pair.kTone;
            }
            if (!pair.vTone.empty()) {
                node["vTone"] = pair.vTone;
            }
            pairs.push_back(node);
        }
        out["pairs"]    = pairs;
        out["keyWidth"] = sizeValueToJson(item.keyWidth);
        out["sep"]      = item.sep;
    } else if (item.kind == "Table") {
        out["header"] = item.header;
        Json columns  = Json::array();
        for (const TableColumn& column : item.columns) {
            Json node = Json::object();
            if (!column.title.empty()) {
                node["title"] = textValueToJson(column.title);
            }
            node["align"] = column.align;
            if (!column.width.isAuto()) {
                node["width"] = sizeValueToJson(column.width);
            }
            if (!column.tone.empty()) {
                node["tone"] = column.tone;
            }
            columns.push_back(node);
        }
        out["columns"] = columns;
        Json rows      = Json::array();
        for (const std::vector<TableCell>& row : item.rows) {
            Json cells = Json::array();
            for (const TableCell& cell : row) {
                if (cell.tone.empty() && cell.action.empty()) {
                    cells.push_back(textValueToJson(cell.text));
                } else {
                    Json node = Json::object();
                    node["text"] = textValueToJson(cell.text);
                    if (!cell.tone.empty()) {
                        node["tone"] = cell.tone;
                    }
                    if (!cell.action.empty()) {
                        node["action"] = actionToJson(cell.action);
                    }
                    cells.push_back(node);
                }
            }
            rows.push_back(cells);
        }
        out["rows"] = rows;
    } else if (item.kind == "Tree") {
        out["connector"] = item.connector;
        Json nodes       = Json::array();
        for (const TreeNode& treeNode : item.nodes) {
            nodes.push_back(dumpTreeNodeImpl(treeNode));
        }
        out["nodes"] = nodes;
    } else if (item.kind == "Progress") {
        out["value"] = item.value;
        out["total"] = item.total;
        if (!item.label.empty()) {
            out["label"] = textValueToJson(item.label);
        }
        out["unit"]      = item.unit;
        out["showValue"] = item.showValue;
        out["tone"]      = item.tone;
        Json thresholds  = Json::array();
        for (const Threshold& threshold : item.thresholds) {
            thresholds.push_back(
                Json::object({{"at", Json(threshold.at)}, {"tone", Json(threshold.tone)}})
            );
        }
        if (!item.thresholds.empty()) {
            out["thresholds"] = thresholds;
        }
        if (!item.width.isAuto()) {
            out["width"] = sizeValueToJson(item.width);
        }
    } else if (item.kind == "Badge") {
        putText(item.text);
        out["tone"] = item.tone;
    } else if (item.kind == "Control") {
        out["control"] = item.control;
        if (!item.label.empty()) {
            out["label"] = textValueToJson(item.label);
        }
        if (!item.help.empty()) {
            out["help"] = textValueToJson(item.help);
        }
        Json options = Json::array();
        for (const ControlOption& option : item.options) {
            Json node = Json::object();
            try {
                node["value"] = Json::parse(option.valueJson);
            } catch (...) {
                node["value"] = option.valueJson;
            }
            node["label"] = textValueToJson(option.label);
            if (!option.tone.empty()) {
                node["tone"] = option.tone;
            }
            options.push_back(node);
        }
        if (!item.options.empty()) {
            out["options"] = options;
        }
        if (!item.valueJson.empty()) {
            try {
                out["value"] = Json::parse(item.valueJson);
            } catch (...) {
            }
        }
        if (item.disabled) {
            out["disabled"] = true;
        }
        if (item.integer) {
            out["integer"] = true;
        }
        if (item.multiline) {
            out["multiline"] = true;
        }
        if (item.hasMin) {
            out["min"] = item.minValue;
        }
        if (item.hasMax) {
            out["max"] = item.maxValue;
        }
        if (item.hasStep) {
            out["step"] = item.step;
        }
    } else if (item.kind == "Markdown") {
        out["text"] = item.markdown;
    } else if (item.kind == "Icon") {
        if (!item.icon.empty()) {
            out["name"] = item.icon;
        }
        if (!item.glyph.empty()) {
            out["glyph"] = item.glyph;
        }
        if (!item.size.isAuto()) {
            out["size"] = sizeValueToJson(item.size);
        }
        out["tone"] = item.tone;
    } else if (item.kind == "Stack") {
        out["align"]    = item.align;
        out["vertical"] = item.vertical;
        putChildren(out, item.children);
    } else if (item.kind == "Image") {
        out["source"] = item.source;
        out["src"]    = item.src;
        if (!item.width.isAuto()) {
            out["width"] = sizeValueToJson(item.width);
        }
        if (!item.height.isAuto()) {
            out["height"] = sizeValueToJson(item.height);
        }
        if (item.aspect > 0.0) {
            out["aspect"] = item.aspect;
        }
        if (item.radius > 0.0) {
            out["radius"] = item.radius;
        }
        out["fit"] = item.fit;
        if (!item.alt.empty()) {
            out["alt"] = textValueToJson(item.alt);
        }
    } else if (item.kind == "Diff") {
        if (!item.path.empty()) {
            out["path"] = item.path;
        }
        out["oldStr"] = item.oldStr;
        out["newStr"] = item.newStr;
    } else if (item.kind == "Sparkline") {
        Json data = Json::array();
        for (const double v : item.data) {
            data.push_back(Json(v));
        }
        out["data"]       = data;
        out["height"]     = item.glyphHeight;
        out["glyphStyle"] = item.glyphStyle;
        if (item.hasMin) {
            out["min"] = item.minValue;
        }
        if (item.hasMax) {
            out["max"] = item.maxValue;
        }
        out["tone"]     = item.tone;
        out["showLast"] = item.showLast;
        if (!item.colors.empty()) {
            Json colors = Json::array();
            for (const std::string& tone : item.colors) {
                colors.push_back(Json(tone));
            }
            out["colors"] = colors;
        }
    } else if (item.kind == "Diagram") {
        out["mermaid"] = item.mermaid;
    } else if (item.kind == "musicxx.Shader") {
        out["bundle"] = item.bundle;
        if (!item.shaderArgsJson.empty()) {
            try {
                out["args"] = Json::parse(item.shaderArgsJson);
            } catch (...) {
            }
        }
        out["speed"]           = item.speed;
        out["animate"]         = item.animate;
        out["resolutionScale"] = item.resolutionScale;
        if (item.maxFps > 0) {
            out["maxFps"] = item.maxFps;
        }
    }

    if (!item.action.empty()) {
        out["action"] = actionToJson(item.action);
    }
    return out;
}

} // namespace

Json dumpItem(const Item& item) {
    return dumpBlockImpl(item);
}

Json dumpBlocks(const std::vector<Item>& items) {
    Json out = Json::array();
    for (const Item& item : items) {
        out.push_back(dumpBlockImpl(item));
    }
    return out;
}

Json dumpDocument(const Document& doc) {
    Json out = Json::object();
    if (!doc.title.empty()) {
        out["title"] = textValueToJson(doc.title);
    }
    if (!doc.subtitle.empty()) {
        out["subtitle"] = textValueToJson(doc.subtitle);
    }
    out["blocks"] = dumpBlocks(doc.blocks);
    return out;
}

// ===== 能力段 =====

Json capabilitiesToJson(const Capabilities& caps) {
    Json out = Json::object();
    out["apiVersion"] = caps.apiVersion;
    out["kind"]       = caps.kind;

    Json blocks = Json::array();
    for (const std::string& name : caps.blocks) {
        blocks.push_back(Json(name));
    }
    out["blocks"] = blocks;

    Json controls = Json::array();
    for (const std::string& name : caps.controls) {
        controls.push_back(Json(name));
    }
    out["controls"] = controls;

    if (caps.kind == "tui") {
        out["cell"] = Json::object({
            {"width",  Json(caps.cell.width)},
            {"height", Json(caps.cell.height)}
        });
    }
    out["gap"] = caps.gap;
    if (!caps.icons.empty()) {
        Json icons = Json::array();
        for (const std::string& name : caps.icons) {
            icons.push_back(Json(name));
        }
        out["icons"] = icons;
    }
    out["percent"] = caps.percent;
    out["aspect"]  = caps.aspect;
    out["limits"]  = Json::object({
        {"maxDepth",         Json(caps.limits.maxDepth)},
        {"maxItems",         Json(caps.limits.maxItems)},
        {"maxTextBytes",     Json(caps.limits.maxTextBytes)},
        {"maxDocumentBytes", Json(caps.limits.maxDocumentBytes)},
        {"maxTableRows",     Json(caps.limits.maxTableRows)},
        {"maxTableColumns",  Json(caps.limits.maxTableColumns)},
        {"maxTreeNodes",     Json(caps.limits.maxTreeNodes)},
        {"maxDataPoints",    Json(caps.limits.maxDataPoints)},
    });
    return out;
}

Capabilities capabilitiesFromJson(const Json& json) {
    Capabilities caps;
    if (!json.is_object()) {
        return caps;
    }
    caps.apiVersion = static_cast<int>(fieldNumber(json, "apiVersion", gen::kUiApiVersion));
    if (json.contains("kind") && json["kind"].is_string()) {
        const std::string kind = std::string(json["kind"].get_string_view());
        caps.kind = detail::iequals(kind, "tui") ? "tui" : "gui";
    }
    if (json.contains("blocks") && json["blocks"].is_array()) {
        caps.blocks.clear();
        for (const Json& value : json["blocks"]) {
            if (value.is_string()) {
                caps.blocks.emplace_back(value.get_string_view());
            }
        }
    } else {
        caps.blocks = Capabilities::full().blocks;
    }
    if (json.contains("controls") && json["controls"].is_array()) {
        caps.controls.clear();
        for (const Json& value : json["controls"]) {
            if (value.is_string()) {
                caps.controls.emplace_back(value.get_string_view());
            }
        }
    } else {
        caps.controls = Capabilities::full().controls;
    }
    if (json.contains("cell") && json["cell"].is_object()) {
        caps.cell.width  = fieldNumber(json["cell"], "width", gen::kDefaultCellWidth);
        caps.cell.height = fieldNumber(json["cell"], "height", gen::kDefaultCellHeight);
    }
    caps.gap     = fieldNumber(json, "gap", gen::kDefaultGap);
    caps.percent = fieldBool(json, "percent", true);
    caps.aspect  = fieldBool(json, "aspect", true);
    if (json.contains("icons") && json["icons"].is_array()) {
        caps.icons.clear();
        for (const Json& value : json["icons"]) {
            if (value.is_string()) {
                caps.icons.emplace_back(value.get_string_view());
            }
        }
    }
    if (json.contains("limits") && json["limits"].is_object()) {
        const Json& limits = json["limits"];
        // 上限用 double 字段传递，这里按需转回整数类型
        caps.limits.maxDepth =
            static_cast<int>(fieldNumber(limits, "maxDepth", static_cast<double>(caps.limits.maxDepth)));
        caps.limits.maxItems = static_cast<std::size_t>(
            fieldNumber(limits, "maxItems", static_cast<double>(caps.limits.maxItems))
        );
        caps.limits.maxTextBytes = static_cast<std::size_t>(
            fieldNumber(limits, "maxTextBytes", static_cast<double>(caps.limits.maxTextBytes))
        );
        caps.limits.maxDocumentBytes = static_cast<std::size_t>(
            fieldNumber(limits, "maxDocumentBytes", static_cast<double>(caps.limits.maxDocumentBytes))
        );
        caps.limits.maxTableRows = static_cast<std::size_t>(
            fieldNumber(limits, "maxTableRows", static_cast<double>(caps.limits.maxTableRows))
        );
        caps.limits.maxTableColumns = static_cast<int>(
            fieldNumber(limits, "maxTableColumns", static_cast<double>(caps.limits.maxTableColumns))
        );
        caps.limits.maxTreeNodes = static_cast<std::size_t>(
            fieldNumber(limits, "maxTreeNodes", static_cast<double>(caps.limits.maxTreeNodes))
        );
        caps.limits.maxDataPoints = static_cast<std::size_t>(
            fieldNumber(limits, "maxDataPoints", static_cast<double>(caps.limits.maxDataPoints))
        );
    }
    return caps;
}

Capabilities fullCapabilities() {
    Capabilities caps;
    caps.kind = "gui";
    caps.blocks.reserve(gen::kBlockCount);
    for (const BlockMeta& meta : gen::kBlockTable) {
        caps.blocks.emplace_back(meta.kind);
    }
    caps.controls.reserve(countOf(gen::kControlKinds));
    for (const std::string_view control : gen::kControlKinds) {
        caps.controls.emplace_back(control);
    }
    return caps;
}

Capabilities minimalCapabilities() {
    Capabilities caps;
    caps.kind     = "gui";
    caps.blocks   = {"Text"};
    caps.controls = {};
    caps.percent  = false;
    caps.aspect   = false;
    return caps;
}

Capabilities Capabilities::full() {
    return fullCapabilities();
}

Capabilities Capabilities::minimal() {
    return minimalCapabilities();
}

/// 动作描述 → 规范模型（块字段与客户端扩展点共用同一套解析）
Action parseAction(const utilxx_base::Json& json) {
    return actionOf(json);
}

/// 动作 → JSON（空动作输出 null）
utilxx_base::Json dumpAction(const Action& action) {
    return actionToJson(action);
}

} // namespace ui
} // namespace pluginxx
