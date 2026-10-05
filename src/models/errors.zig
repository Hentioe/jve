const OrtError = @import("ort").Error;

pub const CustomError = error{
    ModelNotConfigured, // 模型未配置
};

pub const Error = CustomError || OrtError;
