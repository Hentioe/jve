const std = @import("std");
const SdlError = @import("sdl").Error;
const AssError = @import("ass").Error;
const OrtError = @import("ort").Error;
const SizeError = @import("shared").SizeError;
const AiError = @import("../ai.zig").Error;
const UiError = @import("../ui.zig").CustomError; // todo: 改为 Error（等待 display 的部分代码迁移）
const ShaderError = @import("../shader.zig").Error;
const PipelineError = @import("../pipelines/errors.zig").Error;
const GalleryError = @import("../gallery.zig").Error;
const StepTraceError = @import("../StepTrace.zig").Error;

const CustomError = error{};

pub const Error = CustomError || SdlError || AssError || SizeError || OrtError || GalleryError || AiError || UiError || ShaderError || PipelineError || StepTraceError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.fs.File.OpenError;
