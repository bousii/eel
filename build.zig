const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const Target = std.Target.x86;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        // We use software float because we are disabling all SIMD stuff
        .cpu_features_add = Target.featureSet(&.{.soft_float}),
        // Disable all SIMD related stuff because SIMD are problematic in kernel
        .cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .kernel,
        }),
    });
    kernel.setLinkerScript(b.path("src/linker.ld"));
    b.installArtifact(kernel);

    const kernel_path = kernel.getEmittedBin();
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "qemu-system-x86_64",
        "-m", "1G",
        "-serial", "stdio",
    });
    // zig fmt: on
    qemu_cmd.addArg("-kernel");
    qemu_cmd.addFileArg(kernel_path);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_cmd = b.addRunArtifact(kernel);
    run_cmd.step.dependOn(&qemu_cmd.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run kernel with qemu");
    run_step.dependOn(&run_cmd.step);

    // --- ISO + GRUB + QEMU/OVMF run step ---

    const iso_dir = ".zig-cache/isodir";
    const iso_path = "zig-out/eel.iso";
    const cfg_path = "grub.cfg";

    const mkdir_cmd = b.addSystemCommand(&[_][]const u8{
        "mkdir", "-p", iso_dir ++ "/boot/grub",
    });

    const copy_kernel = b.addSystemCommand(&[_][]const u8{"cp"});
    copy_kernel.addFileArg(kernel_path);
    copy_kernel.addArg(iso_dir ++ "/boot/kernel.elf");
    copy_kernel.step.dependOn(&mkdir_cmd.step);
    copy_kernel.step.dependOn(b.getInstallStep());

    const copy_cfg = b.addSystemCommand(&[_][]const u8{"cp"});
    copy_cfg.addFileArg(b.path(cfg_path));
    copy_cfg.addArg(iso_dir ++ "/boot/grub/grub.cfg");
    copy_cfg.step.dependOn(&mkdir_cmd.step);

    const mkrescue_cmd = b.addSystemCommand(&[_][]const u8{
        "grub2-mkrescue", "-o", iso_path, iso_dir,
    });
    mkrescue_cmd.step.dependOn(&copy_kernel.step);
    mkrescue_cmd.step.dependOn(&copy_cfg.step);

    const copy_ovmf_vars = b.addSystemCommand(&[_][]const u8{
        "cp", "-n", "/usr/share/OVMF/OVMF_VARS.fd", ".zig-cache/OVMF_VARS.fd",
    });
    copy_ovmf_vars.step.dependOn(&mkdir_cmd.step);

    const qemu_iso_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "1G",
        "-serial",
        "stdio",
        "-drive",
        "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd",
        "-drive",
        "if=pflash,format=raw,file=.zig-cache/OVMF_VARS.fd",
        "-vga",
        "std",
        "-cdrom",
        iso_path,
    });
    qemu_iso_cmd.step.dependOn(&mkrescue_cmd.step);
    qemu_iso_cmd.step.dependOn(&copy_ovmf_vars.step);

    const run_iso_step = b.step("run-iso", "Build a GRUB ISO and boot it via QEMU+OVMF (EFI)");
    run_iso_step.dependOn(&qemu_iso_cmd.step);
}
