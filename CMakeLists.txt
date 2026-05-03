cmake_minimum_required(VERSION 3.14.0)
project(while VERSION 0.1.0 LANGUAGES CXX)


set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Bygg med: cmake -DCODE_COVERAGE=ON -DCMAKE_CXX_COMPILER=clang++ ..
option(CODE_COVERAGE "Enable coverage instrumentation" OFF)
if(CODE_COVERAGE)
  message(STATUS "Code coverage enabled")
  set(COVERAGE_FLAGS "-fprofile-instr-generate -fcoverage-mapping -O0 -g")
  set(CMAKE_CXX_FLAGS        "${CMAKE_CXX_FLAGS}        ${COVERAGE_FLAGS}")
  set(CMAKE_C_FLAGS          "${CMAKE_C_FLAGS}          ${COVERAGE_FLAGS}")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${COVERAGE_FLAGS}")
endif()

set(TRIESTE_BUILD_SAMPLES OFF)

include(FetchContent)

set(CLANG_FORMAT CLANG_FORMAT-NOTFOUND)


set(SNMALLOC_USE_CXX17 ON CACHE BOOL "" FORCE)
set(SNMALLOC_BUILD_TESTING OFF)
FetchContent_Declare(
  snmalloc
  GIT_REPOSITORY https://github.com/microsoft/snmalloc
  GIT_TAG        b8e28be14b3fd98e27c2fe87c0296570f6d3990e
)
FetchContent_MakeAvailable(snmalloc)

FetchContent_Declare(
  trieste
  GIT_REPOSITORY https://github.com/microsoft/Trieste
  GIT_TAG main
)
FetchContent_MakeAvailable(trieste)

macro(clangformat_targets)
endmacro()

FetchContent_Declare(
  vbc
  GIT_REPOSITORY https://github.com/sylvanc/verona-bc
  GIT_TAG 19944ae71191f2f242b52cf0eb5a9f745536e313
)
FetchContent_MakeAvailable(vbc)

find_package(PkgConfig REQUIRED)
pkg_check_modules(FFI REQUIRED libffi)

add_library(while_lib SHARED
  src/lib.cc
)

add_executable(while
  src/while.cc
  src/parser.cc
  src/reader.cc
  src/optimization_analysis.cc
  src/compiler.cc
  src/inlining_rewriter.cc

  src/utils.cc
  src/analyses/utils.cc
  src/control_flow.cc

  src/passes/generate_mermaid.cc

  src/passes/functions.cc
  src/passes/expressions.cc
  src/passes/statements.cc
  src/passes/check_refs.cc

  src/passes/unique_variables.cc
  src/passes/gather_stats.cc
  src/passes/normalization.cc
  src/passes/gather_control_flow.cc
  src/passes/zero_analysis.cc
  src/passes/constant_folding.cc
  src/passes/dead_code_elimination.cc

  src/passes/to3addr.cc
  src/passes/gather_vars.cc
  src/passes/blockify.cc
  src/passes/compile.cc

  src/passes/build_call_graph.cc
  src/passes/inlining.cc
)

add_executable(while_trieste
  src/while_trieste.cc
  src/parser.cc

  src/utils.cc

  src/passes/functions.cc
  src/passes/expressions.cc
  src/passes/statements.cc
  src/passes/check_refs.cc
  src/passes/unique_variables.cc
  src/passes/gather_stats.cc
  src/passes/normalization.cc

  src/passes/to3addr.cc
  src/passes/gather_vars.cc
  src/passes/blockify.cc
  src/passes/compile.cc
)

target_link_libraries(while
  CLI11::CLI11
  trieste::trieste
  vbc::include
)

target_link_libraries(while_trieste
  CLI11::CLI11
  trieste::trieste
  vbc::include
)

# Disable testsuite - requires a newer trieste cmake module
enable_testing()
add_subdirectory(testsuite)