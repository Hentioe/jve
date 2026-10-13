const shared = @import("shared");
const Position = shared.Point(f32);
const RasterSize = shared.Size2D(u32);
const FrameSize = shared.Size2D(i32);

/// 组件的布局选项（与栅格化无关的几何/调试配置）。
pub const LayoutOptions = struct {
    /// 组件 quad 左上角在帧内的像素坐标（原点为帧左上角），默认 (0, 0) 即左上角。
    position: Position = .{},
    /// 调试开关：为组件图片叠加红色背景，便于观察 quad 的位置与大小。
    debug: bool = false,

    /// 计算使组件在帧内居中的位置。居中不再是默认行为，需要时显式调用。
    pub fn centered(raster_size: RasterSize, frame_size: FrameSize, offset: Position) Position {
        const f_rsize = raster_size.to(f32);
        const bw: f32 = f_rsize.w;
        const bh: f32 = f_rsize.h;
        const fw: f32 = @floatFromInt(frame_size.w);
        const fh: f32 = @floatFromInt(frame_size.h);
        return .{ .x = (fw - bw) * 0.5 + offset.x, .y = (fh - bh) * 0.5 + offset.y };
    }
};
