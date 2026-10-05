const OrtError = @import("ort").Error;
const ConfigError = @import("../config.zig").Error;

pub const CustomError = error{
    ModelNotConfigured,
    ModelDirNotFound,
    ModelDirAccessError,
    ModelFileNotFound,
    ModelFileAccessError,
};

pub const Error = CustomError || OrtError || ConfigError;
