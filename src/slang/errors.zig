const CStringError = @import("shared").CString.Error;

pub const SlangError = error{ SlangCompileFailed, SlangInitFailed };
pub const Error = SlangError || CStringError;
