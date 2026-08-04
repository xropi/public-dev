#include <fstream>
#include <iostream>
static int show(const char* path) {
    std::ifstream f(path);
    if (!f) return std::cerr << "missing " << path << '\n', 1;
    std::cout << "--- " << path << " ---\n" << f.rdbuf();
    return 0;
}
int main() {
    // the staged directory is proof only if the nested file came along too
    return show(INI_PATH) | show(ASSET_DIR "/greeting.txt")
         | show(ASSET_DIR "/nested/deep.txt");
}
