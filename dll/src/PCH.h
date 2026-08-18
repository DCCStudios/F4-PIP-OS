#pragma once

#define _AMD64_

#pragma warning(push)
#include "F4SE/F4SE.h"
#include "RE/Fallout.h"
#include "REX/REX.h"
#pragma warning(pop)

#pragma warning(disable: 4100)
#pragma warning(disable: 4189)

#define DLLEXPORT __declspec(dllexport)

using namespace std::literals;

#include <array>
#include <cstdint>
#include <filesystem>
#include <format>
#include <fstream>
#include <source_location>
#include <string>
#include <string_view>
#include <utility>

// Logging shim over the multi-runtime CommonLib backend (mirrors the F4Parkour reference plugin).
namespace logger
{
    inline void info(std::string_view a_message)
    {
        REX::Impl::Log(std::source_location::current(), REX::ELogLevel::Info, a_message);
    }
    inline void error(std::string_view a_message)
    {
        REX::Impl::Log(std::source_location::current(), REX::ELogLevel::Error, a_message);
    }
    inline void critical(std::string_view a_message)
    {
        REX::Impl::Log(std::source_location::current(), REX::ELogLevel::Critical, a_message);
    }
    template <class... Args>
    void info(std::format_string<Args...> a_format, Args&&... a_args)
    {
        REX::Impl::Log(std::source_location::current(), REX::ELogLevel::Info, a_format, std::forward<Args>(a_args)...);
    }
}
