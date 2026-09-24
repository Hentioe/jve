const c = @import("c.zig").c;

pub const ProviderOptions = union(enum) {
    migraphx: c.OrtMIGraphXProviderOptions,
};
