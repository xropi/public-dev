#include <filesystem>
#include <fstream>
#include <iostream>

namespace fs = std::filesystem;

// The ini sits next to the executable, and its directory is the config name --
// so unlike the parent sample there is nothing to bake in at configure time.
//
// argv[0] is enough for a sample launched by path. A real tool would read the
// executable's own location from the OS (/proc/self/exe on Linux,
// GetModuleFileNameW on Windows), since argv[0] is whatever the caller passed:
// a bare name when found via PATH, and outright forgeable.
static fs::path ini_path(const char* argv0) {
    fs::path exe = argv0;
    fs::path dir = exe.parent_path();
    if (dir.empty())
        dir = fs::current_path(); // invoked by bare name
    return dir / "x.ini";
}

int main(int argc, char** argv) {
    [[maybe_unused]] const int unused_argc = argc;

    const fs::path ini = ini_path(argv[0]);

    std::ifstream f(ini);
    if (!f)
        return std::cerr << "missing " << ini.string() << '\n', 1;

    std::cout << "--- " << ini.string() << " ---\n" << f.rdbuf();
    return 0;
}
