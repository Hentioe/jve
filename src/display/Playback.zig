const std = @import("std");
const Animation = @import("vips").Animation;
const Self = @This();

/// 播放锚点：`anchor_ticks` 时刻对应累计进度 `anchor_ms`。
anchor_ticks: u64,
anchor_ms: u64 = 0,
/// 当前显示的帧索引。初始为 0，因为首帧在初始化时已经上传并显示。
index: usize = 0,
/// 是否继续推进。动图始终播放，不提供暂停交互；
/// 解码或上传失败时置 false，避免每轮重复出错。
playing: bool,

pub fn init(now: u64, is_animation: bool) Self {
    return .{ .anchor_ticks = now, .playing = is_animation };
}

/// 当前累计播放进度（毫秒），始终落在 [0, total_ms)。
pub fn elapsedMs(self: *const Self, animation: *const Animation, now: u64) u64 {
    const total = animation.totalMs();
    if (total == 0) return 0;
    // now 可能早于锚点（理论上不会发生），用饱和减法兜底
    const advanced = self.anchor_ms + (now -| self.anchor_ticks);
    return advanced % total;
}

/// 与当前时间同步。帧索引变化时更新自身并返回新索引；
/// 索引未变时返回 null，调用方无需重复上传纹理。
pub fn sync(self: *Self, animation: *const Animation, now: u64) ?usize {
    const index = animation.frameIndexAt(self.elapsedMs(animation, now));
    if (index == self.index) return null;
    self.index = index;
    return index;
}
