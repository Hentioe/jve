const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const ProviderOptions = @import("enums.zig").ProviderOptions;
const Session = @import("Session.zig");
const Self = @This();

allocator: Allocator,
ort_api: *const c.struct_OrtApi,
env: *c.OrtEnv,
memory_info: ?*c.OrtMemoryInfo,
provider_list: std.ArrayList([]const u8),
provider_options_list: std.ArrayList(ProviderOptions),

pub fn init(allocator: Allocator, logid: [*]const u8) Error!Self {
    // 获取 ONNX Runtime API 句柄
    const base = c.OrtGetApiBase();
    const ort_api = base.*.GetApi.?(c.ORT_API_VERSION);

    // 创建 Env
    var env: ?*c.OrtEnv = null;
    if (!h.check(ort_api, ort_api.*.CreateEnv.?(c.ORT_LOGGING_LEVEL_WARNING, logid, &env))) {
        return Error.OrtCreateEnvFailed;
    }

    // 创建 MemoryInfo
    var memory_info: ?*c.OrtMemoryInfo = null;
    if (!h.check(ort_api, ort_api.*.CreateCpuMemoryInfo.?(c.OrtArenaAllocator, c.OrtMemTypeDefault, &memory_info))) {
        return Error.OrtCreateMemoryInfoFailed;
    }

    // 获取可用的 EP 列表
    std.log.info("Getting available EP list...", .{});
    var providers: [*c][*c]u8 = undefined;
    var provider_len: i32 = 0;
    if (!h.check(ort_api, ort_api.*.GetAvailableProviders.?(&providers, &provider_len))) {
        return Error.OrtGetAvailableProvidersFailed;
    }
    defer _ = ort_api.*.ReleaseAvailableProviders.?(providers, provider_len);
    const provider_count: u32 = @intCast(provider_len);
    var provider_list = try std.ArrayList([]const u8).initCapacity(allocator, provider_count);
    for (0..provider_count) |i| {
        const c_str = providers[i];
        const s = std.mem.span(c_str);
        const owned_s = try allocator.dupe(u8, s); // 复制一份
        try provider_list.append(allocator, owned_s);
    }
    // 用日志把可用的 EP 列表打印出来
    for (provider_list.items) |item| {
        std.log.info("Available: {s}", .{item});
    }
    // 遍历 provider_list 并创建部分对应的 ProviderOptions
    var provider_options_list = try std.ArrayList(ProviderOptions).initCapacity(allocator, 0);
    for (provider_list.items) |item| {
        if (std.mem.eql(u8, item, "MIGraphXExecutionProvider")) { // 添加 MiGraphX 配置
            const migraphx_options: c.OrtMIGraphXProviderOptions = .{
                .device_id = 0, // todo: 获取设备 id
            };
            try provider_options_list.append(allocator, ProviderOptions{ .migraphx = migraphx_options });
        }
    }

    return .{
        .allocator = allocator,
        .ort_api = ort_api,
        .env = env.?,
        .memory_info = memory_info.?,
        .provider_list = provider_list,
        .provider_options_list = provider_options_list,
    };
}

pub fn deinit(self: *Self) void {
    self.ort_api.*.ReleaseEnv.?(self.env);
    self.ort_api.*.ReleaseMemoryInfo.?(self.memory_info);
    for (self.provider_list.items) |item| {
        self.allocator.free(item);
    }
    self.provider_list.deinit(self.allocator);
    self.provider_options_list.deinit(self.allocator);
    self.* = undefined;
}

pub fn createSession(self: *const Self, model_path: [*]const u8, init_options: Session.InitOptions) Error!Session {
    return try Session.init(
        self,
        &self.provider_options_list,
        model_path,
        init_options,
    );
}

pub fn releaseValue(self: *const Self, value: ?*c.OrtValue) void {
    self.ort_api.*.ReleaseValue.?(value);
}

pub fn getTensorMutableData(self: *const Self, output_tensor: ?*c.OrtValue) Error!*anyopaque {
    var output_ptr: ?*anyopaque = null;
    if (!h.check(self.ort_api, self.ort_api.*.GetTensorMutableData.?(output_tensor, &output_ptr))) {
        return Error.OrtGetTensorMutableDataFailed;
    }

    return output_ptr.?;
}
