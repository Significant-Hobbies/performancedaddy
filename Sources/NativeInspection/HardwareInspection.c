// Read-only adapter informed by MIT Stats, macmon and Mac Performance Monitor.
// See ThirdPartyNotices.md. No SMC write command or fan-control operation exists.
#include "NativeInspection.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVersion version; SMCLimits limits; SMCKeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} SMCParam;
_Static_assert(sizeof(SMCParam) == 80, "SMC transport ABI");
struct PDHardwareReader { io_connect_t connection; pthread_mutex_t lock; uint32_t keys[128]; int domains[128]; SMCKeyInfo info[128]; int count; time_t discovery; };
#define FOUR(a,b,c,d) ((uint32_t)(a)<<24 | (uint32_t)(b)<<16 | (uint32_t)(c)<<8 | (uint32_t)(d))

double pd_smc_decode(uint32_t type, const uint8_t *bytes, uint32_t size) {
    if (!bytes) return NAN;
    double value = NAN;
    if (type == FOUR('f','l','t',' ') && size == 4) { uint32_t bits = bytes[0] | ((uint32_t)bytes[1]<<8) | ((uint32_t)bytes[2]<<16) | ((uint32_t)bytes[3]<<24); float f; memcpy(&f, &bits, 4); value = f; }
    else if (type == FOUR('u','i','8',' ') && size == 1) value = bytes[0];
    else if (type == FOUR('u','i','1','6') && size == 2) value = ((uint16_t)bytes[0]<<8) | bytes[1];
    else if (type == FOUR('u','i','3','2') && size == 4) value = ((uint32_t)bytes[0]<<24) | ((uint32_t)bytes[1]<<16) | ((uint32_t)bytes[2]<<8) | bytes[3];
    else if (type == FOUR('f','p','e','2') && size == 2) value = (((uint16_t)bytes[0]<<8) | bytes[1]) / 4.0;
    else if (type == FOUR('s','p','7','8') && size == 2) value = (int16_t)(((uint16_t)bytes[0]<<8) | bytes[1]) / 256.0;
    else if (type == FOUR('i','o','f','t') && size == 8) { uint64_t v = 0; for (int i=7; i>=0; --i) v = (v<<8) | bytes[i]; value = (double)v / 65536.0; }
    return isfinite(value) ? value : NAN;
}
static int call(PDHardwareReader *reader, SMCParam *in, SMCParam *out) {
    if (!reader->connection) return 0;
    size_t size = sizeof(*out); memset(out,0,sizeof(*out));
    return IOConnectCallStructMethod(reader->connection,2,in,sizeof(*in),out,&size) == KERN_SUCCESS && size == sizeof(*out) && out->result == 0;
}
static int metadata(PDHardwareReader *r, uint32_t key, SMCKeyInfo *info) {
    SMCParam in={0},out; in.key=key; in.command=9;
    if (!call(r,&in,&out) || !out.info.size || out.info.size>32) return 0;
    *info=out.info; return 1;
}
static double read_key(PDHardwareReader *r, uint32_t key, SMCKeyInfo *cached) {
    SMCKeyInfo info; if (cached) info=*cached; else if (!metadata(r,key,&info)) return NAN;
    SMCParam in={0},out; in.key=key; in.command=5; in.info=info;
    return call(r,&in,&out) ? pd_smc_decode(info.type,out.bytes,info.size) : NAN;
}
PDHardwareReader *pd_hardware_create(void) {
    PDHardwareReader *r=calloc(1,sizeof(*r)); if (!r) return NULL;
    pthread_mutex_init(&r->lock,NULL);
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMCKeysEndpoint"));
    if (!service) service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
    if (service) { IOServiceOpen(service,mach_task_self(),0,&r->connection); IOObjectRelease(service); }
    return r;
}
void pd_hardware_destroy(PDHardwareReader *r) { if (!r) return; if (r->connection) IOServiceClose(r->connection); pthread_mutex_destroy(&r->lock); free(r); }
static void discover(PDHardwareReader *r) {
    time_t now=time(NULL); if (r->discovery && now>=r->discovery && now-r->discovery<300) return;
    r->discovery=now; r->count=0;
    double count=read_key(r,FOUR('#','K','E','Y'),NULL);
    if (!isfinite(count) || count<1 || count>8192 || floor(count)!=count) return;
    for (uint32_t i=0; i<(uint32_t)count && r->count<128; i++) {
        SMCParam in={0},out; in.command=8; in.index=i;
        if (!call(r,&in,&out)) continue;
        unsigned a=out.key>>24, b=(out.key>>16)&255;
        int domain=a=='T' && (b=='p' || b=='e') ? 1 : a=='T' && b=='g' ? 2 : 0;
        if (out.key==FOUR('T','C','0','P')) domain=1;
        if (!domain) continue;
        SMCKeyInfo info; if (!metadata(r,out.key,&info)) continue;
        r->keys[r->count]=out.key; r->domains[r->count]=domain; r->info[r->count]=info; r->count++;
    }
}
static double gpu_utilization(void) {
    io_iterator_t iterator=0; double maximum=NAN;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOAccelerator"),&iterator)!=KERN_SUCCESS) return NAN;
    io_service_t service; int count=0;
    while ((service=IOIteratorNext(iterator))) {
        if (++count>16) { IOObjectRelease(service); break; }
        CFTypeRef property=IORegistryEntryCreateCFProperty(service,CFSTR("PerformanceStatistics"),kCFAllocatorDefault,0);
        if (property && CFGetTypeID(property)==CFDictionaryGetTypeID()) {
            CFTypeRef value=CFDictionaryGetValue((CFDictionaryRef)property,CFSTR("Device Utilization %")); double percent;
            if (value && CFGetTypeID(value)==CFNumberGetTypeID() && CFNumberGetValue(value,kCFNumberDoubleType,&percent) && isfinite(percent) && percent>=0 && percent<=100)
                maximum=isnan(maximum) ? percent : fmax(maximum,percent);
        }
        if (property) CFRelease(property); IOObjectRelease(service);
    }
    IOObjectRelease(iterator); return maximum;
}
void pd_hardware_read(PDHardwareReader *r, PDHardware *out) {
    memset(out,0,sizeof(*out)); out->fan_count=-1;
    out->cpu_sensor_max_celsius=out->gpu_sensor_max_celsius=out->gpu_percent=NAN;
    for (int i=0;i<10;i++) out->fan_rpm[i]=out->fan_max_rpm[i]=NAN;
    if (!r) return;
    pthread_mutex_lock(&r->lock);
    double fans=read_key(r,FOUR('F','N','u','m'),NULL);
    if (isfinite(fans) && fans>=0 && fans<=10 && floor(fans)==fans) {
        out->fan_count=(int)fans;
        for (int i=0;i<out->fan_count;i++) {
            double rpm=read_key(r,FOUR('F','0'+i,'A','c'),NULL), max=read_key(r,FOUR('F','0'+i,'M','x'),NULL);
            if (isfinite(rpm) && rpm>=0 && rpm<=30000) out->fan_rpm[i]=rpm;
            if (isfinite(max) && max>0 && max<=30000) out->fan_max_rpm[i]=max;
        }
    }
    discover(r);
    for (int i=0;i<r->count;i++) {
        double temperature=read_key(r,r->keys[i],&r->info[i]);
        if (!isfinite(temperature) || temperature<=0 || temperature>150) continue;
        double *maximum=r->domains[i]==1 ? &out->cpu_sensor_max_celsius : &out->gpu_sensor_max_celsius;
        if (isnan(*maximum) || temperature>*maximum) *maximum=temperature;
        if (r->domains[i]==1) out->cpu_sensor_count++; else out->gpu_sensor_count++;
    }
    out->gpu_percent=gpu_utilization(); pthread_mutex_unlock(&r->lock);
}
