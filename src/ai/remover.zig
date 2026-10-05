const std = @import("std");
const ort = @import("ort");
const Allocator = std.mem.Allocator;
const Api = ort.Api;
const Error = @import("errors.zig").Error;
const Image = @import("vips").Image;
const Input = @import("processors/Input.zig");
const OrtRunner = @import("OrtRunner.zig");
const Model = OrtRunner.Model;
const Self = @This();

const model_count = @typeInfo(Model).@"enum".fields.len;

/// 全局唯一的 remover 实例。模型会话按需惰性创建，创建后一直复用。
var instance: ?Self = null;
/// 保护 instance 及其内部模型会话的访问
var mutex: std.Thread.Mutex = .{};

api: Api,
runners: [model_count]?OrtRunner = [_]?OrtRunner{null} ** model_count,

/// 初始化全局 remover（幂等）。重复调用不会重建 ONNX 环境。
pub fn init(allocator: Allocator) Error!void {
    mutex.lock();
    defer mutex.unlock();
    if (instance != null) return;
    instance = .{ .api = try Api.init(allocator, "jve") };
}

/// 释放所有已初始化的模型会话与 ONNX 环境。
pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();
    if (instance) |*self| {
        for (&self.runners) |*runner| {
            if (runner.*) |*r| r.deinit();
        }
        self.api.deinit();
        instance = null;
    }
}

/// 以 Model 为键调度对应的模型执行背景移除。模型首次使用时初始化，之后直接复用。
pub fn remove(model: Model, input: Input) Error!Image {
    mutex.lock();
    defer mutex.unlock();
    if (instance) |*self| {
        const index = @intFromEnum(model);
        if (self.runners[index] == null) {
            self.runners[index] = try OrtRunner.init(model, &self.api);
        }
        if (self.runners[index]) |*runner| return runner.run(input);
        unreachable;
    }
    return Error.RemoverNotInitialized;
}
