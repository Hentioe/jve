const Self = @This();

r: f32,
g: f32,
b: f32,
a: f32,

/// 由 8 位分量（0..255）构造颜色，便于直接使用设计稿或常见色值。
pub fn rgba(r: u8, g: u8, b: u8, a: u8) Self {
    return Self{
        .r = @as(f32, @floatFromInt(r)) / 255.0,
        .g = @as(f32, @floatFromInt(g)) / 255.0,
        .b = @as(f32, @floatFromInt(b)) / 255.0,
        .a = @as(f32, @floatFromInt(a)) / 255.0,
    };
}

pub fn rgb(r: u8, g: u8, b: u8) Self {
    return rgba(r, g, b, 255);
}

/// 由归一化分量（0..1）构造颜色。
pub fn rgba01(r: f32, g: f32, b: f32, a: f32) Self {
    return Self{ .r = r, .g = g, .b = b, .a = a };
}

pub fn rgb01(r: f32, g: f32, b: f32) Self {
    return Self{ .r = r, .g = g, .b = b, .a = 1.0 };
}

pub fn value(self: Self) [4]f32 {
    return .{ self.r, self.g, self.b, self.a };
}
