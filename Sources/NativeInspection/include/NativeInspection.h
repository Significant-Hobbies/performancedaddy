#pragma once
#include "ShellProbe.h"
#include <stdint.h>
typedef struct {
    int32_t pid, parent;
    uint32_t uid;
    uint64_t started, cpu, memory;
    uint64_t footprint, read_bytes, written_bytes;
    int resource_available, has_terminal;
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
