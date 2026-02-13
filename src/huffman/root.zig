const std = @import("std");

pub const Node = struct {
    data: ?u8,
    left: ?*Node,
    right: ?*Node,
    isChildNode: bool,
    freq: usize,
};

pub const Encode = struct {
    allocator: std.mem.Allocator,
    input: []u8,
    headNode: ?*Node,
    output: []u8,
    frequencyTable: std.AutoHashMap(u8, usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, input: []u8) !Self {
        return .{
            .allocator = allocator,
            .input = input,
            .frequencyTable = std.AutoHashMap(u8, usize).init(allocator),
            .headNode = null,
            .output = &[_]u8{},
        };
    }

    pub fn generateFields(self: *Self) !void {
        try self.buildFreq();

        self.headNode = try self.buildTree();

        if (self.headNode == null) return;
        var code_map = try self.generateCodes();
        defer {
            var it = code_map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.value_ptr.*);
            }

            code_map.deinit();
        }
        self.output = try self.encodeInput(code_map);
    }

    pub fn deinit(self: *Self) void {
        if (self.output.len > 0) self.allocator.free(self.output);
    }

    fn compareNodePtrs(context: void, a: *Node, b: *Node) std.math.Order {
        _ = context;
        return std.math.order(a.freq, b.freq);
    }

    pub fn buildFreq(self: *Self) !void {
        for (self.input) |b| {
            const prev = try self.frequencyTable.getOrPut(b);
            if (!prev.found_existing) {
                prev.value_ptr.* = 0;
            }
            prev.value_ptr.* += 1;
        }
    }

    fn buildTree(self: *Self) !?*Node {
        if (self.frequencyTable.count() == 0) return null;

        var heap = std.PriorityQueue(*Node, void, compareNodePtrs).init(self.allocator, {});

        var it = self.frequencyTable.iterator();

        while (it.next()) |entry| {
            const char_byte = entry.key_ptr.*;
            const frequency = entry.value_ptr.*;

            const node = try self.allocator.create(Node);

            node.* = Node{
                .data = char_byte,
                .freq = frequency,
                .left = null,
                .right = null,
                .isChildNode = true,
            };
            try heap.add(node);
        }

        while (heap.count() > 1) {
            const left_child = heap.remove();
            const right_child = heap.remove();

            const parent = try self.allocator.create(Node);
            parent.* = Node{
                .data = null,
                .freq = left_child.freq + right_child.freq,
                .left = left_child,
                .right = right_child,
                .isChildNode = false,
            };

            try heap.add(parent);
        }

        return heap.remove();
    }

    pub fn generateCodes(self: *Self) !std.AutoHashMap(u8, []const u8) {
        var map = std.AutoHashMap(u8, []const u8).init(self.allocator);
        var current_code = try std.ArrayList(u8).initCapacity(self.allocator, 50);
        defer current_code.deinit(self.allocator);

        if (self.headNode) |root| {
            try self.traverseTree(root, &current_code, &map);
        }

        return map;
    }

    fn traverseTree(self: *Self, node: *Node, prefix: *std.ArrayList(u8), map: *std.AutoHashMap(u8, []const u8)) !void {
        if (node.isChildNode) {
            if (node.data) |char_byte| {
                const code_str = try self.allocator.dupe(u8, prefix.items);
                try map.put(char_byte, code_str);
            }

            return;
        }

        if (node.left) |left_child| {
            try prefix.append(self.allocator, '0');
            try self.traverseTree(left_child, prefix, map);
            _ = prefix.pop();
        }

        if (node.right) |right_child| {
            try prefix.append(self.allocator, '1');
            try self.traverseTree(right_child, prefix, map);
            _ = prefix.pop();
        }
    }

    pub fn encodeInput(self: *Self, code_map: std.AutoHashMap(u8, []const u8)) ![]u8 {
        var output = try std.ArrayList(u8).initCapacity(self.allocator, 100);

        for (self.input) |char_byte| {
            if (code_map.get(char_byte)) |code| {
                try output.appendSlice(self.allocator, code);
            } else {
                std.log.err("Character '{c}' not found in map!", .{char_byte});
            }
        }

        return try output.toOwnedSlice(self.allocator);
    }

    pub fn decode(self: *Self) ![]u8 {
        var decoded = try std.ArrayList(u8).initCapacity(self.allocator, 50);

        var current_node = self.headNode orelse return error.TreeNotBuild;

        for (self.output) |bit| {
            if (bit == '0') {
                if (current_node.left) |left| {
                    current_node = left;
                }
            } else if (bit == '1') {
                if (current_node.right) |right| {
                    current_node = right;
                }
            } else {
                return error.InvalidBitInOutput;
            }

            if (current_node.isChildNode) {
                if (current_node.data) |char_byte| {
                    try decoded.append(self.allocator, char_byte);
                    current_node = self.headNode.?;
                }
            }
        }

        return try decoded.toOwnedSlice(self.allocator);
    }
};

pub const Decode = struct {
    allocator: std.mem.Allocator,
    encoded_input: []const u8,
    frequency_map: std.AutoHashMap(u8, usize),
    root: ?*Node,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, freq_map: std.AutoHashMap(u8, usize), input: []const u8) Self {
        return .{
            .allocator = allocator,
            .frequency_map = freq_map,
            .encoded_input = input,
            .root = null,
        };
    }

    fn compareNodePtrs(context: void, a: *Node, b: *Node) std.math.Order {
        _ = context;
        return std.math.order(a.freq, b.freq);
    }

    pub fn deinit(self: *Self) void {
        self.frequency_map.deinit();
    }

    pub fn rebuildTree(self: *Self) !void {
        var pq = std.PriorityQueue(*Node, void, compareNodePtrs).init(self.allocator, {});
        defer pq.deinit();

        var it = self.frequency_map.iterator();
        while (it.next()) |entry| {
            const node = try self.allocator.create(Node);
            node.* = Node{
                .data = entry.key_ptr.*,
                .freq = entry.value_ptr.*,
                .left = null,
                .right = null,
                .isChildNode = true,
            };

            try pq.add(node);
        }

        while (pq.count() > 1) {
            const left = pq.remove();
            const right = pq.remove();

            const parent = try self.allocator.create(Node);
            parent.* = Node{
                .data = null,
                .freq = left.freq + right.freq,
                .left = left,
                .right = right,
                .isChildNode = false,
            };

            try pq.add(parent);
        }

        self.root = pq.removeOrNull();
    }

    pub fn decode(self: *Self) ![]u8 {
        var decoded = try std.ArrayList(u8).initCapacity(self.allocator, 50);

        var current_node = self.root orelse return error.TreeNotBuild;

        for (self.encoded_input) |bit| {
            if (bit == '0') {
                if (current_node.left) |left| {
                    current_node = left;
                }
            } else if (bit == '1') {
                if (current_node.right) |right| {
                    current_node = right;
                }
            } else {
                return error.InvalidBitInOutput;
            }

            if (current_node.isChildNode) {
                if (current_node.data) |char_byte| {
                    try decoded.append(self.allocator, char_byte);
                    current_node = self.root.?;
                }
            }
        }

        return try decoded.toOwnedSlice(self.allocator);
    }
};
