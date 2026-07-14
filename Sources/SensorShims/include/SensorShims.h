#ifndef SENSOR_SHIMS_H
#define SENSOR_SHIMS_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// MARK: - Temperature sensors (IOHIDEventSystemClient, private IOKit API)
//
// Apple Silicon exposes die temperature sensors through the HID event system
// (AppleVendor usage page 0xff00, usage 5). The enumeration and event reads
// are done in C (shim.c) so Swift never has to deal with unaudited CF
// ownership on the private functions.

// Enumerate temperature sensor services. Returns the sensor count, or -1 on
// failure. Safe to call repeatedly; enumeration happens once.
int vitals_temp_init(void);

// Copy sensor `index`'s product name into buf (UTF-8, NUL-terminated).
// Returns 1 on success, 0 otherwise.
int vitals_temp_name(int index, char *buf, int buflen);

// Read the current temperature (°C) of sensor `index`. Returns NaN on failure.
double vitals_temp_read(int index);

// MARK: - CPU frequency (IOReport performance-state residencies)
//
// Live core clocks come from IOReport's "CPU Complex Performance States"
// residency counters, weighted by the per-cluster frequency tables that the
// pmgr device-tree node publishes (voltage-states1-sram for E cores,
// voltage-states5-sram for P cores).

// Load frequency tables and subscribe to IOReport. Returns 1 on success.
int vitals_freq_init(void);

// Compute active-residency-weighted average frequencies (MHz) since the
// previous call. Returns 0 until two samples exist, 1 on success.
int vitals_freq_sample(double *e_mhz, double *p_mhz);

// Same idea for the GPU ("GPU Performance States" + voltage-states9-sram).
// busy is the active (non-idle) residency fraction, 0..1.
int vitals_gpu_init(void);
int vitals_gpu_sample(double *mhz, double *busy);

// MARK: - SMC key data (AppleSMC user client, selector 2)
//
// The canonical 80-byte structure exchanged with the AppleSMC kext.
// Defined in C so the layout matches the kernel's expectation exactly.

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} VitalsSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} VitalsSMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} VitalsSMCKeyInfo;

typedef struct {
    uint32_t key;
    VitalsSMCVersion vers;
    VitalsSMCPLimitData pLimitData;
    VitalsSMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} VitalsSMCKeyData;

// SMC user-client selectors / command bytes.
#define VITALS_SMC_SELECTOR_HANDLE_EVENT 2
#define VITALS_SMC_CMD_READ_KEY 5
#define VITALS_SMC_CMD_WRITE_KEY 6
#define VITALS_SMC_CMD_GET_KEY_INFO 9

#endif /* SENSOR_SHIMS_H */
