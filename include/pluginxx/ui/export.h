#pragma once

/// 动态库导出宏
///
/// - 静态链接本库的使用方由 CMake 目标自动带上 `CXX_PLUGINXX_UI_STATIC`（此时宏为空）
/// - 构建动态库时定义 `CXX_PLUGINXX_UI_EXPORTS`
/// - GCC/Clang 用 visibility("default")（构建时默认隐藏其余符号）
#if defined(_WIN32) || defined(__CYGWIN__)
#  if defined(CXX_PLUGINXX_UI_STATIC)
#    define PLUGINXX_UI_API
#  elif defined(CXX_PLUGINXX_UI_EXPORTS)
#    define PLUGINXX_UI_API __declspec(dllexport)
#  else
#    define PLUGINXX_UI_API __declspec(dllimport)
#  endif
#elif defined(__GNUC__) || defined(__clang__)
#  define PLUGINXX_UI_API __attribute__((visibility("default")))
#else
#  define PLUGINXX_UI_API
#endif
