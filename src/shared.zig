const structs = @import("shared/structs.zig");
const errors = @import("shared/errors.zig");

pub const h = @import("shared/helper.zig");
pub const heap = @import("shared/heap.zig");
pub const opener = @import("shared/opener.zig");
pub const CString = @import("shared/CString.zig");
pub const Fatal = @import("shared/Fatal.zig");
pub const Vertex = structs.Vertex;
pub const Size2D = structs.Size2D;
pub const IShape = structs.IShape;
pub const Point = structs.Point;
pub const SizeError = errors.SizeError;
pub const Error = errors.Error;
// 直接导出部分常用函数
pub const strdup = h.strdup;
pub const pathExists = h.pathExists;
pub const pathAccessible = h.pathAccessible;
pub const milliTimestamp = h.milliTimestamp;
pub const timestamp = h.timestamp;
