pub const Error = error{
    VipsNotInitialized,
    VipsInitFailed,
    VipsSuffixesGetFailed,
    VipsImageLoadFailed,
    VipsWriteFailed,
    VipsEncodingFailed,
    UnsupportedFormat,
    OutOfMemory,
};
