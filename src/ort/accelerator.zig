const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const ProviderOptions = @import("enums.zig").ProviderOptions;

pub fn buidlOptions(provider_name: []const u8) Error!?ProviderOptions {
    if (std.mem.eql(u8, provider_name, "MIGraphXExecutionProvider")) { // 构造 MiGraphX 配置
        const device_id = getDeviceId();
        std.log.info("MIGraphX selected device id: {d}", .{device_id});
        const migraphx: c.OrtMIGraphXProviderOptions = .{
            .device_id = device_id, // todo: 获取设备 id
            .migraphx_fp16_enable = 1,
        };

        return .{ .migraphx = migraphx };
    }

    return null;
}

const kfd_nodes = "/sys/class/kfd/kfd/topology/nodes";

fn readSmall(path: []const u8, buf: []u8) ?[]const u8 {
    const f = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    const n = f.readAll(buf) catch return null;
    return buf[0..n];
}

/// 解析 "key value" 形式的 properties 文件
fn propValue(content: []const u8, key: []const u8) ?u64 {
    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    while (lines.next()) |line| {
        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const k = parts.next() orelse continue;
        if (!std.mem.eql(u8, k, key)) continue;
        const v = parts.next() orelse return null;
        return std.fmt.parseInt(u64, v, 10) catch null;
    }
    return null;
}

/// 获取 HIP 设备序号（MIGraphX 的 device_id）。
/// 多 GPU 时选择 SIMD 数量最多的那块；任何失败都回退到 0。
fn getDeviceId() c_int {
    // 用户已通过环境变量限定可见设备，此时 HIP 会重新编号，第一块就是 0
    if (std.posix.getenv("HIP_VISIBLE_DEVICES") != null or
        std.posix.getenv("ROCR_VISIBLE_DEVICES") != null) return 0;

    var path_buf: [128]u8 = undefined;
    var buf: [4096]u8 = undefined;

    var gpu_index: c_int = 0; // 已遇到的 GPU 节点数，即 HIP 序号
    var best_index: c_int = 0;
    var best_simd: u64 = 0;

    var node: usize = 0;
    while (node < 64) : (node += 1) {
        const gpu_id_path = std.fmt.bufPrint(&path_buf, "{s}/{d}/gpu_id", .{ kfd_nodes, node }) catch break;
        const gpu_id_txt = readSmall(gpu_id_path, &buf) orelse break; // 节点编号连续，读不到就结束
        const gpu_id = std.fmt.parseInt(u64, std.mem.trim(u8, gpu_id_txt, " \n\r\t"), 10) catch continue;
        if (gpu_id == 0) continue; // CPU 节点

        const prop_path = std.fmt.bufPrint(&path_buf, "{s}/{d}/properties", .{ kfd_nodes, node }) catch break;
        if (readSmall(prop_path, &buf)) |props| {
            const simd = propValue(props, "simd_count") orelse 0;
            if (simd > best_simd) {
                best_simd = simd;
                best_index = gpu_index;
            }
        }
        gpu_index += 1;
    }

    return best_index;
}
