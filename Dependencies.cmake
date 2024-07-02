if(NOT TARGET fmtlib::fmtlib)
  cmake_fetch_content(fmt "https://github.com/fmtlib/fmt.git" 11.0.0)
endif()

if(NOT TARGET spdlog::spdlog)
  cmake_fetch_content(
    spdlog
    "https://github.com/gabime/spdlog.git"
    v1.14.1
    OPTIONS
    SPDLOG_FMT_EXTERNAL ON)
endif()

if(NOT TARGET Catch2::Catch2WithMain)
  cmake_fetch_content(fmt "https://github.com/catchorg/Catch2.git" 3.6.0)
endif()
