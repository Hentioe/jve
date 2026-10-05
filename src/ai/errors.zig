const OrtError = @import("ort").Error;
const ConfigError = @import("config").Error;
const VipsError = @import("vips").Error;

pub const CustomError = error{
    ModelNotConfigured,
    ModelDirNotFound,
    ModelDirAccessError,
    ModelFileNotFound,
    ModelFileAccessError,
    RemoverNotInitialized,
};

/// Timer 的错误集
pub const TimerError = error{ TimerNotStarted, TimerUnsupported };

pub const Error = CustomError || TimerError || OrtError || ConfigError || VipsError;
