const std = @import("std");
const AllocatorError = std.mem.Allocator.Error;

pub const OrtError = error{
    OrtCreateEnvFailed,
    OrtCreateMemoryInfoFailed,
    OrtCreateSessionFailed,
    OrtCreateSessionOptionsFailed,
    OrtDisableMemPatternFailed,
    OrtDisableCpuMemArenaFailed,
    OrtAddSessionConfigEntryFailed,
    OrtCreateTensorWithDataAsOrtValue,
    OrtGetAllocatorWithDefaultOptionsFailed,
    OrtGetInputNameFailed,
    OrtGetOutputNameFailed,
    OrtGetAvailableProvidersFailed,
    OrtGetTensorMutableDataFailed,
    OrtRunFailed,
};

pub const Error = OrtError || AllocatorError;
