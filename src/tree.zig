const std = @import("std");

pub const Node = struct {
    name: []const u8,
    size: u64,
    is_dir: bool,
    expanded: bool,
    children: std.ArrayListUnmanaged(*Node),
};

pub const VisibleItem = struct {
    node: *Node,
    depth: usize,
};

pub fn buildTree(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8, scanned: *usize) !*Node {
    scanned.* += 1;
    const trunc_name = if (name.len > 40) name[name.len - 40 ..] else name;
    var pbuf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&pbuf, "\r\x1b[KScanning... {d} dirs  {s}", .{ scanned.*, trunc_name }) catch pbuf[0..0];
    _ = std.posix.write(std.posix.STDERR_FILENO, msg) catch {};

    const node = try allocator.create(Node);
    node.* = .{
        .name = name,
        .size = 0,
        .is_dir = true,
        .expanded = false,
        .children = .{},
    };

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const stat = try dir.statFile(entry.name);
                const child = try allocator.create(Node);
                child.* = .{
                    .name = try allocator.dupe(u8, entry.name),
                    .size = stat.size,
                    .is_dir = false,
                    .expanded = false,
                    .children = .{},
                };
                try node.children.append(allocator, child);
                node.size += stat.size;
            },
            .directory => {
                var subdir = dir.openDir(entry.name, .{ .iterate = true }) catch |err| switch (err) {
                    error.AccessDenied, error.PermissionDenied => continue,
                    else => return err,
                };
                defer subdir.close();
                const child = try buildTree(allocator, subdir, try allocator.dupe(u8, entry.name), scanned);
                node.size += child.size;
                try node.children.append(allocator, child);
            },
            else => {},
        }
    }

    std.mem.sort(*Node, node.children.items, {}, struct {
        fn gt(_: void, a: *Node, b: *Node) bool {
            return a.size > b.size;
        }
    }.gt);

    return node;
}

pub fn collectVisible(node: *Node, depth: usize, allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(VisibleItem)) !void {
    for (node.children.items) |child| {
        try list.append(allocator, .{ .node = child, .depth = depth });
        if (child.is_dir and child.expanded) {
            try collectVisible(child, depth + 1, allocator, list);
        }
    }
}
