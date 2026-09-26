pub const Error = error{
    VipsInitFailed,
    VipsForeignGetSuffixesFailed,
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
