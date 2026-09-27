// 构建器（build.h）：每个便捷构造出来的节点都能被解析、字段落在正确的位置
//
// 这一组用例同时充当"build.h 能编译"的守门：它是 header-only 的，只有真正被包含
// 才会暴露编译错误（曾经 `card()` 往 TextValue 上写字符串，直到有插件包含它才发现）。
#include "pluginxx/ui/build.h"

#include "pluginxx/ui/parse.h"
#include "test_framework.h"

#include <string>
#include <vector>

using pluginxx::ui::Action;
using pluginxx::ui::Item;
using utilxx_base::Json;

PLUGINXX_UI_TEST(构建器的节点都能被解析) {
    const std::vector<Item> items = {
        pluginxx::ui::build::title("标题"),
        pluginxx::ui::build::caption("说明"),
        pluginxx::ui::build::divider(),
        pluginxx::ui::build::gap(12),
        pluginxx::ui::build::card(pluginxx::ui::build::text("内容"), "卡片标题"),
        pluginxx::ui::build::row({pluginxx::ui::build::text("左"), pluginxx::ui::build::expanded(
                                                                       pluginxx::ui::build::text("右"))},
                                 8),
        pluginxx::ui::build::column({pluginxx::ui::build::text("上"), pluginxx::ui::build::spacer()}, 6),
        pluginxx::ui::build::sizedBox(40, 40, pluginxx::ui::build::text("方")),
        pluginxx::ui::build::align(pluginxx::ui::build::text("居中"), "center", "center"),
        pluginxx::ui::build::stack({pluginxx::ui::build::text("底"), pluginxx::ui::build::text("顶")}),
        pluginxx::ui::build::button("按钮", pluginxx::ui::build::dispatch("doIt"), "primary"),
        pluginxx::ui::build::badge("3"),
        pluginxx::ui::build::progress(30, 100, "%"),
        pluginxx::ui::build::icon("play", "▶"),
        pluginxx::ui::build::image("cover", "a.png", "封面"),
        pluginxx::ui::build::control("switch", "skipAds", pluginxx::ui::TextValue::of("跳过")),
    };
    for (const Item& item : items) {
        PLUGINXX_UI_CHECK(!item.kind.empty(), "节点有 kind");
        // 序列化一次再解析回来：字段名写错时这里就会露出来
        const Item again = pluginxx::ui::parseBlock(pluginxx::ui::dumpItem(item));
        PLUGINXX_UI_CHECK_EQ(again.kind, item.kind, "往返保留 kind");
    }
}

PLUGINXX_UI_TEST(构建器的文本与动作字段) {
    const Item card = pluginxx::ui::build::card(pluginxx::ui::build::text("内容"), "卡片标题");
    PLUGINXX_UI_CHECK_EQ(card.title.fallback, std::string("卡片标题"), "内容块标题");
    PLUGINXX_UI_CHECK_EQ(card.variant, std::string("card"), "内容块形态");

    const Item button = pluginxx::ui::build::button("刷新", pluginxx::ui::build::command(
                                                                 "musicxx.render.select",
                                                                 R"({"slot":"player.background"})"));
    PLUGINXX_UI_CHECK_EQ(button.label.fallback, std::string("刷新"), "按钮文案");
    PLUGINXX_UI_CHECK(button.action.kind == Action::Kind::Command, "按钮动作是 command");
    PLUGINXX_UI_CHECK_EQ(button.action.name, std::string("musicxx.render.select"), "动作名");

    const Item control = pluginxx::ui::build::control("checkbox", "skipAds",
                                                      pluginxx::ui::TextValue::of("跳过广告"),
                                                      pluginxx::ui::build::dispatch("setSkipAds"));
    PLUGINXX_UI_CHECK_EQ(control.control, std::string("checkbox"), "控件形态");
    PLUGINXX_UI_CHECK_EQ(control.id, std::string("skipAds"), "控件 id");
    PLUGINXX_UI_CHECK_EQ(control.label.fallback, std::string("跳过广告"), "控件标签");
    PLUGINXX_UI_CHECK(control.action.kind == Action::Kind::Dispatch, "控件动作是 dispatch");

    // 文本取值（i18n 键 + 命名占位）也能用构建器表达
    const Item text = pluginxx::ui::build::text("兜底");
    PLUGINXX_UI_CHECK_EQ(text.text.resolve(), std::string("兜底"), "文本解析");
}
