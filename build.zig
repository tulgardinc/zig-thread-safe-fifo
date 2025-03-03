const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.createModule(.{
        .root_source_file = b.path("src/thread_safe_fifo.zig"),
        .target = target,
        .optimize = optimize,
    });
}
