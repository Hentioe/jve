const c = @import("ort_c");

pub const ProviderOptions = union(enum) {
    migraphx: c.OrtMIGraphXProviderOptions,
};
