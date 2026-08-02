pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255 };
};

pub const FramebufferInfo = struct {
    addr: usize,
    pitch: u32, // width plus padding
    width: u32,
    height: u32,
    bpp: u8,
    red_pos: u8,
    red_size: u8,
    green_pos: u8,
    green_size: u8,
    blue_pos: u8,
    blue_size: u8,

    pub fn packColor(self: FramebufferInfo, c: Color) u32 {
        const r32: u32 = @as(u32, c.r) >> @intCast(8 - self.red_size);
        const g32: u32 = @as(u32, c.g) >> @intCast(8 - self.green_size);
        const b32: u32 = @as(u32, c.b) >> @intCast(8 - self.blue_size);
        return (r32 << @intCast(self.red_pos)) |
            (g32 << @intCast(self.green_pos)) |
            (b32 << @intCast(self.blue_pos));
    }

    pub fn putPixel(self: FramebufferInfo, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;

        const packed_color = self.packColor(color);
        const offset = y * self.pitch + x * (self.bpp / 8);
        const base: [*]volatile u8 = @ptrFromInt(self.addr);

        switch (self.bpp) {
            32 => {
                const ptr: *volatile u32 = @ptrCast(@alignCast(&base[offset]));
                ptr.* = packed_color;
            },
            24 => {
                base[offset + 0] = @truncate(packed_color);
                base[offset + 1] = @truncate(packed_color >> 8);
                base[offset + 2] = @truncate(packed_color >> 16);
            },
            15 => {
                const ptr: *volatile u16 = @ptrCast(@alignCast(&base[offset]));
                ptr.* = @truncate(packed_color);
            },
            else => {
                @panic("Unsupported framebuffer bpp");
            },
        }
    }
};
