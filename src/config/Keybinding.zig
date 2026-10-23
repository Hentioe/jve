const std = @import("std");
const sdl = @import("sdl");
const Self = @This();

pub const Error = error{
    KeybindingInvalidFormat,
    KeybindingKeyNotFound,
};

pub const Modifier = enum {
    left_ctrl,
    right_ctrl,
    left_shift,
    right_shift,
    left_alt,
    right_alt,
    left_gui,
    right_gui,

    pub fn from(key: sdl.Key) ?Modifier {
        return switch (key) {
            inline else => |k| if (@hasField(Modifier, @tagName(k)))
                @field(Modifier, @tagName(k))
            else
                null,
        };
    }
};

pub fn isModifier(key: sdl.Key) bool {
    return Modifier.from(key) != null;
}

/// 归一化后绑定字符串的最大长度（最长的组合为 left_alt+right_shift，只有 19 个字符）
const MAX_BINDING_LEN = 32;

/// 修饰键，未指定时为 null
modifier: ?sdl.Key,
/// 绑定的按键
key: sdl.Key,

/// 把按键绑定字符串解析为 Keybinding 实例。
pub fn parse(binding: []const u8) Error!Self {
    // 统一转换为小写并移除所有空格，方便后续处理
    var buffer: [MAX_BINDING_LEN]u8 = undefined;
    var len: usize = 0;
    for (binding) |ch| {
        if (std.ascii.isWhitespace(ch)) continue;
        if (len == buffer.len) return Error.KeybindingInvalidFormat;
        buffer[len] = std.ascii.toLower(ch);
        len += 1;
    }
    const normalized = buffer[0..len];

    var modifier: ?sdl.Key = null;
    var key_name = normalized;

    if (std.mem.indexOfScalar(u8, normalized, '+')) |index| {
        // '+' 左侧必须是单个修饰键，右侧必须是非空的单个按键
        const modifier_name = normalized[0..index];
        if (modifier_name.len == 0) return Error.KeybindingInvalidFormat;
        key_name = normalized[index + 1 ..];
        if (key_name.len == 0 or std.mem.indexOfScalar(u8, key_name, '+') != null) {
            return Error.KeybindingInvalidFormat;
        }
        const parsed = sdl.Key.parse(modifier_name) orelse return Error.KeybindingKeyNotFound;
        if (!isModifier(parsed)) return Error.KeybindingInvalidFormat;
        modifier = parsed;
    }

    // 空字符串
    if (key_name.len == 0) return Error.KeybindingInvalidFormat;

    const key = sdl.Key.parse(key_name) orelse return Error.KeybindingKeyNotFound;
    return .{
        .modifier = modifier,
        .key = key,
    };
}

test "parse single key" {
    const binding = try parse("a");
    try std.testing.expectEqual(@as(?sdl.Key, null), binding.modifier);
    try std.testing.expectEqual(sdl.Key.a, binding.key);

    const digit = try parse("1");
    try std.testing.expectEqual(@as(?sdl.Key, null), digit.modifier);
    try std.testing.expectEqual(sdl.Key._1, digit.key);
}

test "parse modifier key binding" {
    const binding = try parse("left_alt+1");
    try std.testing.expectEqual(@as(?sdl.Key, sdl.Key.left_alt), binding.modifier);
    try std.testing.expectEqual(sdl.Key._1, binding.key);

    const other = try parse("right_shift+a");
    try std.testing.expectEqual(@as(?sdl.Key, sdl.Key.right_shift), other.modifier);
    try std.testing.expectEqual(sdl.Key.a, other.key);
}

test "parse ignores case and whitespace" {
    const binding = try parse(" LEFT_ALT + A ");
    try std.testing.expectEqual(@as(?sdl.Key, sdl.Key.left_alt), binding.modifier);
    try std.testing.expectEqual(sdl.Key.a, binding.key);
}

test "parse rejects invalid format" {
    try std.testing.expectError(error.KeybindingInvalidFormat, parse(""));
    try std.testing.expectError(error.KeybindingInvalidFormat, parse("   "));
    try std.testing.expectError(error.KeybindingInvalidFormat, parse("+a"));
    try std.testing.expectError(error.KeybindingInvalidFormat, parse("left_alt+"));
    try std.testing.expectError(error.KeybindingInvalidFormat, parse("left_alt+a+b"));
    try std.testing.expectError(error.KeybindingInvalidFormat, parse("a+b"));
}

test "parse rejects unknown key" {
    try std.testing.expectError(error.KeybindingKeyNotFound, parse("unknown"));
    try std.testing.expectError(error.KeybindingKeyNotFound, parse("unknown+1"));
    try std.testing.expectError(error.KeybindingKeyNotFound, parse("left_alt+unknown"));
    try std.testing.expectError(error.KeybindingKeyNotFound, parse("mod+a"));
}
