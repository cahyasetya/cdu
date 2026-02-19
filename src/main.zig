const std = @import("std");
const tree = @import("tree.zig");
const tui = @import("tui.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.args();
    _ = args.next(); // skip argv[0]
    const path = args.next() orelse ".";

    var dir = try std.fs.openDirAbsolute(
        if (std.fs.path.isAbsolute(path)) path else blk: {
            const cwd = try std.process.getCwdAlloc(allocator);
            break :blk try std.fs.path.join(allocator, &.{ cwd, path });
        },
        .{ .iterate = true },
    );
    defer dir.close();

    var scanned: usize = 0;
    const root = try tree.buildTree(allocator, dir, path, &scanned);
    _ = std.posix.write(std.posix.STDERR_FILENO, "\r\x1b[K") catch {};

    const orig = try tui.enableRawMode();
    defer tui.disableRawMode(orig);

    var out: std.ArrayListUnmanaged(u8) = .{};
    var selected: usize = 0;
    var viewport_top: usize = 0;
    var visible: std.ArrayListUnmanaged(tree.VisibleItem) = .{};

    while (true) {
        visible.clearRetainingCapacity();
        try tree.collectVisible(root, 0, allocator, &visible);
        const items = visible.items;

        const rows = tui.termRows();
        const visible_height = if (rows > tui.HEADER_LINES + tui.FOOTER_LINES + 1)
            rows - tui.HEADER_LINES - tui.FOOTER_LINES
        else
            1;

        if (selected < viewport_top) viewport_top = selected;
        if (selected >= viewport_top + visible_height) viewport_top = selected - visible_height + 1;

        out.clearRetainingCapacity();
        try tui.render(out.writer(allocator), root, items, selected, viewport_top, visible_height);
        _ = try std.posix.write(std.posix.STDOUT_FILENO, out.items);

        var buf: [4]u8 = undefined;
        const n = try std.posix.read(std.posix.STDIN_FILENO, &buf);
        if (n == 0) continue;

        const key = buf[0];

        if (key == 'q') break;

        if (key == 'k' or (n >= 3 and buf[0] == '\x1b' and buf[1] == '[' and buf[2] == 'A')) {
            if (selected > 0) selected -= 1;
        } else if (key == 'j' or (n >= 3 and buf[0] == '\x1b' and buf[1] == '[' and buf[2] == 'B')) {
            if (items.len > 0 and selected < items.len - 1) selected += 1;
        } else if (key == '\r' or key == '\n') {
            if (items.len > 0) {
                const node = items[selected].node;
                if (node.is_dir) node.expanded = !node.expanded;
            }
        }

        // Clamp after collapse
        visible.clearRetainingCapacity();
        try tree.collectVisible(root, 0, allocator, &visible);
        if (selected >= visible.items.len and visible.items.len > 0) {
            selected = visible.items.len - 1;
        }
    }

    _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[2J\x1b[H");
}
