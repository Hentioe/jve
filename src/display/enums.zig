// 退出动作
pub const ExitAction = enum {
    quit,
    toggle,
};

// 图片超出窗口最大限制的方向
pub const Overflow = enum {
    none, // 未超出
    horizontal, // 横向超出
    vertical, // 纵向超出
    both, // 横纵均超出
};
