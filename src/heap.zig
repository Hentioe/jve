// glibc 释放大块内存后不一定立即归还操作系统，进程内空闲堆可能长期滞留。
// 这里封装 glibc 的堆管理接口，供需要主动归还内存的场景复用。

const std = @import("std");

extern "c" fn malloc_trim(pad: usize) c_int;

/// 把进程中空闲的堆内存归还给操作系统。
pub fn trimHeap() void {
    // 返回非 0 表示确实归还了内存，0 表示没有可归还的空闲堆
    if (malloc_trim(0) != 0) {
        std.log.debug("Trimmed free heap back to the OS", .{});
    }
}
