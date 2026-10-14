const Self = @This();

r: f32,
g: f32,
b: f32,
a: f32,

pub fn rgba(r: f32, g: f32, b: f32, a: f32) Self {
    return Self{ .r = r, .g = g, .b = b, .a = a };
}

pub fn rgb(r: f32, g: f32, b: f32) Self {
    return Self{ .r = r, .g = g, .b = b, .a = 1.0 };
}

pub fn value(self: Self) [4]f32 {
    return .{ self.r, self.g, self.b, self.a };
}
