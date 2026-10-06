// 纯文本降级
#include "pluginxx/ui/plain_text.h"

#include "pluginxx/ui/parse.h"
#include "test_framework.h"

#include <utilxx_base/json.h>

#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

using pluginxx::ui::Document;
using pluginxx::ui::Item;
using utilxx_base::Json;

namespace {

bool contains(const std::string& haystack, const std::string& needle) {
    return haystack.find(needle) != std::string::npos;
}

} // namespace

PLUGINXX_UI_TEST(纯文本的基本形态) {
    const std::string text = pluginxx_ui_test::readFixture("tui_heavy.json");
    PLUGINXX_UI_CHECK(!text.empty(), "tui_heavy.json 存在");
    const Document doc  = pluginxx::ui::parseDocument(Json::parse(text));
    const std::string out = pluginxx::ui::plainTextDocument(doc);

    PLUGINXX_UI_CHECK(contains(out, "等宽文本"), "文本");
    PLUGINXX_UI_CHECK(contains(out, "状态: 运行中"), "键值按键列对齐");
    PLUGINXX_UI_CHECK(contains(out, "命令   说明"), "表头（列宽按内容）");
    PLUGINXX_UI_CHECK(contains(out, "-----------"), "表头下的分隔线");
    PLUGINXX_UI_CHECK(contains(out, "build  构建"), "表格行");
    PLUGINXX_UI_CHECK(contains(out, "agent\n  lib\ndocs"), "无连接线的树（缩进）");
    PLUGINXX_UI_CHECK(contains(out, "\u2581\u2584\u2582\u2588\u2585 5"), "块状趋势图 + 末值");
    PLUGINXX_UI_CHECK(contains(out, "\u258F\u258F\u2588"), "条状趋势图");
    PLUGINXX_UI_CHECK(contains(out, std::string(40, '-')), "分隔线默认 40 列");
    PLUGINXX_UI_CHECK(contains(out, "[----------] 0%"), "进度条");
    PLUGINXX_UI_CHECK(contains(out, "[居中标签]"), "标签");
}

PLUGINXX_UI_TEST(纯文本逐行形态) {
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"KV","pairs":[{"k":"a","v":"1"},{"k":"bb","v":"2"}]},
        {"kind":"Progress","label":"进度","value":50,"unit":"%"},
        {"kind":"Badge","text":"OK"}
    ])"));
    const std::string expected = "a  : 1\nbb : 2\n进度: [#####-----] 50%\n[OK]";
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::plainText(items), expected, "整体输出");
}

PLUGINXX_UI_TEST(纯文本按宽度折行) {
    const std::vector<Item> items =
        pluginxx::ui::parseBlocks(Json::parse(R"([{"kind":"Text","text":"abcdefgh"}])"));
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::plainText(items, 4), std::string("abcd\nefgh"), "硬折行");
    // 宽字符不会被从中间切开
    const std::vector<Item> wide =
        pluginxx::ui::parseBlocks(Json::parse(R"([{"kind":"Text","text":"中文abc"}])"));
    PLUGINXX_UI_CHECK_EQ(
        pluginxx::ui::plainText(wide, 4), std::string("中文\nabc"), "按显示列宽折行"
    );
}

PLUGINXX_UI_TEST(纯文本的缩进留白) {
    // Padding 的左留白折算成缩进列数（u → 列，默认每列 8u）; 折行宽度扣掉缩进
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Padding","padding":16,"children":[{"kind":"Text","text":"abc"}]}
    ])"));
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::plainText(items), std::string("  abc"), "两列缩进");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::plainText(items, 6), std::string("  abc"), "缩进后仍放得下");
    const std::vector<Item> wrapped = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Padding","padding":16,"children":[{"kind":"Text","text":"abcdefgh"}]}
    ])"));
    PLUGINXX_UI_CHECK_EQ(
        pluginxx::ui::plainText(wrapped, 6), std::string("  abcd\n  efgh"), "折行后每行都带缩进"
    );
    // 其余三边的留白在行式文本里没有意义（忽略）；左留白不足半列时折算结果是 0 列
    const std::vector<Item> others = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Padding","padding":{"left":3,"top":40,"right":40,"bottom":40},
         "children":[{"kind":"Text","text":"x"}]}
    ])"));
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::plainText(others), std::string("x"), "不足半列不缩进");
}

