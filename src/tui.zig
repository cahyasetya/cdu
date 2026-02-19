const std = @import("std");
const c = @cImport(@cInclude("sys/ioctl.h"));
const tree = @import("tree.zig");

pub const BAR_WIDTH = 16;
pub const HEADER_LINES: usize = 3;
pub const FOOTER_LINES: usize = 1;

pub fn humanSize(bytes: u64, buf: []u8) []u8 {
    const kb: f64 = 1024;
    const mb: f64 = kb * 1024;
    const gb: f64 = mb * 1024;
    const f: f64 = @floatFromInt(bytes);
    if (f >= gb) {
        return std.fmt.bufPrint(buf, "{d:.1} GB", .{f / gb}) catch buf;
    } else if (f >= mb) {
        return std.fmt.bufPrint(buf, "{d:.1} MB", .{f / mb}) catch buf;
    } else if (f >= kb) {
        return std.fmt.bufPrint(buf, "{d:.1} KB", .{f / kb}) catch buf;
    } else {
        return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch buf;
    }
}

pub fn termRows() usize {
    var ws = std.mem.zeroes(c.struct_winsize);
    _ = c.ioctl(std.posix.STDOUT_FILENO, c.TIOCGWINSZ, &ws);
    return if (ws.ws_row > 0) ws.ws_row else 24;
}

pub fn render(
    writer: anytype,
    root: *tree.Node,
    items: []const tree.VisibleItem,
    selected: usize,
    viewport_top: usize,
    visible_height: usize,
) !void {
    try writer.writeAll("\x1b[2J\x1b[H");

    var hbuf: [32]u8 = undefined;
    try writer.print("--- {s} ({s}) ---\r\n\r\n", .{ root.name, humanSize(root.size, &hbuf) });

    const viewport_end = @min(viewport_top + visible_height, items.len);
    for (items[viewport_top..viewport_end], viewport_top..) |item, i| {
        const is_selected = i == selected;
        const node = item.node;

        if (is_selected) try writer.writeAll("\x1b[7m");
        try writer.print("{s}  ", .{if (is_selected) ">" else " "});

        const pct: f64 = if (root.size == 0) 0 else
            @as(f64, @floatFromInt(node.size)) / @as(f64, @floatFromInt(root.size));
        const filled: usize = @intFromFloat(pct * BAR_WIDTH);
        try writer.writeAll("[");
        var b: usize = 0;
        while (b < BAR_WIDTH) : (b += 1) {
            try writer.writeAll(if (b < filled) "#" else " ");
        }
        try writer.print("] {d:5.1}%  ", .{pct * 100.0});

        var d: usize = 0;
        while (d < item.depth) : (d += 1) try writer.writeAll("  ");
        if (node.is_dir) {
            try writer.print("{s}/", .{node.name});
        } else {
            try writer.print("{s}", .{node.name});
        }

        var sbuf: [32]u8 = undefined;
        try writer.print("  {s}", .{humanSize(node.size, &sbuf)});

        if (is_selected) try writer.writeAll("\x1b[0m");
        try writer.writeAll("\r\n");
    }

    try writer.writeAll("\r\n  j/k \u{2191}\u{2193}  navigate    enter  expand/collapse    q  quit\r\n");
}

pub fn enableRawMode() !std.posix.termios {
    const fd = std.posix.STDIN_FILENO;
    const orig = try std.posix.tcgetattr(fd);
    var raw = orig;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.oflag.OPOST = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(fd, .FLUSH, raw);
    return orig;
}

pub fn disableRawMode(orig: std.posix.termios) void {
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, orig) catch {};
}
