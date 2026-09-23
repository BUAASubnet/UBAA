// 读取 macOS 或 iOS 模拟器宿主进程的内核创建时间，不以命令发起时间代替。
#include <errno.h>
#include <libproc.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char *end = NULL;
    errno = 0;
    long pid = strtol(argv[1], &end, 10);
    if (errno || !end || *end || pid <= 0 || pid > INT_MAX) return 2;
    struct proc_bsdinfo info = {0};
    int size = proc_pidinfo((int)pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (size != sizeof(info) || info.pbi_start_tvsec == 0) return 1;
    uint64_t micros = info.pbi_start_tvsec * 1000000ULL + info.pbi_start_tvusec;
    printf("%llu\n", (unsigned long long)micros);
    return 0;
}
