#pragma once

/// 极简测试框架（不引入第三方依赖）
///
/// 用法：
/// ```cpp
/// PLUGINXX_UI_TEST(解析基本组件) {
///     PLUGINXX_UI_CHECK(cond, "失败说明");
///     PLUGINXX_UI_CHECK_EQ(actual, expected, "失败说明");
/// }
/// ```
/// 测试在 test_main.cpp 里自动收集并逐个运行。
#include <cstdio>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace pluginxx_ui_test {

struct Case {
    std::string           name;
    std::function<void()> body;
};

inline std::vector<Case>& registry() {
    static std::vector<Case> cases;
    return cases;
}

inline int& failureCount() {
    static int failures = 0;
    return failures;
}

inline const char*& currentCase() {
    static const char* name = "";
    return name;
}

inline void report(bool ok, const std::string& message, const char* file, const int line) {
    if (!ok) {
        ++failureCount();
        std::printf("  [FAIL] %s (%s:%d)\n", message.c_str(), file, line);
    }
}

struct Registrar {
    Registrar(const char* name, std::function<void()> body) {
        registry().push_back(Case{name, std::move(body)});
    }
};

/// 读取夹具文件（路径由 CMake 以 PLUGINXX_UI_FIXTURES_DIR 传入）
std::string readFixture(const std::string& name);

} // namespace pluginxx_ui_test

#define PLUGINXX_UI_TEST(name)                                                       \
    static void pluginxx_ui_test_##name();                                           \
    static pluginxx_ui_test::Registrar pluginxx_ui_test_reg_##name(                  \
        #name, pluginxx_ui_test_##name                                              \
    );                                                                               \
    static void pluginxx_ui_test_##name()

#define PLUGINXX_UI_CHECK(cond, message)                                             \
    pluginxx_ui_test::report(static_cast<bool>(cond), message, __FILE__, __LINE__)

#define PLUGINXX_UI_CHECK_EQ(actual, expected, message)                              \
    do {                                                                             \
        const auto& _a = (actual);                                                   \
        const auto& _e = (expected);                                                 \
        pluginxx_ui_test::report(_a == _e, std::string(message), __FILE__, __LINE__); \
        if (!(_a == _e)) {                                                           \
            std::printf("         actual  : %s\n", pluginxx_ui_test::describe(_a).c_str()); \
            std::printf("         expected: %s\n", pluginxx_ui_test::describe(_e).c_str()); \
        }                                                                            \
    } while (false)

namespace pluginxx_ui_test {

inline std::string describe(const std::string& value) {
    return value;
}

inline std::string describe(const char* value) {
    return value == nullptr ? "(null)" : std::string(value);
}

inline std::string describe(const std::string_view value) {
    return std::string(value);
}

inline std::string describe(const bool value) {
    return value ? "true" : "false";
}

inline std::string describe(const int value) {
    return std::to_string(value);
}

inline std::string describe(const unsigned long value) {
    return std::to_string(value);
}

inline std::string describe(const unsigned long long value) {
    return std::to_string(value);
}

inline std::string describe(const double value) {
    return std::to_string(value);
}

} // namespace pluginxx_ui_test
