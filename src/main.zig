const fb = @import("framebuffer.zig");

// Declare constants for the multiboot header.
const MB_HEADER_MAGIC = 0x1BADB002; // 'magic number' lets bootloader find the header
const MB_BOOTLOADER_HEADER_MAGIC = 0x2BADB002; // 'magic number' lets bootloader find the header
const MB_ALIGN = 1 << 0; // align loaded modules on page boundaries
const MB_MEMINFO = 1 << 1; // provide memory map
const MB_VIDEO_MODE = 1 << 2; // Request Framebuffer
const FLAGS = MB_ALIGN | MB_MEMINFO | MB_VIDEO_MODE; // this is the Multiboot 'flag' field
const CHECKSUM = ~@as(u32, (MB_HEADER_MAGIC + FLAGS)) +% 1;
const LINEAR_VIDEO_MODE = 0;

// Is there basic lower/upper memory information?
const MB_INFO_MEMORY = 0x1;
// Is there a boot device set?
const MB_INFO_BOOTDEV = 0x2;
// Is the command line defined?
const MB_INFO_COMMANDLINE = 0x4;
// Are there modules to do something with?
const MB_INFO_MODS = 0x8;

// These next two are mutually exclusive

// Is there a symbol table loaded?
const MB_INFO_AOUT_SYS = 0x10;
// Is there an ELF section header table?
const MB_INFO_ELF_SHDR = 0x10;

// Is there a full memory map?
const MB_INFO_MEM_MAP = 0x40;

// Is there drive info?
const MB_INFO_DRIVE_INFO = 0x80;

//Is there a config table?
const MB_INFO_CFG_TABLE = 0x100;

// Is there a boot loader name?
const MB_INFO_BOOT_LOADER_NAME = 0x200;

// Is there an APM table?
const MB_INFO_APM_TABLE = 0x200;

// Is there video information?
const MB_INFO_VBE_INFO = 0x800;
const MB_INFO_FRAMEBUFFER_INFO = 0x1000;

// Declare constants for Multiboot info FB type
const MB_FRAMEBUFFER_TYPE_INDEXED = 0;
const MB_FRAMEBUFFER_TYPE_RGB = 1;
const MB_FRAMEBUFFER_TYPE_TEXT = 2;

// https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Header-layout
const MultibootHeader = extern struct {
    magic: u32 = MB_HEADER_MAGIC,
    flags: u32 = FLAGS,
    checksum: u32 = CHECKSUM,

    // a.out kludge fields (header_addr, load_addr, load_end_addr,
    // bss_end_addr, entry_addr) — unused since we're an ELF kernel,
    // but must be present (as zero) because MB_VIDEO_MODE requires
    // the struct to extend this far.
    aout_kludge: [5]u32 = [_]u32{0} ** 5,

    // Required because MB_VIDEO_MODE is set.
    mode_type: u32 = LINEAR_VIDEO_MODE,
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 0,
};

pub const MultibootRgb = extern struct {
    red_field_position: u8,
    red_mask_size: u8,
    green_field_position: u8,
    green_mask_size: u8,
    blue_field_position: u8,
    blue_mask_size: u8,
};

pub const MultibootInfo = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,

    // 16 bytes symbol table info
    syms: [4]u32,

    mmap_len: u32,
    mmap_addr: u32,
    drives_len: u32,
    drives_addr: u32,
    config_table: u32,
    boot_loader_name: u32,
    apm_table: u32,
    vbe_ctrl_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,

    // NOTE: THIS NEEDS TO BE ALIGNED TO FOUR BYTES BECAUSE OF THE
    // IDIOTIC UNION IN THE SPEC, DO NOT REMOVE OR CHANGE
    rgb: MultibootRgb align(4),
};

// Sanity check, because WHY, WHY IS IT LIKE THIS
comptime {
    if (@offsetOf(MultibootInfo, "rgb") != 112) {
        @compileError("framebuffer rgb values not properly aligned");
    }
}
// Declare a multiboot header that marks the program as a kernel. These are magic
// values that are documented in the multiboot standard. The bootloader will
// search for this signature in the first 8 KiB of the kernel file, aligned at a
// 32-bit boundary. The signature is in its own section so the header can be
// forced to be within the first 8 KiB of the kernel file.
export var multiboot: MultibootHeader align(4) linksection(".multiboot") = .{};

// The multiboot standard does not define the value of the stack pointer register
// (esp) and it is up to the kernel to provide a stack. This allocates room for a
// small stack by creating a symbol at the bottom of it, then allocating 16384
// bytes for it, and finally creating a symbol at the top. The stack grows
// downwards on x86. The stack is in its own section so it can be marked nobits,
// which means the kernel file is smaller because it does not contain an
// uninitialized stack. The stack on x86 must be 16-byte aligned according to the
// System V ABI standard and de-facto extensions. The compiler will assume the
// stack is properly aligned and failure to align the stack will result in
// undefined behavior.
var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

// We specify that this function is "naked" to let the compiler know
// not to generate a standard function prologue and epilogue, since
// we don't have a stack yet.
export fn _start() callconv(.naked) noreturn {
    // We use inline assembly to set up the stack before jumping to
    // our kernel entry point.
    asm volatile (
        \\ movl %%eax, %%esi
        \\ movl  %%ebx, %%edi
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ pushl %%edi
        \\ pushl %%esi
        \\ call %[kmain:P]
        :
        // The stack grows downwards on x86, so we need to point ESP register
        // to one element past the end of `stack_bytes`.
        //
        // Finally, we pass the whole expression as an input operand with the
        // "immediate" constraint to force the compiler to encode this as an
        // absolute address. This prevents the compiler from doing unnecessary
        // extra steps to compute the address at runtime (especially in Debug mode),
        // which could possibly clobber registers that are specified by multiboot
        // to hold special values (e.g. EAX).
        : [stack_top] "i" (stack_bytes[stack_bytes.len..].ptr),
          // We let the compiler handle the reference to kmain by passing it as an input operand as well.
          [kmain] "X" (&kmain),
    );
}

inline fn rot() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

noinline fn kmain(magic: u32, mb_info_addr: usize) callconv(.c) noreturn {
    if (magic != MB_BOOTLOADER_HEADER_MAGIC) {
        rot();
    }

    const mb_info: *const MultibootInfo = @ptrFromInt(mb_info_addr);
    const color = fb.Color.green;
    const fb_info = fb.FramebufferInfo{
        .addr = @intCast(mb_info.framebuffer_addr),
        .pitch = mb_info.framebuffer_pitch,
        .width = mb_info.framebuffer_width,
        .height = mb_info.framebuffer_height,
        .bpp = mb_info.framebuffer_bpp,
        .red_pos = mb_info.rgb.red_field_position,
        .red_size = mb_info.rgb.red_mask_size,
        .green_pos = mb_info.rgb.green_field_position,
        .green_size = mb_info.rgb.green_mask_size,
        .blue_pos = mb_info.rgb.blue_field_position,
        .blue_size = mb_info.rgb.blue_mask_size,
    };

    for (0..fb_info.width) |x| {
        for (0..fb_info.height) |y| {
            fb_info.putPixel(x, y, color);
        }
    }

    // console.init(mb_info);

    // if (mb_info.flags & MB_INFO_FRAMEBUFFER_INFO != 0) {
    //     console.printString("Framebuffer Ok!");
    //     console.printString("Welcome to eel!");
    // } else {
    //     console.printString("Framebuffer not Ok :(");
    // }

    rot();
}
