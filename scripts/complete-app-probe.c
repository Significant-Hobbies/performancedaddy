#include <ApplicationServices/ApplicationServices.h>
#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    pid_t pid = (pid_t)atoi(argv[1]);
    struct rusage_info_v0 info = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V0, (rusage_info_t *)&info)) return 3;
    int visible = 0;
    CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windows) return 4;
    for (CFIndex i = 0; i < CFArrayGetCount(windows); i++) {
        CFDictionaryRef window = CFArrayGetValueAtIndex(windows, i);
        int owner = 0, layer = -1;
        CFNumberRef ownerValue = CFDictionaryGetValue(window, kCGWindowOwnerPID);
        CFNumberRef layerValue = CFDictionaryGetValue(window, kCGWindowLayer);
        if (ownerValue) CFNumberGetValue(ownerValue, kCFNumberIntType, &owner);
        if (layerValue) CFNumberGetValue(layerValue, kCFNumberIntType, &layer);
        if (owner == pid && layer == 0) visible++;
    }
    CFRelease(windows);
    printf("{\"residentBytes\":%llu,\"physicalFootprintBytes\":%llu,\"userTimeRaw\":%llu,\"systemTimeRaw\":%llu,\"packageIdleWakeups\":%llu,\"interruptWakeups\":%llu,\"startIdentity\":%llu,\"visibleWindows\":%d}\n",
        info.ri_resident_size, info.ri_phys_footprint, info.ri_user_time, info.ri_system_time,
        info.ri_pkg_idle_wkups, info.ri_interrupt_wkups, info.ri_proc_start_abstime, visible);
    return 0;
}
