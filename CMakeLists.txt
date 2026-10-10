# ===== cxx_pluginxx_ui: 插件界面描述层（与渲染器无关） =====
#
# 定位: 插件不写界面代码, 只交一份 JSON 声明; 本库负责
#   模型(item.h) / 解析(parse) / 降级适配(adapt) / 纯文本降级(plain_text) /
#   构建器(build.h) / kit 展开(kit_runtime) / 能力段(capabilities) / 开发期检查(lint)
# 同一份描述经 adapt(caps) 后既能渲染到终端(列/行), 也能渲染到 GUI(逻辑像素)。
#
# 依赖: cxx_utilxx_base (JSON/日志/字符串) + fmt; **不含渲染**(没有 FTXUI / Flutter)
#
# 产物 (命名规则: Release 无后缀, Debug 文件名追加 d):
#   Release: libcxx_pluginxx_ui_static.a
#   Debug:   libcxx_pluginxx_ui_staticd.a
# 另有 INTERFACE 目标 cxx_pluginxx_ui (只要头文件时用它, 例如插件侧构建组件项)
#
# 使用 (处理方):
#   find_package(cxx_pluginxx_ui REQUIRED)
#   target_link_libraries(<your_target> PRIVATE cxx_pluginxx_ui_static)

cmake_minimum_required(VERSION 3.10)
cmake_policy(SET CMP0074 NEW)
cmake_policy(SET CMP0091 NEW)
cmake_policy(SET CMP0144 NEW)
cmake_policy(SET CMP0167 OLD)

set(PLUGINXX_UI_PROJECT_VERSION "0.1.0")
project(cxx_pluginxx_ui VERSION ${PLUGINXX_UI_PROJECT_VERSION} LANGUAGES CXX)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if (XX_IS_MSVC_D)
  list(PREPEND CMAKE_FIND_LIBRARY_SUFFIXES .lib .a)
else ()
  list(PREPEND CMAKE_FIND_LIBRARY_SUFFIXES .a)
endif ()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/xx_platform_macros.cmake")
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/xx_rpath.cmake")

