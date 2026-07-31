#include <fstream>
#include <iostream>

int main() {
    // INI_PATH is the binary root, baked in by CMakeLists.txt
    std::ifstream f(INI_PATH);
    if (!f)
        return std::cerr << "missing " << INI_PATH << '\n', 1;

    std::cout << "--- " INI_PATH " ---\n" << f.rdbuf();
    return 0;
}
