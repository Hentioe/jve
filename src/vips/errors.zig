pub const Error = error{
    VipsNotInitialized,
    VipsInitFailed,
    VipsSuffixesGetFailed,
    VipsImageLoadFailed,
    VipsWriteFailed,
    VipsEncodingFailed,
    VipsResizeFailed,
    VipsLinear1Failed,
    VipsFlattenFailed,
    VipsBandJoinConst2Failed,
    UnsupportedFormat,
    OutOfMemory,
};
