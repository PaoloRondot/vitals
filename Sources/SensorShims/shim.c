#include "include/SensorShims.h"
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Private IOKit HID event-system API (symbols live in IOKit.framework).
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define IOHIDEventFieldBase(type) ((type) << 16)

static IOHIDEventSystemClientRef gClient = NULL;
static CFArrayRef gServices = NULL;

int vitals_temp_init(void) {
    if (gServices) {
        return (int)CFArrayGetCount(gServices);
    }

    gClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!gClient) {
        return -1;
    }

    int page = 0xff00; // kHIDPage_AppleVendor
    int usage = 5;     // kHIDUsage_AppleVendor_TemperatureSensor
    CFNumberRef pageNum = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef usageNum = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[2] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *vals[2] = {pageNum, usageNum};
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    CFRelease(pageNum);
    CFRelease(usageNum);

    IOHIDEventSystemClientSetMatching(gClient, match);
    CFRelease(match);

    gServices = IOHIDEventSystemClientCopyServices(gClient);
    if (!gServices) {
        return -1;
    }
    return (int)CFArrayGetCount(gServices);
}

int vitals_temp_name(int index, char *buf, int buflen) {
    if (!gServices || index < 0 || index >= CFArrayGetCount(gServices) || buflen < 1) {
        return 0;
    }
    buf[0] = '\0';
    IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(gServices, index);
    CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
    if (!name) {
        return 0;
    }
    int ok = 0;
    if (CFGetTypeID(name) == CFStringGetTypeID()) {
        ok = CFStringGetCString((CFStringRef)name, buf, buflen, kCFStringEncodingUTF8) ? 1 : 0;
    }
    CFRelease(name);
    return ok;
}

double vitals_temp_read(int index) {
    if (!gServices || index < 0 || index >= CFArrayGetCount(gServices)) {
        return NAN;
    }
    IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(gServices, index);
    IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
    if (!event) {
        return NAN;
    }
    double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
    CFRelease(event);
    return value;
}

// MARK: - CPU frequency via IOReport

// Private IOReport API (libIOReport.tbd in the SDK).
typedef struct IOReportSubscription *IOReportSubscriptionRef;
typedef CFDictionaryRef IOReportSampleRef;

extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup,
                                                   uint64_t a, uint64_t b, uint64_t c);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *allocator,
                                                          CFMutableDictionaryRef desiredChannels,
                                                          CFMutableDictionaryRef *subbedChannels,
                                                          uint64_t channelID, CFTypeRef options);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
                                             CFMutableDictionaryRef subbedChannels, CFTypeRef options);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef current,
                                                  CFTypeRef options);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel);
extern int IOReportStateGetCount(CFDictionaryRef channel);
extern int64_t IOReportStateGetResidency(CFDictionaryRef channel, int index);
extern void IOReportIterate(CFDictionaryRef samples, int (^block)(IOReportSampleRef channel));

#define VITALS_MAX_PSTATES 64
static double gEFreqsMHz[VITALS_MAX_PSTATES];
static int gEFreqCount = 0;
static double gPFreqsMHz[VITALS_MAX_PSTATES];
static int gPFreqCount = 0;
static IOReportSubscriptionRef gFreqSub = NULL;
static CFMutableDictionaryRef gFreqSubbed = NULL;
static CFDictionaryRef gFreqPrev = NULL;

