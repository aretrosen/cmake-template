cmake_minimum_required(VERSION 3.25)

# only set the cxx_standard if it is not set by someone else
if(NOT DEFINED CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 23)
endif()

set(CMAKE_CXX_EXTENSIONS OFF)

# Set the project name and language
project(
  the_project
  VERSION 0.0.1
  DESCRIPTION ""
  HOMEPAGE_URL ""
  # LANGUAGES CXX CUDA C ASM
  LANGUAGES CXX C)

# exit if source and build directory are same
get_filename_component(srcdir "${PROJECT_SOURCE_DIR}" REALPATH)
get_filename_component(bindir "${CMAKE_BINARY_DIR}" REALPATH)
if("${srcdir}" STREQUAL "${bindir}")
  message(FATAL_ERROR "Make a separate build directory. Ciao.")
endif()

include(CMakeDependentOption)
include(CheckCXXCompilerFlag)

# Link multiple library targets as system libraries (which suppresses their
# warnings).
function(target_link_system_libraries target)
  set(multiValueArgs INTERFACE PUBLIC PRIVATE)
  cmake_parse_arguments(
    ARG
    ""
    ""
    "${multiValueArgs}"
    ${ARGN})

  foreach(scope IN ITEMS INTERFACE PUBLIC PRIVATE)
    foreach(lib IN LISTS ARG_${scope})
      if(TARGET ${lib})
        get_target_property(lib_include_dirs ${lib} INTERFACE_INCLUDE_DIRECTORIES)
        if(lib_include_dirs)
          set(multiValueArgs INTERFACE PUBLIC PRIVATE)
          cmake_parse_arguments(
            ARG
            ""
            ""
            "${multiValueArgs}"
            ${ARGN})

          foreach(scope IN ITEMS INTERFACE PUBLIC PRIVATE)
            foreach(lib_include_dirs IN LISTS ARG_${scope})
              set(_SYSTEM SYSTEM)
              if(${scope} STREQUAL "INTERFACE" OR ${scope} STREQUAL "PUBLIC")
                target_include_directories(
                  ${target}
                  ${_SYSTEM}
                  ${scope}
                  "$<BUILD_INTERFACE:${lib_include_dirs}>"
                  "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")
              else()
                target_include_directories(
                  ${target}
                  ${_SYSTEM}
                  ${scope}
                  ${lib_include_dirs})
              endif()
            endforeach()
          endforeach()
        else()
          message(TRACE "${lib} library does not have the INTERFACE_INCLUDE_DIRECTORIES property.")
        endif()
      endif()

      target_link_libraries(${target} ${scope} ${lib})
    endforeach()
  endforeach()
endfunction()

option(PROJ_ENABLE_COVERAGE "Enable coverage reporting" OFF)
option(PROJ_ENABLE_HARDENING "Enable hardening" ON)

if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang|GNU")
  if(WIN32)
    set(SUPPORTS_UBSAN OFF)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_UBSAN ON)
    set(SUPPORTS_ASAN ON)
  endif()
endif()

