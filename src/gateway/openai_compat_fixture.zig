const std = @import("std");
const io_mod = @import("../core/shared/io.zig");

const Allocator = std.mem.Allocator;

pub const Request = struct {
    method: []u8,
    path: []u8,
    headers: std.StringHashMap([]u8),
    body: []u8,
    raw: []u8,

    pub fn deinit(self: *Request, alloc: Allocator) void {
        alloc.free(self.method);
        alloc.free(self.path);
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        alloc.free(self.body);
        alloc.free(self.raw);
    }
};

pub const Response = struct {
    status: u16 = 200,
    headers: []const u8 = "Content-Type: text/event-stream\r\nCache-Control: no-cache\r\n",
    body: []const u8,
    owned: bool = false,
};

pub const Fixture = struct {
    alloc: Allocator,
    address: std.net.Address,
    listener: std.net.Address.ListenOptions.ListenError!std.net.Server,
    // Actually we will use std.net.Server
    server: std.net.Server,
    port: u16,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    requests: std.ArrayList(Request),
    responses: std.ArrayList(Response),
    next_idx: usize = 0,
    thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    done: bool = false,

    pub fn init(alloc: Allocator) !*Fixture {
        const self = try alloc.create(Fixture);
        self.* = .{
            .alloc = alloc,
            .address = undefined,
            .server = undefined,
            .port = 0,
            .requests = .empty,
            .responses = .empty,
        };
        // Bind to 127.0.0.1:0
        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        var server = try addr.listen(.{ .reuse_address = true });
        const listen_addr = server.listen_address;
        self.address = listen_addr;
        self.server = server;
        self.port = listen_addr.getPort();
        self.running.store(true, .seq_cst);
        self.thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
        return self;
    }

    pub fn deinit(self: *Fixture) void {
        self.running.store(false, .seq_cst);
        // Connect to self to unblock accept
        if (self.port != 0) {
            const addr = std.net.Address.parseIp("127.0.0.1", self.port) catch null;
            if (addr) |a| {
                const conn = std.net.tcpConnectToAddress(self.alloc, a, 1000) catch null;
                if (conn) |c| {
                    c.close();
                }
            }
        }
        if (self.thread) |t| t.join();
        self.server.deinit();
        for (self.requests.items) |*r| {
            var req = r.*;
            req.deinit(self.alloc);
        }
        self.requests.deinit(self.alloc);
        for (self.responses.items) |r| {
            if (r.owned) self.alloc.free(@constCast(r.body));
        }
        self.responses.deinit(self.alloc);
        self.alloc.destroy(self);
    }

    pub fn url(self: *Fixture) ![]u8 {
        return std.fmt.allocPrint(self.alloc, "http://127.0.0.1:{d}/v1/chat/completions", .{self.port});
    }

    pub fn pushResponse(self: *Fixture, resp: Response) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.responses.append(self.alloc, resp);
        self.cond.signal();
    }

    pub fn pushSseResponse(self: *Fixture, sse_body: []const u8) !void {
        const owned = try self.alloc.dupe(u8, sse_body);
        try self.pushResponse(.{ .status = 200, .body = owned, .owned = true });
    }

    pub fn waitForRequests(self: *Fixture, count: usize, timeout_ms: i64) !void {
        const start = io_mod.milliTimestamp();
        while (true) {
            self.mutex.lock();
            const n = self.requests.items.len;
            self.mutex.unlock();
            if (n >= count) return;
            if (io_mod.milliTimestamp() - start > timeout_ms) return error.Timeout;
            io_mod.sleep(10 * std.time.ns_per_ms);
        }
    }

    pub fn requestCount(self: *Fixture) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.requests.items.len;
    }

    fn acceptLoop(self: *Fixture) void {
        while (self.running.load(.seq_cst)) {
            const conn = self.server.accept() catch {
                if (!self.running.load(.seq_cst)) break;
                continue;
            };
            self.handleConn(conn) catch {};
        }
    }

    fn handleConn(self: *Fixture, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();
        var buf: [64 * 1024]u8 = undefined;
        var reader = conn.stream.reader(&buf);
        // Read request line and headers
        var req_buf: std.ArrayList(u8) = .empty;
        defer req_buf.deinit(self.alloc);
        // Simple: read until \r\n\r\n
        var header_end: usize = 0;
        var body_start: usize = 0;
        var content_length: usize = 0;
        var method: []u8 = &.{};
        var path: []u8 = &.{};
        // Read with timeout
        var total_read: usize = 0;
        while (true) {
            const n = reader.read(&buf) catch break;
            if (n == 0) break;
            try req_buf.appendSlice(self.alloc, buf[0..n]);
            total_read += n;
            if (std.mem.indexOf(u8, req_buf.items, "\r\n\r\n")) |idx| {
                header_end = idx;
                body_start = idx + 4;
                // Parse content-length
                const header_text = req_buf.items[0..idx];
                if (std.mem.indexOf(u8, header_text, "Content-Length:")) |cl_idx| {
                    const after = header_text[cl_idx + "Content-Length:".len ..];
                    const line_end = std.mem.indexOfScalar(u8, after, '\r') orelse after.len;
                    const val = std.mem.trim(u8, after[0..line_end], " \t");
                    content_length = std.fmt.parseInt(usize, val, 10) catch 0;
                }
                // Parse method/path
                const first_line_end = std.mem.indexOfScalar(u8, header_text, '\r') orelse 0;
                const first_line = header_text[0..first_line_end];
                var it = std.mem.splitScalar(u8, first_line, ' ');
                const m = it.next() orelse "";
                const p = it.next() orelse "";
                method = try self.alloc.dupe(u8, m);
                path = try self.alloc.dupe(u8, p);
                break;
            }
            if (total_read > 128 * 1024) break;
        }
        const raw_header = req_buf.items[0..header_end];
        // Read body if needed
        var body: []u8 = &.{};
        const already = if (req_buf.items.len > body_start) req_buf.items.len - body_start else 0;
        if (content_length > 0) {
            var body_buf = try self.alloc.alloc(u8, content_length);
            if (already > 0) {
                const copy_len = @min(already, content_length);
                @memcpy(body_buf[0..copy_len], req_buf.items[body_start .. body_start + copy_len]);
                var offset: usize = copy_len;
                while (offset < content_length) {
                    const n = reader.read(body_buf[offset..]) catch break;
                    if (n == 0) break;
                    offset += n;
                }
            } else {
                var offset: usize = 0;
                while (offset < content_length) {
                    const n = reader.read(body_buf[offset..]) catch break;
                    if (n == 0) break;
                    offset += n;
                }
            }
            body = body_buf;
        }
        // Capture headers map
        var headers = std.StringHashMap([]u8).init(self.alloc);
        const header_text = raw_header;
        var lines = std.mem.splitSequence(u8, header_text, "\r\n");
        _ = lines.next(); // skip request line
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
                const k = std.mem.trim(u8, line[0..colon], " \t");
                const v = std.mem.trim(u8, line[colon + 1 ..], " \t");
                const kd = try self.alloc.dupe(u8, k);
                const vd = try self.alloc.dupe(u8, v);
                try headers.put(kd, vd);
            }
        }
        const raw = try self.alloc.dupe(u8, req_buf.items);
        const req = Request{
            .method = method,
            .path = path,
            .headers = headers,
            .body = body,
            .raw = raw,
        };
        // Store request
        self.mutex.lock();
        try self.requests.append(self.alloc, req);
        const idx = self.next_idx;
        self.next_idx += 1;
        self.cond.signal();
        self.mutex.unlock();

        // Get response for this idx
        var resp: Response = undefined;
        var has_resp = false;
        // Wait for response to be queued
        var wait_start = io_mod.milliTimestamp();
        while (true) {
            self.mutex.lock();
            if (idx < self.responses.items.len) {
                resp = self.responses.items[idx];
                has_resp = true;
                self.mutex.unlock();
                break;
            }
            self.mutex.unlock();
            if (io_mod.milliTimestamp() - wait_start > 5000) break;
            io_mod.sleep(5 * std.time.ns_per_ms);
        }
        if (!has_resp) {
            // Unexpected request - send 500
            const body_500 = "unexpected request - no queued response";
            const header = try std.fmt.allocPrint(self.alloc, "HTTP/1.1 500 Internal Server Error\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{body_500.len});
            defer self.alloc.free(header);
            conn.stream.writeAll(header) catch {};
            conn.stream.writeAll(body_500) catch {};
            return;
        }
        // Send response
        const status_text: []const u8 = switch (resp.status) {
            200 => "OK",
            400 => "Bad Request",
            401 => "Unauthorized",
            429 => "Too Many Requests",
            500 => "Internal Server Error",
            else => "OK",
        };
        const header = try std.fmt.allocPrint(self.alloc, "HTTP/1.1 {d} {s}\r\n{s}Content-Length: {d}\r\nConnection: close\r\n\r\n", .{ resp.status, status_text, resp.headers, resp.body.len });
        defer self.alloc.free(header);
        conn.stream.writeAll(header) catch {};
        // For SSE, we may want to split writes to test fragmentation - but for now send all at once
        // The test will push body that is already fragmented across SSE chunks as separate data: lines
        conn.stream.writeAll(resp.body) catch {};
    }
};

test "fixture captures request and serves SSE" {
    const alloc = std.testing.allocator;
    const fixture = try Fixture.init(alloc);
    defer fixture.deinit();
    const url = try fixture.url();
    defer alloc.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, "http://127.0.0.1:"));

    // Push a simple SSE response
    const sse = "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\ndata: [DONE]\n\n";
    try fixture.pushSseResponse(sse);

    // Make a request via http client
    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();
    const uri = try std.Uri.parse(url);
    var req = try client.request(.POST, uri, .{});
    defer req.deinit();
    try req.sendBodilessHeaders();
    // Don't send body, just close
    _ = try req.receiveHead(&.{});
    try fixture.waitForRequests(1, 2000);
    try std.testing.expectEqual(@as(usize, 1), fixture.requestCount());
}
