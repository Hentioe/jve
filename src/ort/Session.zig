const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const ProviderOptions = @import("enums.zig").ProviderOptions;
const Api = @import("Api.zig");
const Self = @This();

api: *const Api,
session: *c.OrtSession,
session_options: *c.OrtSessionOptions,

pub const InitOptions = struct {
    disable_gpu: bool = false,
};

pub fn init(
    api: *const Api,
    provider_options_list: *const std.ArrayList(ProviderOptions),
    model_path: [*]const u8,
    init_options: InitOptions,
) Error!Self {
    const ort_api = api.ort_api;
    // 创建 SessionOptions
    var session_options: ?*c.OrtSessionOptions = null;
    if (!h.check(ort_api, ort_api.*.CreateSessionOptions.?(&session_options)))
        return Error.OrtCreateSessionOptionsFailed;
    // 关闭 Pattern 优化（避免额外内存申请）
    if (!h.check(ort_api, ort_api.*.DisableMemPattern.?(session_options)))
        return Error.OrtDisableMemPatternFailed;
    // 关闭 CPU Arena（用完立即释放内存）
    if (!h.check(ort_api, ort_api.*.DisableCpuMemArena.?(session_options)))
        return Error.OrtDisableCpuMemArenaFailed;
    // 关闭权重预打包（预打包会在堆上额外保存 Conv 权重的优化布局）
    if (!h.check(ort_api, ort_api.*.AddSessionConfigEntry.?(
        session_options,
        "session.disable_prepacking",
        "1",
    ))) return Error.OrtAddSessionConfigEntryFailed;
    // 检查 GPU 加速配置
    if (!init_options.disable_gpu) {
        // 给会话附加 GPU EP 选项
        for (provider_options_list.items) |p| {
            switch (p) {
                .migraphx => |*options| {
                    // 把 MIGraphX EP 配置到 SessionOptions
                    if (!h.check(ort_api, ort_api.*.SessionOptionsAppendExecutionProvider_MIGraphX.?(session_options, options))) {
                        std.log.warn("Failed to append MIGraphX execution provider to session options", .{});
                        continue;
                    }
                    std.log.info("MIGraphX has been appended to session options", .{});
                },
            }
        }
    }
    // 创建会话
    var session: ?*c.OrtSession = null;
    if (!h.check(ort_api, ort_api.*.CreateSession.?(api.env, model_path, session_options, &session))) {
        return Error.OrtCreateSessionFailed;
    }

    return Self{
        .api = api,
        .session = session.?,
        .session_options = session_options.?,
    };
}

pub fn deinit(self: *Self) void {
    const ort_api = self.api.ort_api;
    ort_api.*.ReleaseSession.?(self.session);
    ort_api.*.ReleaseSessionOptions.?(self.session_options);
    self.* = undefined;
}

pub fn createTensorWithData(self: *const Self, shape: [*]const i64, shape_len: usize, data: *anyopaque, data_bytes: usize) Error!*c.OrtValue {
    const ort_api = self.api.ort_api;
    var tensor: ?*c.OrtValue = null;
    if (!h.check(ort_api, ort_api.*.CreateTensorWithDataAsOrtValue.?(
        self.api.memory_info,
        data,
        data_bytes,
        shape,
        shape_len,
        c.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &tensor,
    ))) {
        return Error.OrtCreateTensorWithDataAsOrtValue;
    }

    return tensor.?;
}

pub fn run(self: *const Self, input_tensor: ?*c.OrtValue) Error!*c.OrtValue {
    const ort_api = self.api.ort_api;
    // 标准输入和输出节点名称
    var ort_allocator: ?*c.OrtAllocator = null;
    if (!h.check(ort_api, ort_api.*.GetAllocatorWithDefaultOptions.?(&ort_allocator))) {
        return Error.OrtGetAllocatorWithDefaultOptionsFailed;
    }

    // 从 session 中读取第 0 个输入和输出的真实节点名
    var input_name_ptr: [*c]u8 = null;
    if (!h.check(ort_api, ort_api.*.SessionGetInputName.?(self.session, 0, ort_allocator, &input_name_ptr))) {
        return Error.OrtGetInputNameFailed;
    }
    defer _ = ort_api.*.AllocatorFree.?(ort_allocator, input_name_ptr);

    var output_name_ptr: [*c]u8 = null;
    if (!h.check(ort_api, ort_api.*.SessionGetOutputName.?(self.session, 0, ort_allocator, &output_name_ptr))) {
        return Error.OrtGetOutputNameFailed;
    }
    defer _ = ort_api.*.AllocatorFree.?(ort_allocator, output_name_ptr);

    // 用读取到的指针组装数组给 Run 使用
    const input_names = [_][*c]const u8{input_name_ptr};
    const output_names = [_][*c]const u8{output_name_ptr};

    // 执行推理
    var output_tensor: ?*c.OrtValue = null;
    if (!h.check(ort_api, ort_api.*.Run.?(
        self.session,
        null, // RunOptions
        &input_names, // 输入节点名数组
        &input_tensor, // 输入 Tensor 数组和数量
        1,
        &output_names, // 输出节点名数组和数量
        1,
        &output_tensor, // 输出结果接收地址
    ))) {
        return Error.OrtRunFailed;
    }

    return output_tensor.?;
}