static int load_freq_table(io_registry_entry_t pmgr, CFStringRef key, double *out, int *count) {
    CFTypeRef prop = IORegistryEntryCreateCFProperty(pmgr, key, kCFAllocatorDefault, 0);
    if (!prop) return 0;
    if (CFGetTypeID(prop) != CFDataGetTypeID()) {
        CFRelease(prop);
        return 0;
    }
    const uint8_t *bytes = CFDataGetBytePtr((CFDataRef)prop);
    long len = CFDataGetLength((CFDataRef)prop);
    int n = 0;
    for (long off = 0; off + 8 <= len && n < VITALS_MAX_PSTATES; off += 8) {
        uint32_t raw;
        memcpy(&raw, bytes + off, 4); // (frequency, voltage) LE pairs
        if (raw == 0) continue;
        // Unit varies by chip generation: Hz (M1-era), kHz (M4/M5), or MHz.
        double v = (double)raw;
        double mhz = v >= 1e8 ? v / 1e6 : (v >= 1e5 ? v / 1e3 : v);
        out[n++] = mhz;
        if (getenv("VITALS_DEBUG")) {
            fprintf(stderr, "[vitals] freq table entry: raw=%u -> %.0f MHz\n", raw, mhz);
        }
    }
    CFRelease(prop);
    *count = n;
    return n > 0;
}

int vitals_freq_init(void) {
    if (gFreqSub) return 1;

    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"),
                                     &iter) != KERN_SUCCESS) {
        return 0;
    }
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        io_name_t name;
        if (IORegistryEntryGetName(entry, name) == KERN_SUCCESS && strcmp(name, "pmgr") == 0) {
            load_freq_table(entry, CFSTR("voltage-states1-sram"), gEFreqsMHz, &gEFreqCount);
            load_freq_table(entry, CFSTR("voltage-states5-sram"), gPFreqsMHz, &gPFreqCount);
            IOObjectRelease(entry);
            break;
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iter);
    if (gEFreqCount == 0 && gPFreqCount == 0) return 0;

    CFDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("CPU Stats"),
                                                           CFSTR("CPU Complex Performance States"),
                                                           0, 0, 0);
    if (!channels) return 0;
    CFMutableDictionaryRef desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels);
    CFRelease(channels);
    gFreqSub = IOReportCreateSubscription(NULL, desired, &gFreqSubbed, 0, NULL);
    // `desired` intentionally not released: the subscription references it for
    // the lifetime of the process.
    return gFreqSub != NULL;
}

int vitals_freq_sample(double *e_mhz, double *p_mhz) {
    *e_mhz = 0;
    *p_mhz = 0;
    if (!gFreqSub) return 0;

    CFDictionaryRef now = IOReportCreateSamples(gFreqSub, gFreqSubbed, NULL);
    if (!now) return 0;
    if (!gFreqPrev) {
        gFreqPrev = now;
        return 0;
    }
    CFDictionaryRef delta = IOReportCreateSamplesDelta(gFreqPrev, now, NULL);
    CFRelease(gFreqPrev);
    gFreqPrev = now;
    if (!delta) return 0;

    __block double eNum = 0, eDen = 0, pNum = 0, pDen = 0;
    IOReportIterate(delta, ^int(IOReportSampleRef channel) {
        CFStringRef name = IOReportChannelGetChannelName(channel);
        if (!name || CFStringGetLength(name) == 0) return 0;
        UniChar first = CFStringGetCharacterAtIndex(name, 0);

        const double *table;
        int tableCount;
        double *num, *den;
        if (first == 'E') {
            table = gEFreqsMHz; tableCount = gEFreqCount; num = &eNum; den = &eDen;
        } else if (first == 'P') {
            table = gPFreqsMHz; tableCount = gPFreqCount; num = &pNum; den = &pDen;
        } else {
            return 0;
        }
        if (tableCount == 0) return 0;

        // The trailing states map onto the frequency table; leading states
        // (IDLE/OFF/DOWN) are inactive and excluded from the average.
        int states = IOReportStateGetCount(channel);
        int offset = states - tableCount;
        if (offset < 0) offset = 0;
        for (int i = offset; i < states; i++) {
            int64_t residency = IOReportStateGetResidency(channel, i);
            if (residency <= 0) continue;
            *num += (double)residency * table[i - offset];
            *den += (double)residency;
        }
        return 0;
    });
    CFRelease(delta);

    if (eDen > 0) *e_mhz = eNum / eDen;
    if (pDen > 0) *p_mhz = pNum / pDen;
    return (eDen > 0 || pDen > 0) ? 1 : 0;
}
