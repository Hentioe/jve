const std = @import("std");
const AllocatorError = std.mem.Allocator.Error;

pub const OrtError = error{
    OrtCreateEnvFailed,
    OrtCreateMemoryInfoFailed,
    OrtCreateSessionFailed,
    OrtCreateSessionOptionsFailed,
    OrtCreateTensorWithDataAsOrtValue,
    OrtGetAllocatorWithDefaultOptionsFailed,
    OrtGetInputNameFailed,
    OrtGetOutputNameFailed,
    OrtGetAvailableProvidersFailed,
    OrtGetTensorMutableDataFailed,
    OrtRunFailed,
};

pub const Error = OrtError || AllocatorError;
