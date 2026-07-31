const console = @import("console.zig");

// Declare constants for the multiboot header.
const MB_HEADER_MAGIC = 0x1BADB002; // align loaded modules on page boundaries
const MB_ALIGN = 1 << 0; // provide memory map
const MB_MEMINFO = 1 << 1; // this is the Multiboot 'flag' field
const FLAGS = MB_ALIGN | MB_MEMINFO; // 'magic number' lets bootloader find the header
const CHECKSUM = ~@as(u32, (MB_HEADER_MAGIC + FLAGS)) + 1;

// https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Header-layout
const MultibootHeader = packed struct(u128) {
    magic: u32 = MB_HEADER_MAGIC,
    flags: u32 = FLAGS,
    checksum: u32 = CHECKSUM,
    padding: u32 = 0,
};

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
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
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

noinline fn kmain() callconv(.c) noreturn {
    // VGA driver init
    console.init();
    // Print string
    console.printString("Welcome to eel!");
    // halt forever
    while (true) {
        asm volatile ("hlt");
    }
}
