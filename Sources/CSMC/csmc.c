#include "csmc.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>

// Layout of the AppleSMC user client struct (selector 2). Not public API; must match the kernel exactly.
typedef struct { char major, minor, build, reserved; UInt16 release; } vers_t;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } plimit_t;
typedef struct { UInt32 dataSize; UInt32 dataType; char dataAttributes; } keyinfo_t;
typedef struct {
    UInt32 key; vers_t vers; plimit_t pLimitData; keyinfo_t keyInfo;
    char result; char status; char data8; UInt32 data32; unsigned char bytes[32];
} smc_t;

enum { CMD_READ = 5, CMD_WRITE = 6, CMD_KEY_AT = 8, CMD_INFO = 9 };

static io_connect_t conn;

static int call(smc_t *in, smc_t *out) {
    size_t sz = sizeof(smc_t);
    memset(out, 0, sizeof *out);
    kern_return_t kr = IOConnectCallStructMethod(conn, 2, in, sizeof(smc_t), out, &sz);
    return (kr == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS ? 0 : -1;
}

int smc_read(uint32_t key, uint8_t *bytes, uint32_t size) {
    smc_t in = {0}, out;
    if (size > 32) return -1;
    in.key = key; in.keyInfo.dataSize = size; in.data8 = CMD_READ;
    if (call(&in, &out)) return -1;
    memcpy(bytes, out.bytes, size);
    return 0;
}

int smc_write(uint32_t key, const uint8_t *bytes, uint32_t size) {
    smc_t in = {0}, out;
    if (size > 32) return -1;
    in.key = key; in.keyInfo.dataSize = size; in.data8 = CMD_WRITE;
    memcpy(in.bytes, bytes, size);
    return call(&in, &out);
}

int smc_info(uint32_t key, uint32_t *type, uint32_t *size) {
    smc_t in = {0}, out;
    in.key = key; in.data8 = CMD_INFO;
    if (call(&in, &out)) return -1;
    *type = out.keyInfo.dataType; *size = out.keyInfo.dataSize;
    return 0;
}

int smc_key_at(uint32_t index, uint32_t *key) {
    smc_t in = {0}, out;
    in.data8 = CMD_KEY_AT; in.data32 = index;
    if (call(&in, &out)) return -1;
    *key = out.key;
    return 0;
}

int smc_key_count(uint32_t *count) {
    uint8_t b[4];
    if (smc_read('#KEY', b, 4)) return -1;
    *count = ((uint32_t)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    return 0;
}

int cpu_ticks(uint32_t *busy, uint32_t *idle, int max) {
    natural_t ncpu; processor_info_array_t info; mach_msg_type_number_t cnt;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &cnt)) return -1;
    int n = (int)ncpu < max ? (int)ncpu : max;
    for (int c = 0; c < n; c++) {
        unsigned *t = (unsigned *)&info[c * CPU_STATE_MAX];
        busy[c] = t[CPU_STATE_USER] + t[CPU_STATE_SYSTEM] + t[CPU_STATE_NICE];
        idle[c] = t[CPU_STATE_IDLE];
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, cnt * sizeof(int));
    return n;
}
