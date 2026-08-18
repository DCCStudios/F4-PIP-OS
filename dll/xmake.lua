-- PIP-OS Pip-Boy companion F4SE plugin (OG 1.10.163 only).
-- Reuses the workspace's CommonLibF4 checkout (same one S2 HUD Rework / FOV Slider use).
includes("../../FOV Slider F4SE/lib/commonlibf4")

set_project("PipOSPipboy")
set_version("1.0.0")
set_license("MIT")
set_languages("c++23")
set_warnings("allextra")
set_encodings("utf-8")
set_allowedarchs("windows|x64")
set_allowedmodes("debug", "releasedbg")
set_defaultarchs("windows|x64")
set_defaultmode("releasedbg")

add_rules("mode.debug", "mode.releasedbg")

-- OG-only per locked decision (MagnumOpus targets 1.10.163). Single runtime slot.
add_defines("COMMONLIB_RUNTIMECOUNT=1")

target("PipOSPipboy", function()
    add_rules("commonlibf4.plugin", {
        name = "PipOSPipboy",
        author = "Robert",
        description = "PIP-OS Pip-Boy companion: per-tab page-mode bridge + live character capture.",
        plugin_template = path.join(os.projectdir(), "res/commonlibf4-plugin.cpp.in"),
    })
    add_files("src/**.cpp")
    add_headerfiles("src/**.h")
    add_includedirs("src")
    add_defines("_UNICODE", "UNICODE", "NOMINMAX", "_CRT_SECURE_NO_WARNINGS")
    set_pcxxheader("src/PCH.h")
    set_runtimes("MD")
    set_symbols("debug")
    set_optimize("fastest")
    set_targetdir("Compile/F4SE/Plugins")
end)
