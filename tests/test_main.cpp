// 测试入口：跑完所有注册用例，失败时返回非 0
#include "test_framework.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

namespace pluginxx_ui_test {

std::string readFixture(const std::string& name) {
    std::ifstream file(std::string(PLUGINXX_UI_FIXTURES_DIR) + "/" + name, std::ios::binary);
    if (!file) {
        return {};
    }
    std::ostringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

} // namespace pluginxx_ui_test

int main(int argc, char** argv) {
    // 直接输出，崩溃时也能看到走到哪个用例
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    // 可选过滤器：只看名字里包含该子串的用例（排查崩溃时用）
    const std::string filter = argc > 1 ? std::string(argv[1]) : std::string();
    int failedCases = 0;
    for (const pluginxx_ui_test::Case& item : pluginxx_ui_test::registry()) {
        if (!filter.empty() && item.name.find(filter) == std::string::npos) {
            continue;
        }
        pluginxx_ui_test::currentCase() = item.name.c_str();
        const int before               = pluginxx_ui_test::failureCount();
        std::printf("- %s\n", item.name.c_str());
        try {
            item.body();
        } catch (const std::exception& error) {
            ++pluginxx_ui_test::failureCount();
            std::printf("  [FAIL] 抛出异常：%s\n", error.what());
        }
        if (pluginxx_ui_test::failureCount() > before) {
            ++failedCases;
        }
    }
    std::printf(
        "\n用例 %zu 个，失败 %d 个，断言失败 %d 条\n",
        pluginxx_ui_test::registry().size(),
        failedCases,
        pluginxx_ui_test::failureCount()
    );
    return pluginxx_ui_test::failureCount() == 0 ? 0 : 1;
}
