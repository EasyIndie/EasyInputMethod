#include "ime.h"
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

static double footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
        return -1;
    return info.phys_footprint / 1048576.0;
}
static double now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}
static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
int main(int argc, char **argv) {
    if (argc != 5 && argc != 6) return 2;
    int count = argc == 6 ? atoi(argv[5]) : 1;
    if (count < 1 || count > 16 || ime_config_init(argv[4]) != IME_OK) return 2;
    ImeSession *sessions[16];
    for (int i = 0; i < count; i++) {
        sessions[i] = ime_session_new_with_data(argv[1], strcmp(argv[2], "-") ? argv[2] : NULL,
                                               strcmp(argv[3], "-") ? argv[3] : NULL);
        if (!sessions[i]) {
            for (int j = 0; j < i; j++) ime_session_free(sessions[j]);
            return 3;
        }
    }
    printf("sessions=%d loaded_footprint_mib=%.2f\n", count, footprint());
    double values[5000];
    int samples = 0;
    const char *inputs[] = {"wq", "nihao", "zhongguo", "zz", "a", "kwwl"};
    for (int round = 0; round < 100; round++) {
        ImeSession *session = sessions[round % count];
        if (round % 10 == 0) printf("round=%d footprint=%.2f\n", round, footprint());
        for (int j = 0; j < 6; j++) {
            ime_session_reset(session);
            for (const char *key = inputs[j]; *key; key++) {
                double start = now();
                if (ime_session_configure(session) != IME_OK || ime_session_key(session, *key) < 0)
                    return 4;
                values[samples++] = (now() - start) * 1000;
            }
        }
    }
    qsort(values, samples, sizeof(double), compare);
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    printf("keys=%d p50_ms=%.3f p95_ms=%.3f max_ms=%.3f peak_rss_mib=%.2f\n", samples,
           values[samples / 2], values[samples * 95 / 100], values[samples - 1], usage.ru_maxrss / 1048576.0);
    printf("steady_footprint_mib=%.2f\n", footprint());
    for (int i = 0; i < count; i++) ime_session_free(sessions[i]);
    return 0;
}
