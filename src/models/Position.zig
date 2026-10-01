const Self = @This();

x: f32,
y: f32,

pub fn init(x: f32, y: f32) Self {
    return Self{
        .x = x,
        .y = y,
    };
}
