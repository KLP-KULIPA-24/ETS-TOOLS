cmake_minimum_required(VERSION 3.14)
project(ets_inject LANGUAGES ASM_MASM C CXX)

# 产物名必须是 winmm.dll：Chromium/CEF 运行时会动态加载 winmm，
# DLL 搜索顺序里应用目录（ETS 安装目录）优先于 System32，
# 因此把本代理 DLL 放在 ETS 目录即可被侧加载。
# 转发桩由 tools/inject/gen_winmm_proxy.py 从系统 winmm.dll 自动生成。

add_compile_definitions(UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
add_compile_options(/utf-8 /W3 /EHsc)

add_library(winmm SHARED
  payload.cpp
  winmm_forward.cpp
  winmm_forward.asm
  winmm_forward.def
  minhook/hook.c
  minhook/buffer.c
  minhook/trampoline.c
  minhook/hde/hde32.c
  minhook/hde/hde64.c
)

# MASM 默认给 stdcall 过程名加下划线装饰，与 .def 里的导出名对不上
set_source_files_properties(winmm_forward.asm PROPERTIES COMPILE_OPTIONS "/Zp1")

target_include_directories(winmm PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/minhook
  ${CMAKE_CURRENT_SOURCE_DIR}/cef_root
  ${CMAKE_CURRENT_SOURCE_DIR}/cef_root/include
)

set_target_properties(winmm PROPERTIES
  PREFIX ""
  OUTPUT_NAME "winmm"
  SUFFIX ".dll"
)

target_compile_features(winmm PRIVATE cxx_std_17)
target_link_libraries(winmm PRIVATE user32 kernel32 ws2_32)

# 二分定位开关：1=只做 winmm 转发，2=+LoadLibrary IAT 钩，3=全开(默认)
if(NOT DEFINED ETS_STAGE)
  set(ETS_STAGE 3)
endif()
target_compile_definitions(winmm PRIVATE ETS_STAGE=${ETS_STAGE})