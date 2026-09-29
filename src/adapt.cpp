// 降级适配：规范模型 + 客户端能力 → 客户端能渲染的模型
#include "pluginxx/ui/adapt.h"

#include "pluginxx/ui/gen/adapt_rules.g.h"
#include "pluginxx/ui/plain_text.h"

#include <cstddef>
#include <string>
#include <utility>
#include <vector>

namespace pluginxx {
namespace ui {

namespace {

/// 适配的最大递归层数（超过就停止继续降级，保留 Text）
constexpr int kMaxAdaptDepth = 16;

std::string clampBytes(const std::string& text, const std::size_t maxBytes) {
    if (maxBytes == 0 || text.size() <= maxBytes) {
        return text;
    }
    std::size_t cut = maxBytes;
    while (cut > 0 && (static_cast<unsigned char>(text[cut]) & 0xC0) == 0x80) {
        --cut;
    }
    return text.substr(0, cut);
}

/// 造一个文本块（降级结果的最小形态）
Item makeText(Item source, std::string text, const bool mono,
              const std::string_view textType = "body", const std::string_view tone = "normal") {
    Item out;
    out.kind     = "Text";
    out.text     = TextValue::of(text);
    out.mono     = mono;
    out.textType = std::string(textType);
    out.tone     = std::string(tone);
    out.action   = std::move(source.action);
    return out;
}

void adjustSize(SizeValue& size, const Capabilities& caps) {
    if (!caps.percent && size.isPercent()) {
        size = SizeValue::autoValue();
    }
}

/// 能力相关的取值调整：`percent` 不支持 → 内容尺寸；`aspect` 不支持 → 忽略比例
void applyCapabilityAdjust(Item& node, const Capabilities& caps) {
    if (!caps.percent) {
        adjustSize(node.size, caps);
        adjustSize(node.width, caps);
        adjustSize(node.height, caps);
        adjustSize(node.keyWidth, caps);
        adjustSize(node.gap, caps);
    }
    if (!caps.aspect) {
        node.aspect = 0.0;
    }
}

std::vector<Item> adaptList(const std::vector<Item>& items, const Capabilities& caps,
                            AdaptReport* report, int depth);

/// 把不支持组的件降级成"文本形态"（纯文本 / fallback / 指定字段）
Item degradeToText(const Item& item, const std::string& text, const bool mono,
                   const std::string_view textType = "body",
                   const std::string_view tone = "normal") {
    Item source = item;
    return makeText(std::move(source), text, mono, textType, tone);
}

std::vector<Item> adaptItemImpl(const Item& item, const Capabilities& caps, AdaptReport* report,
                                const int depth) {
    std::vector<Item> out;
    if (depth > kMaxAdaptDepth) {
        if (report) {
            report->note("降级层数超过上限，`" + item.kind + "` 被丢弃");
        }
        return out;
    }

    // 未识别的组件：有 fallback 就显示它，否则跳过
    if (!item.known) {
        if (!item.fallback.empty()) {
            out.push_back(degradeToText(item, item.fallback, false, "caption", "hint"));
        } else if (report) {
            report->note("跳过未识别的组件（没有 fallback）");
        }
        return out;
    }

    if (caps.supportsBlock(item.kind)) {
        Item node = item;
        applyCapabilityAdjust(node, caps);

        // 控件的这个形态客户端不认识 → 退成只读展示（与纯文本形态一致）
        if (node.kind == "Control" && !caps.supportsControl(node.control)) {
            if (report) {
                report->note("控件形态 `" + node.control + "` 不受支持，退成只读文本");
            }
            const std::string text = plainTextItem(node, 0);
            if (!text.empty()) {
                out.push_back(degradeToText(node, text, false));
            }
            return out;
        }

        // 子块：不再按层级/数量上限截断（限制已移除；limits 的 0 表示不限制）
        if (!node.children.empty()) {
            if (caps.limits.maxDepth > 0 && depth >= caps.limits.maxDepth) {
                if (report) {
                    report->note(node.kind + " 的层级超过上限 " +
                                 std::to_string(caps.limits.maxDepth) + "，子块被丢弃");
                }
                node.children.clear();
            } else {
                if (caps.limits.maxItems > 0 &&
                    node.children.size() > caps.limits.maxItems) {
                    if (report) {
                        report->note(node.kind + " 的子块超过上限 " +
                                     std::to_string(caps.limits.maxItems) + "，已截断");
                    }
                    node.children.resize(caps.limits.maxItems);
                }
                node.children = adaptList(node.children, caps, report, depth + 1);
            }
        }

        // 文本长度上限（0 = 不限制）
        if (!node.text.fallback.empty()) {
            node.text.fallback = clampBytes(node.text.fallback, caps.limits.maxTextBytes);
        }
        if (caps.limits.maxDataPoints > 0 &&
            node.data.size() > caps.limits.maxDataPoints) {
            node.data.resize(caps.limits.maxDataPoints);
        }
        out.push_back(std::move(node));
        return out;
    }

    // 不支持 → 按规则降级
    switch (adaptRuleOf(item.kind)) {
        case AdaptRule::Terminal:
            // 收敛终点：即使能力表里没写也保留（客户端至少能画文字）
            out.push_back(item);
            return out;

        case AdaptRule::Flatten: {
            if (report) {
                report->note("展开 " + item.kind + "（客户端不支持该容器）");
            }
            // 容器自身的标题/文本先作为一行保留，再展开子块
            if (!item.title.empty()) {
                out.push_back(degradeToText(item, item.title.resolve(), false, "title"));
            } else if (!item.text.empty() && item.kind != "Block") {
                const std::string text = item.text.resolve();
                if (!text.empty()) {
                    out.push_back(degradeToText(item, text, item.mono));
                }
            }
            for (const Item& child : item.children) {
                std::vector<Item> adapted = adaptItemImpl(child, caps, report, depth + 1);
                out.insert(out.end(), std::make_move_iterator(adapted.begin()),
                           std::make_move_iterator(adapted.end()));
            }
            return out;
        }

        case AdaptRule::LastChild: {
            if (report) {
                report->note(item.kind + " 不支持，保留最后一个子块");
            }
            if (!item.children.empty()) {
                return adaptItemImpl(item.children.back(), caps, report, depth + 1);
            }
            return out;
        }

        case AdaptRule::GlyphText: {
            const std::string text = !item.glyph.empty() ? item.glyph : item.icon;
            if (!text.empty()) {
                out.push_back(degradeToText(item, text, true, "body", item.tone));
            } else if (!item.fallback.empty()) {
                out.push_back(degradeToText(item, item.fallback, false, "caption", "hint"));
            } else if (report) {
                report->note(item.kind + " 不支持且没有 glyph/name，跳过");
            }
            return out;
        }

        case AdaptRule::AltText: {
            const std::string text = item.alt.resolve();
            if (!text.empty()) {
                out.push_back(degradeToText(item, text, false, "body", item.tone));
            } else if (!item.fallback.empty()) {
                out.push_back(degradeToText(item, item.fallback, false, "caption", "hint"));
            } else if (report) {
                report->note(item.kind + " 不支持且没有 alt，跳过");
            }
            return out;
        }

        case AdaptRule::Skip:
        case AdaptRule::PlainTextMono:
        default: {
            std::string text = item.fallback;
            if (text.empty()) {
                text = plainTextItem(item, 0);
            }
            if (!text.empty()) {
                if (report) {
                    report->note(item.kind + " 不支持，退成文本");
                }
                out.push_back(degradeToText(item, text, true, "body", item.tone));
            } else if (report) {
                report->note(item.kind + " 不支持且没有可显示的文本，跳过");
            }
            return out;
        }
    }
}

std::vector<Item> adaptList(const std::vector<Item>& items, const Capabilities& caps,
                            AdaptReport* report, const int depth) {
    std::vector<Item> out;
    for (const Item& item : items) {
        std::vector<Item> adapted = adaptItemImpl(item, caps, report, depth);
        out.insert(out.end(), std::make_move_iterator(adapted.begin()),
                   std::make_move_iterator(adapted.end()));
    }
    return out;
}

} // namespace

void AdaptReport::note(std::string message) {
    notes.push_back(std::move(message));
}

AdaptRule adaptRuleOf(const std::string_view kind) {
    for (const gen::AdaptRuleEntry& entry : gen::kAdaptRules) {
        if (detail::iequals(entry.kind, kind)) {
            return entry.rule;
        }
    }
    return AdaptRule::Terminal;
}

std::vector<Item> adaptItem(const Item& item, const Capabilities& caps, AdaptReport* report) {
    return adaptItemImpl(item, caps, report, 0);
}

std::vector<Item> adaptBlocks(const std::vector<Item>& items, const Capabilities& caps,
                              AdaptReport* report) {
    return adaptList(items, caps, report, 0);
}

Document adaptDocument(const Document& doc, const Capabilities& caps, AdaptReport* report) {
    Document out;
    out.title    = doc.title;
    out.subtitle = doc.subtitle;
    out.blocks   = adaptList(doc.blocks, caps, report, 0);
    return out;
}

} // namespace ui
} // namespace pluginxx