if(NOT PROJECT_IS_TOP_LEVEL)
  option(PROJ_ENABLE_IPO "Enable IPO/LTO" OFF)
  option(PROJ_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
  option(PROJ_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
  option(PROJ_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
  option(PROJ_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
  option(PROJ_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
  option(PROJ_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
  option(PROJ_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
  option(PROJ_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
  option(PROJ_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
  option(PROJ_ENABLE_PCH "Enable precompiled headers" OFF)
  option(PROJ_ENABLE_CACHE "Enable ccache" OFF)
else()
  option(PROJ_ENABLE_IPO "Enable IPO/LTO" ON)
  option(PROJ_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
  option(PROJ_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
  option(PROJ_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" ON)
  option(PROJ_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
  option(PROJ_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
  option(PROJ_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
  option(PROJ_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
  option(PROJ_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
  option(PROJ_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
  option(PROJ_ENABLE_PCH "Enable precompiled headers" ON)
  option(PROJ_ENABLE_CACHE "Enable ccache" ON)
endif()

if(NOT PROJECT_IS_TOP_LEVEL)
  mark_as_advanced(
    PROJ_ENABLE_IPO
    PROJ_WARNINGS_AS_ERRORS
    PROJ_ENABLE_SANITIZER_ADDRESS
    PROJ_ENABLE_SANITIZER_LEAK
    PROJ_ENABLE_SANITIZER_UNDEFINED
    PROJ_ENABLE_SANITIZER_THREAD
    PROJ_ENABLE_SANITIZER_MEMORY
    PROJ_ENABLE_UNITY_BUILD
    PROJ_ENABLE_CLANG_TIDY
    PROJ_ENABLE_CPPCHECK
    PROJ_ENABLE_COVERAGE
    PROJ_ENABLE_PCH
    PROJ_ENABLE_CACHE)
endif()

# set fuzzing support
function(check_libfuzzer_support var_name)
  set(LibFuzzerTestSource
      "
#include <cstdint>

extern \"C\" int LLVMFuzzerTestOneInput(const std::uint8_t *data, std::size_t size) {
  return 0;
}
    ")

  include(CheckCXXSourceCompiles)

  set(CMAKE_REQUIRED_FLAGS "-fsanitize=fuzzer")
  set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=fuzzer")
  check_cxx_source_compiles("${LibFuzzerTestSource}" ${var_name})
endfunction()
check_libfuzzer_support(LIBFUZZER_SUPPORTED)
if(LIBFUZZER_SUPPORTED
   AND (PROJ_ENABLE_SANITIZER_ADDRESS
        OR PROJ_ENABLE_SANITIZER_THREAD
        OR PROJ_ENABLE_SANITIZER_UNDEFINED))
  set(DEFAULT_FUZZER ON)
else()
  set(DEFAULT_FUZZER OFF)
endif()
option(PROJ_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

# check ipo support
if(PROJ_ENABLE_IPO)
  include(CheckIPOSupported)
  check_ipo_supported(RESULT ipo_supported OUTPUT err_ipo_supported)
  if(ipo_supported)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
    message(STATUS "IPO is supported; enabled")
  else()
    message(SEND_ERROR "IPO is not supported: ${err_ipo_supported}")
  endif()
endif()

if(PROJ_ENABLE_HARDENING)
  macro(enable_hardening)
    if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang|GNU")
      set(NEW_CXX_DEFINITIONS "-D_GLIBCXX_ASSERTIONS")
      message(STATUS "GLIBC++ Assertions (vector[], string[], ...) enabled")

      set(NEW_COMPILE_OPTIONS "")
      set(NEW_LINK_OPTIONS "")

      if(NOT DEFINED CMAKE_BUILD_TYPE
         OR NOT
            CMAKE_BUILD_TYPE
            STREQUAL
            "Debug")
        list(
          APPEND
          NEW_COMPILE_OPTIONS
          "-U_FORTIFY_SOURCE"
          "-D_FORTIFY_SOURCE=3")
        message(STATUS "g++/clang _FORTIFY_SOURCE=3 enabled")
      endif()

      check_cxx_compiler_flag("-fstack-protector-strong" STACK_PROTECTOR)
      if(STACK_PROTECTOR)
        list(APPEND NEW_COMPILE_OPTIONS "-fstack-protector-strong")
        message(STATUS "g++/clang -fstack-protector-strong enabled")
      else()
        message(STATUS "g++/clang -fstack-protector-strong NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fcf-protection" CF_PROTECTION)
      if(CF_PROTECTION)
        list(APPEND NEW_COMPILE_OPTIONS "-fcf-protection=full")
        message(STATUS "g++/clang -fcf-protection enabled")
      else()
        message(STATUS "g++/clang -fcf-protection NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-mbranch-prediction=standard" BRANCH_PREDICTION)
      if(BRANCH_PREDICTION)
        list(APPEND NEW_COMPILE_OPTIONS "-mbranch-prediction=standard")
        message(STATUS "g++/clang -mbranch-prediction=standard enabled")
      else()
        message(STATUS "g++/clang -mbranch-prediction=standard NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fstrict-flex-arrays=3" FLEX_ARRAYS)
      if(FLEX_ARRAYS)
        list(APPEND NEW_COMPILE_OPTIONS "-fstrict-flex-arrays=3")
        message(STATUS "g++/clang -fstrict-flex-arrays enabled")
      else()
        message(STATUS "g++/clang -fstrict-flex-arrays NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fno-delete-null-pointer-checks" NO_DEL_NULL_POINTER)
      if(NO_DEL_NULL_POINTER)
        list(APPEND NEW_COMPILE_OPTIONS "-fno-delete-null-pointer-checks")
        message(STATUS "g++/clang -fno-delete-null-pointer-checks enabled")
      else()
        message(STATUS "g++/clang -fno-delete-null-pointer-checks NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fno-strict-overflow" NO_STRICT_OVERFLOW)
      if(NO_STRICT_OVERFLOW)
        list(APPEND NEW_COMPILE_OPTIONS "-fno-strict-overflow")
        message(STATUS "g++/clang -fno-strict-overflow enabled")
      else()
        message(STATUS "g++/clang -fno-strict-overflow NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fno-strict-aliasing" NO_STRICT_ALIASING)
      if(NO_STRICT_ALIASING)
        list(APPEND NEW_COMPILE_OPTIONS "-fno-strict-aliasing")
        message(STATUS "g++/clang -fno-strict-aliasing enabled")
      else()
        message(STATUS "g++/clang -fno-strict-aliasing NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-ftrivial-auto-var-init=zero" TRIVIAL_AUTO_VAR_INIT_ZERO)
      if(TRIVIAL_AUTO_VAR_INIT_ZERO)
        list(APPEND NEW_COMPILE_OPTIONS "-ftrivial-auto-var-init=zero")
        message(STATUS "g++/clang -ftrivial-auto-var-init=zero enabled")
      else()
        message(STATUS "g++/clang -ftrivial-auto-var-init=zero NOT enabled (not supported)")
      endif()

      # check_cxx_compiler_flag("-fPIE" FPIE)
      # if(FPIE)
      #   list(APPEND NEW_COMPILE_OPTIONS "-fPIE")
      #   message(STATUS "g++/clang -fPIE enabled")
      # else()
      #   message(STATUS "g++/clang -fPIE NOT enabled (not supported)")
      # endif()

      # check_cxx_compiler_flag("-pie" PIE)
      # if(PIE)
      #   list(APPEND NEW_COMPILE_OPTIONS "-pie")
      #   message(STATUS "g++/clang -pie enabled")
      # else()
      #   message(STATUS "g++/clang -pie NOT enabled (not supported)")
      # endif()

      # check_cxx_compiler_flag("-fPIC" FPIC)
      # if(FPIC)
      #   list(APPEND NEW_COMPILE_OPTIONS "-fPIC")
      #   message(STATUS "g++/clang -fPIC enabled")
      # else()
      #   message(STATUS "g++/clang -fPIC NOT enabled (not supported)")
      # endif()

      # check_cxx_compiler_flag("-shared" SHARED)
      # if(SHARED)
      #   list(APPEND NEW_LINK_OPTIONS "-shared")
      #   message(STATUS "g++/clang -shared enabled")
      # else()
      #   message(STATUS "g++/clang -shared NOT enabled (not supported)")
      # endif()

      check_cxx_compiler_flag("-fexceptions" F_EXCEPTIONS)
      if(F_EXCEPTIONS)
        list(APPEND NEW_COMPILE_OPTIONS "-fexceptions")
        message(STATUS "g++/clang -fexceptions enabled")
      else()
        message(STATUS "g++/clang -fexceptions NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fhardened" F_HARDENED)
      if(F_HARDENED)
        list(APPEND NEW_COMPILE_OPTIONS "-fhardened")
        message(STATUS "g++/clang -fhardened enabled")
      else()
        message(STATUS "g++/clang -fhardened NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-fstack-clash-protection" CLASH_PROTECTION)
      if(CLASH_PROTECTION)
        list(APPEND NEW_COMPILE_OPTIONS "-fstack-clash-protection")
        message(STATUS "g++/clang -fstack-clash-protection enabled")
      else()
        message(STATUS "g++/clang -fstack-clash-protection NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-Wl,-z,relro" RELRO)
      if(RELRO)
        list(APPEND NEW_LINK_OPTIONS "-Wl,-z,relro")
        message(STATUS "g++/clang -Wl,-z,relro enabled")
      else()
        message(STATUS "g++/clang -Wl,-z,relro NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-Wl,-z,now" NOW)
      if(NOW)
        list(APPEND NEW_LINK_OPTIONS "-Wl,-z,now")
        message(STATUS "g++/clang -Wl,-z,now enabled")
      else()
        message(STATUS "g++/clang -Wl,-z,now NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-Wl,-z,noexecstack" NOEXECSTACK)
      if(NOEXECSTACK)
        list(APPEND NEW_LINK_OPTIONS "-Wl,-z,noexecstack")
        message(STATUS "g++/clang -Wl,-z,noexecstack enabled")
      else()
        message(STATUS "g++/clang -Wl,-z,noexecstack NOT enabled (not supported)")
      endif()

      check_cxx_compiler_flag("-Wl,-z,nodlopen" NODLOPEN)
      if(NODLOPEN)
        list(APPEND NEW_LINK_OPTIONS "-Wl,-z,nodlopen")
        message(STATUS "g++/clang -Wl,-z,nodlopen enabled")
      else()
        message(STATUS "g++/clang -Wl,-z,nodlopen NOT enabled (not supported)")
      endif()
    endif()

    list(
      JOIN
      NEW_COMPILE_OPTIONS
      " "
      NEW_COMPILE_OPTIONS_LIST)
    list(
      JOIN
      NEW_LINK_OPTIONS
      " "
      NEW_LINK_OPTIONS_LIST)
    list(
      JOIN
      NEW_CXX_DEFINITIONS
      " "
      NEW_CXX_DEFINITIONS_LIST)

    message(STATUS "Hardening Compiler Flags: ${NEW_COMPILE_OPTIONS_LIST}")
    message(STATUS "Hardening Linker Flags: ${NEW_LINK_OPTIONS_LIST}")
    message(STATUS "Hardening Compiler Defines: ${NEW_CXX_DEFINITIONS_LIST}")

    message(STATUS "Setting hardening options globally for all dependencies")

    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${NEW_COMPILE_OPTIONS_LIST}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${NEW_LINK_OPTIONS_LIST}")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${NEW_CXX_DEFINITIONS_LIST}")
  endmacro()
  enable_hardening()
endif()

#fetch dependencies
include(FetchContent)
if(DEFINED ENV{FETCHCONTENT_BASE_DIR})
  set(FETCHCONTENT_BASE_DIR $ENV{FETCHCONTENT_BASE_DIR})
else()
  set(FETCHCONTENT_BASE_DIR "${CMAKE_BINARY_DIR}/_deps")
endif()
function(
  cmake_fetch_content
  NAME
  GIT_REPOSITORY
  GIT_TAG)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs OPTIONS)
  cmake_parse_arguments(
    ARG
    "${options}"
    "${oneValueArgs}"
    "${multiValueArgs}"
    ${ARGN})

  FetchContent_Declare(
    ${NAME}
    GIT_REPOSITORY ${GIT_REPOSITORY}
    GIT_TAG ${GIT_TAG}
    SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/${NAME})

  # Check if options are provided
  list(LENGTH ARG_OPTIONS NUM_OPTIONS)
  if(NUM_OPTIONS GREATER 0)
    # Ensure we have an even number of options (key-value pairs)
    math(EXPR IS_ODD "${NUM_OPTIONS} % 2")
    if(IS_ODD)
      message(FATAL_ERROR "Options for ${NAME} must be provided in key-value pairs")
    endif()

    math(EXPR LAST_OPTION "${NUM_OPTIONS} - 1")
    foreach(IDX RANGE 0 ${LAST_OPTION} 2)
      math(EXPR VALUE_IDX "${IDX} + 1")
      list(
        GET
        ARG_OPTIONS
        ${IDX}
        OPTION_NAME)
      list(
        GET
        ARG_OPTIONS
        ${VALUE_IDX}
        OPTION_VALUE)
      set(${OPTION_NAME}
          ${OPTION_VALUE}
          CACHE INTERNAL "")
    endforeach()
  endif()
  FetchContent_MakeAvailable(${NAME})
endfunction()
include(Dependencies.cmake)

# set build type
if(PROJECT_IS_TOP_LEVEL)
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Setting build type to 'RelWithDebInfo' as none was specified.")
    set(CMAKE_BUILD_TYPE
        RelWithDebInfo
        CACHE STRING "Choose the type of build." FORCE)
    set_property(
      CACHE CMAKE_BUILD_TYPE
      PROPERTY STRINGS
               "Debug"
               "Release"
               "MinSizeRel"
               "RelWithDebInfo")
  endif()

  set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

  if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
    if(WIN32)
      # On Windows cuda nvcc uses cl and not clang
      add_compile_options($<$<COMPILE_LANGUAGE:C>:-fcolor-diagnostics> $<$<COMPILE_LANGUAGE:CXX>:-fcolor-diagnostics>)
    else()
      add_compile_options(-fcolor-diagnostics)
    endif()
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    if(WIN32)
      # On Windows cuda nvcc uses cl and not gcc
      add_compile_options($<$<COMPILE_LANGUAGE:C>:-fdiagnostics-color=always>
                          $<$<COMPILE_LANGUAGE:CXX>:-fdiagnostics-color=always>)
    else()
      add_compile_options(-fdiagnostics-color=always)
    endif()
  else()
    message(STATUS "No colored compiler diagnostic set for '${CMAKE_CXX_COMPILER_ID}' compiler.")
  endif()

endif()

set(CLANG_WARNINGS
    -Wall
    -Wextra
    -Wshadow
    -Wnon-virtual-dtor
    -Wold-style-cast
    -Wcast-align
    -Wunused
    -Woverloaded-virtual
    -Wpedantic
    -pedantic
    -Wconversion
    -Wsign-conversion
    -Wnull-dereference
    -Wdouble-promotion
    -Wformat=2
    -Wimplicit-fallthrough)

set(GCC_WARNINGS
    ${CLANG_WARNINGS}
    -Wmisleading-indentation
    -Wduplicated-cond
    -Wduplicated-branches
    -Wlogical-op
    -Wuseless-cast
    -Wsuggest-override
    -Wtrampolines
    -Wnrvo
    -Wbidi-chars=any)

set(CUDA_WARNINGS
    -Wall
    -Wextra
    -Wunused
    -Wconversion
    -Wshadow)

if(PROJ_WARNINGS_AS_ERRORS)
  message(STATUS "All warnings will be treated as errors")
  list(APPEND CLANG_WARNINGS -Werror)
  list(APPEND GCC_WARNINGS -Werror)
else()
  message(STATUS "Only some warnings will be treated as errors")
  list(
    APPEND
    CLANG_WARNINGS
    -Werror=format-security
    -Werror=implicit
    -Werror=incompatible-pointer-types
    -Werror=int-conversion)
  list(
    APPEND
    GCC_WARNINGS
    -Werror=format-security
    -Werror=implicit
    -Werror=incompatible-pointer-types
    -Werror=int-conversion)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
  message(STATUS "Clang warnings set: '${CLANG_WARNINGS}'")
  set(PROJECT_WARNINGS_CXX ${CLANG_WARNINGS})
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GNU warnings set: ${GNU_WARNINGS}")
  set(PROJECT_WARNINGS_CXX ${GCC_WARNINGS})
else()
  message(AUTHOR_WARNING "No compiler warnings set for CXX compiler: '${CMAKE_CXX_COMPILER_ID}'")
endif()

# use the same warning flags for C
set(PROJECT_WARNINGS_C "${PROJECT_WARNINGS_CXX}")
set(PROJECT_WARNINGS_CUDA "${CUDA_WARNINGS}")

add_library(the_project_warnings INTERFACE)
add_library(the_project_options INTERFACE)

target_compile_options(
  the_project_warnings
  INTERFACE $<$<COMPILE_LANGUAGE:CXX>:${PROJECT_WARNINGS_CXX}> $<$<COMPILE_LANGUAGE:C>:${PROJECT_WARNINGS_C}>
            $<$<COMPILE_LANGUAGE:CUDA>:${PROJECT_WARNINGS_CUDA}>)

# set linker, mold by default
set(PROJ_LINKER_OPTION
    "mold"
    CACHE STRING "Linker to be used")
set(PROJ_LINKER_OPTION_VALUES "mold" "lld" "gold")
set_property(CACHE PROJ_LINKER_OPTION PROPERTY STRINGS ${PROJ_LINKER_OPTION_VALUES})
list(
  FIND
  PROJ_LINKER_OPTION_VALUES
  ${PROJ_LINKER_OPTION}
  PROJ_LINKER_OPTION_INDEX)

if(${PROJ_LINKER_OPTION_INDEX} EQUAL -1)
  message(
    STATUS "Using custom linker: '${PROJ_LINKER_OPTION}', explicitly supported entries are ${PROJ_LINKER_OPTION_VALUES}"
  )
endif()
set(LINKER_FLAG "-fuse-ld=${PROJ_LINKER_OPTION}")
check_cxx_compiler_flag(${LINKER_FLAG} CXX_SUPPORTS_PROJ_LINKER)
if(CXX_SUPPORTS_PROJ_LINKER)
  target_compile_options(the_project_options INTERFACE ${LINKER_FLAG})
endif()

# set sanitizers
if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang|GNU")
  set(SANITIZERS "")
  if(PROJ_ENABLE_SANITIZER_ADDRESS)
    list(APPEND SANITIZERS "address")
  endif()
  if(PROJ_ENABLE_SANITIZER_LEAK)
    list(APPEND SANITIZERS "leak")
  endif()
  if(PROJ_ENABLE_SANITIZER_UNDEFINED_BEHAVIOR)
    list(APPEND SANITIZERS "undefined")
  endif()
  if(PROJ_ENABLE_SANITIZER_THREAD)
    if(PROJ_ENABLE_SANITIZER_ADDRESS OR PROJ_ENABLE_SANITIZER_LEAK)
      message(WARNING "Thread sanitizer does not work with Address and Leak sanitizer enabled")
    else()
      list(APPEND SANITIZERS "thread")
    endif()
  endif()
  if(PROJ_ENABLE_SANITIZER_MEMORY AND CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
    message(
      WARNING
        "Memory sanitizer requires all the code (including libc++) to be MSan-instrumented otherwise it reports false positives"
    )
    if(PROJ_ENABLE_SANITIZER_ADDRESS
       OR PROJ_ENABLE_SANITIZER_LEAK
       OR PROJ_ENABLE_SANITIZER_THREAD)
      message(WARNING "Memory sanitizer does not work with Address, Thread or Leak sanitizer enabled")
    else()
      list(APPEND SANITIZERS "memory")
    endif()
  endif()

  list(
    JOIN
    SANITIZERS
    ","
    LIST_OF_SANITIZERS)
  if(LIST_OF_SANITIZERS
     AND NOT
         "${LIST_OF_SANITIZERS}"
         STREQUAL
         "")
    target_compile_options(the_project_options INTERFACE -fsanitize=${LIST_OF_SANITIZERS})
    target_link_options(the_project_options INTERFACE -fsanitize=${LIST_OF_SANITIZERS})
  endif()
endif()

set_target_properties(the_project_options PROPERTIES UNITY_BUILD ${PROJ_ENABLE_UNITY_BUILD})

if(PROJ_ENABLE_PCH)
  target_precompile_headers(
    the_project_options
    INTERFACE
    <array>
    <vector>
    <string>
    <utility>)
endif()

# set cmake cache
set(CACHE_OPTION
    "ccache"
    CACHE STRING "Compiler cache to be used")
set(CACHE_OPTION_VALUES "ccache" "sccache")
set_property(CACHE CACHE_OPTION PROPERTY STRINGS ${CACHE_OPTION_VALUES})
list(
  FIND
  CACHE_OPTION_VALUES
  ${CACHE_OPTION}
  CACHE_OPTION_INDEX)

if(${CACHE_OPTION_INDEX} EQUAL -1)
  message(
    STATUS
      "Using custom compiler cache system: '${CACHE_OPTION}', explicitly supported entries are ${CACHE_OPTION_VALUES}")
endif()

find_program(CACHE_BINARY NAMES ${CACHE_OPTION_VALUES})
if(CACHE_BINARY)
  message(STATUS "${CACHE_BINARY} found and enabled")
  set(CMAKE_CXX_COMPILER_LAUNCHER
      ${CACHE_BINARY}
      CACHE FILEPATH "CXX compiler cache used")
  set(CMAKE_C_COMPILER_LAUNCHER
      ${CACHE_BINARY}
      CACHE FILEPATH "C compiler cache used")
else()
  message(WARNING "${CACHE_OPTION} is enabled but was not found. Not using it")
endif()

if(PROJ_ENABLE_CLANG_TIDY)
  find_program(CLANGTIDY clang-tidy)
  if(CLANGTIDY)
    if(NOT
       CMAKE_CXX_COMPILER_ID
       MATCHES
       ".*Clang")

      get_target_property(TARGET_PCH the_project_options INTERFACE_PRECOMPILE_HEADERS)

      if("${TARGET_PCH}" STREQUAL "TARGET_PCH-NOTFOUND")
        get_target_property(TARGET_PCH the_project_options PRECOMPILE_HEADERS)
      endif()

      if(NOT ("${TARGET_PCH}" STREQUAL "TARGET_PCH-NOTFOUND"))
        message(
          SEND_ERROR
            "clang-tidy cannot be enabled with non-clang compiler and PCH, clang-tidy fails to handle gcc's PCH file")
      endif()
    endif()

    # construct the clang-tidy command line
    set(CLANG_TIDY_OPTIONS
        ${CLANGTIDY}
        -extra-arg=-Wno-unknown-warning-option
        -extra-arg=-Wno-ignored-optimization-argument
        -extra-arg=-Wno-unused-command-line-argument
        -p)
    # set standard
    if(NOT
       "${CMAKE_CXX_STANDARD}"
       STREQUAL
       "")
      if("${CLANG_TIDY_OPTIONS_DRIVER_MODE}" STREQUAL "cl")
        set(CLANG_TIDY_OPTIONS ${CLANG_TIDY_OPTIONS} -extra-arg=/std:c++${CMAKE_CXX_STANDARD})
      else()
        set(CLANG_TIDY_OPTIONS ${CLANG_TIDY_OPTIONS} -extra-arg=-std=c++${CMAKE_CXX_STANDARD})
      endif()
    endif()

    # set warnings as errors
    if(PROJ_WARNINGS_AS_ERRORS)
      list(APPEND CLANG_TIDY_OPTIONS -warnings-as-errors=*)
    endif()

    message("Also setting clang-tidy globally")
    set(CMAKE_CXX_CLANG_TIDY ${CLANG_TIDY_OPTIONS})
  else()
    message(${WARNING_MESSAGE} "clang-tidy requested but executable not found")
  endif()
endif()

if(PROJ_ENABLE_CPPCHECK)
  find_program(CPPCHECK cppcheck)
  if(CPPCHECK)

    set(CPPCHECK_TEMPLATE "gcc")

    if("${CPPCHECK_OPTIONS}" STREQUAL "")
      # Enable all warnings that are actionable by the user of this toolset
      # style should enable the other 3, but we'll be explicit just in case
      set(SUPPRESS_DIR "*:${CMAKE_CURRENT_BINARY_DIR}/_deps/*.h")
      message(STATUS "CPPCHECK_OPTIONS suppress: ${SUPPRESS_DIR}")
      set(CMAKE_CXX_CPPCHECK
          ${CPPCHECK}
          --template=${CPPCHECK_TEMPLATE}
          --enable=style,performance,warning,portability
          --inline-suppr
          --suppress=cppcheckError
          --suppress=internalAstError
          --suppress=unmatchedSuppression
          --suppress=passedByValue
          --suppress=syntaxError
          --suppress=preprocessorErrorDirective
          --inconclusive
          --suppress=${SUPPRESS_DIR})
    else()
      set(CMAKE_CXX_CPPCHECK ${CPPCHECK} --template=${CPPCHECK_TEMPLATE} ${CPPCHECK_OPTIONS})
    endif()

    if(NOT
       "${CMAKE_CXX_STANDARD}"
       STREQUAL
       "")
      set(CMAKE_CXX_CPPCHECK ${CMAKE_CXX_CPPCHECK} --std=c++${CMAKE_CXX_STANDARD})
    endif()
    if(PROJ_WARNINGS_AS_ERRORS)
      list(APPEND CMAKE_CXX_CPPCHECK --error-exitcode=2)
    endif()
  else()
    message(${WARNING_MESSAGE} "cppcheck requested but executable not found")
  endif()
endif()

if(PROJ_ENABLE_COVERAGE)
  if(CMAKE_CXX_COMPILER_ID MATCHES "*.Clang|GNU")
    target_compile_options(the_project_options INTERFACE --coverage -O0 -g)
    target_link_libraries(the_project_options INTERFACE --coverage)
  endif()
endif()

# don't know if this should be set globally from here or not...
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

find_program(GIT_EXECUTABLE git)
if(GIT_EXECUTABLE)
  set(GIT_SHA
      "Unknown"
      CACHE STRING "SHA this build was generated from")
  string(
    SUBSTRING "${GIT_SHA}"
              0
              8
              GIT_SHORT_SHA)
else()
  message(WARNING "Git not found")
endif()

target_compile_features(the_project_options INTERFACE cxx_std_${CMAKE_CXX_STANDARD})

add_library(the_project::the_project_options ALIAS the_project_options)
add_library(the_project::the_project_warnings ALIAS the_project_warnings)

# add src here
add_subdirectory(src)

# Don't even look at tests if we're not top level
if(NOT PROJECT_IS_TOP_LEVEL)
  return()
endif()

# Adding the tests:
include(CTest)

if(BUILD_TESTING)
  # add tests here add_subdirectory(test)
endif()

if(PROJ_BUILD_FUZZ_TESTS)
  if(NOT PROJ_ENABLE_SANITIZER_ADDRESS AND NOT PROJ_ENABLE_SANITIZER_THREAD)
    message(WARNING "You need asan or tsan enabled for meaningful fuzz testing")
  endif()
  # add fuzz tests here add_subdirectory(fuzz_test)

endif()

if(CMAKE_SKIP_INSTALL_RULES)
  return()
endif()
