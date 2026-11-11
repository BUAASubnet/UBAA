#include "my_application.h"
#include <unistd.h>
#include <cstring>
#include <filesystem>
#include <vector>

int main(int argc, char** argv) {
  if (argc > 1 && std::strcmp(argv[1], "--command") == 0) {
    const auto command = std::filesystem::canonical("/proc/self/exe").parent_path() / "ubaa-cli";
    std::vector<char*> arguments;
    auto path = command.string();
    arguments.push_back(path.data());
    for (int i = 2; i < argc; ++i) arguments.push_back(argv[i]);
    arguments.push_back(nullptr);
    execv(path.c_str(), arguments.data());
    return 7;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