# 库产物安装目录: 嵌套构建时由顶层 superbuild 传入, 独立构建时随标准库目录
if (NOT DEFINED XX_EXEC_INSTALL_PREFIX)
  set(XX_EXEC_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")
endif ()

option(CXX_PLUGINXX_UI_BUILD_TESTS "构建本库的单元测试" ON)

# 依赖库的依赖先于依赖库自身查找: cxx_utilxx_base 的导出接口以目标名
# PkgConfig::uring 声明 io_uring (其构建开关 CXX_UTILXX_BASE_LINUX_IO_URING_SUPPORTED
# 与顶层 XX_LINUX_IO_URING_SUPPORTED 同源, superbuild 同时下发给两者);
# 缺少这一步时 find_package(cxx_utilxx_base) 会报 "PkgConfig::uring target not found"
find_package(PkgConfig REQUIRED)
if (XX_LINUX_IO_URING_SUPPORTED)
  pkg_check_modules(uring REQUIRED IMPORTED_TARGET liburing)
endif ()
find_package(fmt REQUIRED)
find_package(cxx_utilxx_base REQUIRED)

set(_CXX_PLUGINXX_UI_SOURCES
  src/adapt.cpp
  src/item.cpp
  src/kit_runtime.cpp
  src/lint.cpp
  src/parse.cpp
  src/plain_text.cpp
)

# 只依赖头文件的使用方 (插件侧构建组件项、只要能力表) 用这个目标
add_library(cxx_pluginxx_ui INTERFACE)
# 需要解析/适配/文本降级的客户端用这个目标
add_library(cxx_pluginxx_ui_static STATIC ${_CXX_PLUGINXX_UI_SOURCES})

if (XX_IS_DEBUG_D)
  set_target_properties(cxx_pluginxx_ui_static PROPERTIES OUTPUT_NAME "cxx_pluginxx_ui_staticd")
else ()
  set_target_properties(cxx_pluginxx_ui_static PROPERTIES OUTPUT_NAME "cxx_pluginxx_ui_static")
endif ()

set_target_properties(cxx_pluginxx_ui_static PROPERTIES
  PREFIX "lib"
  POSITION_INDEPENDENT_CODE ON
  CXX_STANDARD 26
  CXX_STANDARD_REQUIRED OFF
)

if (NOT XX_IS_MSVC_D)
  # GCC/Clang: 默认隐藏内部符号, 只导出 PLUGINXX_UI_API 标注的公开 API
  set_target_properties(cxx_pluginxx_ui_static PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
  )
endif ()

target_compile_definitions(cxx_pluginxx_ui_static PUBLIC CXX_PLUGINXX_UI_STATIC=1)

foreach (_t cxx_pluginxx_ui cxx_pluginxx_ui_static)
  if (XX_PLATFORM_COMPILE_DEFINITIONS)
    target_compile_definitions(${_t} INTERFACE ${XX_PLATFORM_COMPILE_DEFINITIONS})
  endif ()
endforeach ()
unset(_t)

target_include_directories(cxx_pluginxx_ui INTERFACE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)
target_include_directories(cxx_pluginxx_ui_static PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

# INTERFACE 目标只带头文件; 实现目标额外链依赖
target_link_libraries(cxx_pluginxx_ui INTERFACE cxx_utilxx_base_static)
target_link_libraries(cxx_pluginxx_ui_static PUBLIC cxx_utilxx_base_static fmt::fmt)

# ===== 单元测试 =====
if (CXX_PLUGINXX_UI_BUILD_TESTS)
  add_executable(cxx_pluginxx_ui_tests
    tests/test_main.cpp
    tests/test_parse.cpp
    tests/test_adapt.cpp
    tests/test_plain_text.cpp
    tests/test_kit.cpp
    tests/test_build.cpp
    tests/test_size.cpp
  )
  target_include_directories(cxx_pluginxx_ui_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests"
  )
  # 夹具路径 (fixtures/*.json) 传给测试, 避免相对路径依赖运行目录
  target_compile_definitions(cxx_pluginxx_ui_tests PRIVATE
    PLUGINXX_UI_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
  )
  target_link_libraries(cxx_pluginxx_ui_tests PRIVATE cxx_pluginxx_ui_static cxx_utilxx_base_static fmt::fmt)
  if (NOT XX_IS_MSVC_D)
    set_target_properties(cxx_pluginxx_ui_tests PROPERTIES INSTALL_RPATH "\$ORIGIN")
  endif ()
endif ()

# ===== 安装与导出 =====
install(TARGETS cxx_pluginxx_ui cxx_pluginxx_ui_static
  EXPORT cxx_pluginxx_uiTargets
  ARCHIVE DESTINATION "${XX_EXEC_INSTALL_PREFIX}"
  LIBRARY DESTINATION "${XX_EXEC_INSTALL_PREFIX}"
  RUNTIME DESTINATION "${XX_EXEC_INSTALL_PREFIX}"
)
install(DIRECTORY include/ DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")
# 生成器、schema、夹具与文档随库分发（重新生成/查定义时用）
install(DIRECTORY schema/ DESTINATION "${CMAKE_INSTALL_DATADIR}/cxx_pluginxx_ui/schema")
install(DIRECTORY tools/ DESTINATION "${CMAKE_INSTALL_DATADIR}/cxx_pluginxx_ui/tools")
install(DIRECTORY fixtures/ DESTINATION "${CMAKE_INSTALL_DATADIR}/cxx_pluginxx_ui/fixtures")
install(DIRECTORY js/ DESTINATION "${CMAKE_INSTALL_DATADIR}/cxx_pluginxx_ui/js")
install(EXPORT cxx_pluginxx_uiTargets
  NAMESPACE ""
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/cxx_pluginxx_ui"
)

configure_package_config_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/cxx_pluginxx_uiConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/cxx_pluginxx_uiConfig.cmake"
  INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/cxx_pluginxx_ui"
)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/cxx_pluginxx_uiConfig.cmake"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/cxx_pluginxx_ui"
)
