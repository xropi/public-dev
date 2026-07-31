#include <fstream>
#include <iostream>
int main() {
    std::ifstream f(INI_PATH);
    if (!f) return std::cerr << "missing " << INI_PATH << '\n', 1;
    std::cout << "--- " INI_PATH " ---\n" << f.rdbuf();
    return 0;
}
