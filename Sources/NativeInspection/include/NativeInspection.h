#pragma once
#include "ShellProbe.h"
#include <stdint.h>
typedef struct {
    int32_t pid, parent;
    uint32_t uid;
    uint64_t started, cpu, memory;
    uint64_t footprint, read_bytes, written_bytes;
    int resource_available, has_terminal, is_suspended;
    char name[256], path[4096], cwd[4096];
} PDProcess;
typedef struct {
    uint16_t port;
    int protocol, loopback;
    char address[64];
} PDPort;
int pd_process(int32_t pid, PDProcess *output);
// Read-only identity presence: 1 observed, 0 instance gone, -1 unknown.
int pd_presence(int32_t pid, uint64_t started);
int pd_ports(int32_t pid, PDPort *output, int capacity, int *incomplete);
int pd_signal(int32_t pid, uint64_t started, uint32_t uid, int force);

// Read-only hardware adapter. Undocumented driver fields are capability-checked.
typedef struct PDHardwareReader PDHardwareReader;
typedef struct {
    int fan_count;
    double fan_rpm[10], fan_max_rpm[10];
    double cpu_sensor_max_celsius, gpu_sensor_max_celsius, gpu_percent;
    int cpu_sensor_count, gpu_sensor_count;
} PDHardware;
PDHardwareReader *pd_hardware_create(void);
void pd_hardware_destroy(PDHardwareReader *reader);
void pd_hardware_read(PDHardwareReader *reader, PDHardware *out);
double pd_smc_decode(uint32_t type, const uint8_t *bytes, uint32_t size);
