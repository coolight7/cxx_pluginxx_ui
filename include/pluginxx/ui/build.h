#pragma once

/// 构建器：用 C++ 直接拼组件项（header-only，只用标准库）
///
/// 适合"主程序自己画界面"以及插件需要按逻辑动态决定结构时使用；跨语言复用同一套
/// 结构时优先用生成的 kit（kit.g.h / pluginxx_ui.kit）。
///
/// 用法：
/// ```cpp
/// using namespace pluginxx::ui;
/// Item card = build::card(
///     build::title("统计"),
///     build::row({build::text("切歌次数"), build::spacer(), build::badge("3")})
/// );
/// ```
#include "pluginxx/ui/gen/blocks.g.h"
#include "pluginxx/ui/item.h"

#include <initializer_list>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace pluginxx {
namespace ui {
namespace build {

/// 组件名是否在生成表里（构建器的写法容错；未知组件也能构造，供客户端专属块使用）
inline bool isKnownKind(std::string_view kind) {
    for (const BlockMeta& meta : gen::kBlockTable) {
        if (detail::iequals(meta.kind, kind)) {
            return true;
        }
    }
    return false;
}

inline Item node(std::string_view kind) {
    Item item;
    item.kind.assign(kind);
    item.known = isKnownKind(kind);
    return item;
}

/// 文本类
inline Item text(std::string_view value) {
    Item item = node("Text");
    item.text = TextValue::of(value);
    return item;
}

inline Item title(std::string_view value) {
    Item item = text(value);
    item.textType = "title";
    return item;
}

inline Item caption(std::string_view value) {
    Item item = text(value);
    item.textType = "caption";
    item.tone     = "hint";
    return item;
}

inline Item markdown(std::string_view source) {
    Item item = node("Markdown");
    item.markdown.assign(source);
    return item;
}

/// 布局类
inline Item divider() {
    return node("Divider");
}

inline Item gap(const double size = 0.0) {
    Item item = node("Gap");
    item.size = size > 0.0 ? SizeValue::of(size) : SizeValue::autoValue();
    return item;
}

inline Item spacer(const int flex = 1) {
    Item item = node("Spacer");
    item.flex = flex < 1 ? 1 : flex;
    return item;
}

inline Item row(std::initializer_list<Item> children, const double gapSize = 0.0) {
    Item item = node("Row");
    item.children.assign(children);
    if (gapSize > 0.0) {
        item.hasGap = true;
        item.gap    = SizeValue::of(gapSize);
    }
    return item;
}

inline Item column(std::initializer_list<Item> children, const double gapSize = 0.0) {
    Item item = node("Column");
    item.children.assign(children);
    if (gapSize > 0.0) {
        item.hasGap = true;
        item.gap    = SizeValue::of(gapSize);
    }
    return item;
}

inline Item expanded(Item child, const int flex = 1) {
    Item item = node("Expanded");
    item.flex = flex < 1 ? 1 : flex;
    item.children.push_back(std::move(child));
    return item;
}

inline Item sizedBox(const double width, const double height, Item child = {}) {
    Item item = node("SizedBox");
    if (width > 0.0) {
        item.width = SizeValue::of(width);
    }
    if (height > 0.0) {
        item.height = SizeValue::of(height);
    }
    if (!child.kind.empty()) {
        item.children.push_back(std::move(child));
    }
    return item;
}

inline Item padding(const Edges& insets, Item child) {
    Item item = node("Padding");
    item.padding    = insets;
    item.hasPadding = true;
    item.children.push_back(std::move(child));
    return item;
}

inline Item align(Item child, std::string_view horizontal = "center",
                  std::string_view vertical = "center") {
    Item item = node("Align");
    item.align.assign(horizontal);
    item.vertical.assign(vertical);
    item.children.push_back(std::move(child));
    return item;
}

inline Item stack(std::initializer_list<Item> children) {
    Item item = node("Stack");
    item.children.assign(children);
    return item;
}

/// 内容块与交互
inline Item card(Item child, std::string_view blockTitle = {}, std::string_view variant = "card") {
    Item item = node("Block");
    item.title   = TextValue::of(blockTitle);
    item.variant.assign(variant);
    if (!child.kind.empty()) {
        item.children.push_back(std::move(child));
    }
    return item;
}

inline Item button(std::string_view label, Action action = {},
                   std::string_view variant = "secondary") {
    Item item = node("Button");
    item.label = TextValue::of(label);
    item.variant.assign(variant);
    item.action = std::move(action);
    return item;
}

inline Item badge(std::string_view value, std::string_view tone = "accent") {
    Item item = node("Badge");
    item.text = TextValue::of(value);
    item.tone.assign(tone);
    return item;
}

inline Item progress(const double value, const double total = 100.0,
                     std::string_view unit = "%") {
    Item item = node("Progress");
    item.value = value;
    item.total = total;
    item.unit.assign(unit);
    return item;
}

inline Item kv(std::vector<KeyValuePair> pairs) {
    Item item = node("KV");
    item.pairs = std::move(pairs);
    return item;
}

inline Item icon(std::string_view name, std::string_view glyph) {
    Item item = node("Icon");
    item.icon.assign(name);
    item.glyph.assign(glyph);
    return item;
}

inline Item image(std::string_view source, std::string_view src, std::string_view alt = {}) {
    Item item = node("Image");
    item.source.assign(source);
    item.src.assign(src);
    item.alt = TextValue::of(alt);
    return item;
}

/// 控件：值变化时客户端派发 `action`，并在参数里补 `{"id":…,"value":…}`
inline Item control(std::string_view form, std::string_view controlId, TextValue label = {},
                    Action action = {}, std::string_view valueJson = {}) {
    Item item = node("Control");
    item.control.assign(form);
    item.id.assign(controlId);
    item.label       = std::move(label);
    item.action      = std::move(action);
    item.valueJson.assign(valueJson);
    return item;
}

/// 动作快捷构造
inline Action dispatch(std::string_view name, std::string_view argsJson = "{}") {
    Action action;
    action.kind = Action::Kind::Dispatch;
    action.name.assign(name);
    action.argsJson.assign(argsJson);
    return action;
}

inline Action route(std::string_view target) {
    Action action;
    action.kind = Action::Kind::Route;
    action.route.assign(target);
    return action;
}

inline Action command(std::string_view name, std::string_view argsJson = "{}") {
    Action action;
    action.kind = Action::Kind::Command;
    action.name.assign(name);
    action.argsJson.assign(argsJson);
    return action;
}

} // namespace build
} // namespace ui
} // namespace pluginxx