PLUGINXX_UI_TEST(纯文本的容器与降级形态) {
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Block","title":"卡片","children":[{"kind":"Text","text":"内容"}]},
        {"kind":"Row","children":[{"kind":"Text","text":"左"},{"kind":"Text","text":"右"}]},
        {"kind":"Button","label":"保存"},
        {"kind":"Collapse","id":"x","title":"折叠","expanded":false,"children":[{"kind":"Text","text":"隐藏"}]},
        {"kind":"Icon","glyph":"▶"},
        {"kind":"Image","alt":"封面"},
        {"kind":"Stack","children":[{"kind":"Text","text":"底"},{"kind":"Text","text":"顶"}]},
        {"kind":"musicxx.Shader","bundle":"a.shaderbundle","fallback":"着色器"}
    ])"));
    const std::string out = pluginxx::ui::plainText(items);
    PLUGINXX_UI_CHECK_EQ(
        out,
        std::string(
            "卡片\n"
            "  内容\n"
            "左 | 右\n"
            "[保存]\n"
            "[+] 折叠\n"
            "▶\n"
            "封面\n"
            "顶\n"
            "着色器"
        ),
        "容器与降级形态"
    );
}

PLUGINXX_UI_TEST(纯文本的标题与副标题) {
    const std::string text = pluginxx_ui_test::readFixture("core.json");
    const Document    doc  = pluginxx::ui::parseDocument(Json::parse(text));
    const std::string out  = pluginxx::ui::plainTextDocument(doc);
    PLUGINXX_UI_CHECK(out.rfind("核心组件", 0) == 0, "标题在最前");
    PLUGINXX_UI_CHECK(contains(out, "全部核心组件各一份"), "副标题（缺键回退 + 占位替换）");
}

PLUGINXX_UI_TEST(纯文本两侧结果一致) {
    // 同一批夹具在 C++ 与 Dart 两侧跑纯文本降级，结果必须逐字节一致。
    // 金文件由本用例在设置 PLUGINXX_UI_WRITE_GOLDEN=1 时重写（改了规则后要重跑一次并提交）。
    static const char* kFixtures[] = {
        "core.json",
        "gui_heavy.json",
        "tui_heavy.json",
        "controls.json",
        "stress_limits.json",
        "schema_samples.json",
    };
    const std::string goldenPath =
        std::string(PLUGINXX_UI_FIXTURES_DIR) + "/plaintext.golden.json";
    utilxx_base::Json golden = utilxx_base::Json::object();
    for (const char* name : kFixtures) {
        const std::string text = pluginxx_ui_test::readFixture(name);
        if (text.empty()) {
            continue;
        }
        golden[name] = pluginxx::ui::plainTextJson(utilxx_base::Json::parse(text), 0);
    }
    const std::string dumped = golden.dump(2) + "\n";

    if (std::getenv("PLUGINXX_UI_WRITE_GOLDEN") != nullptr) {
        std::ofstream out(goldenPath, std::ios::binary | std::ios::trunc);
        out << dumped;
        out.close();
        std::printf("  （已重写金文件 %s）\n", goldenPath.c_str());
        return;
    }

    std::ifstream file(goldenPath, std::ios::binary);
    if (!file) {
        PLUGINXX_UI_CHECK(false, "缺少 fixtures/plaintext.golden.json（先跑一次 PLUGINXX_UI_WRITE_GOLDEN=1）");
        return;
    }
    std::ostringstream buffer;
    buffer << file.rdbuf();
    const utilxx_base::Json expected = utilxx_base::Json::parse(buffer.str());
    for (const auto& entry : golden.items()) {
        const std::string key = std::string(entry.first);
        const std::string actual = entry.second.is_string() ? entry.second.get<std::string>() : "";
        const std::string want = expected.contains(key) && expected[key].is_string()
                                     ? expected[key].get<std::string>()
                                     : std::string("<缺失>");
        PLUGINXX_UI_CHECK_EQ(actual, want, std::string("夹具 ") + key + " 的纯文本");
    }
}

PLUGINXX_UI_TEST(显示列宽) {
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::displayWidth("abc"), 3, "ASCII");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::displayWidth("中文"), 4, "汉字按两列");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::displayWidth("a中b"), 4, "混合");
}
