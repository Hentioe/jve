const std = @import("std");
const c = @import("c.zig").c;
const OrtError = @import("errors.zig").OrtError;

/// 检查 ORT 调用返回的 status，如果失败则打印错误并返回 OrtError.OrtFailed。
/// ORT 的 API 通常通过输出参数带出结果，status 非 null 即表示失败。
pub fn check(ort_api: *const c.OrtApi, status: ?*c.OrtStatus) OrtError!void {
    if (status) |s| {
        const err = ort_api.*.GetErrorMessage.?(s);
        std.log.err("[ORT ERROR] {s}", .{std.mem.span(err)});
        ort_api.*.ReleaseStatus.?(s);
        return OrtError.OrtFailed;
    }
}
