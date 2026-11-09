//! Where a point in a window falls for the window manager: content, the
//! title bar's empty space (drags the window), or an edge or corner that
//! resizes it. Pure; `app.zig`'s SDL hit test maps the answer to
//! `SDL_HITTEST_*` for a window with a drag band or a custom title bar.

const std = @import("std");
const geometry = @import("layout/geometry.zig");
const view = @import("view/view.zig");

/// What a point does when pressed.
pub const WindowHit = enum {
    /// Content: the app gets the press.
    normal,
    /// Empty title bar: the press drags the window (a double click maximizes).
    draggable,
    resize_top_left,
    resize_top,
    resize_top_right,
    resize_right,
    resize_bottom_right,
    resize_bottom,
    resize_bottom_left,
    resize_left,
};

/// The window state a hit test needs.
pub const WindowHitArea = struct {
    /// The window's size, in the same points as the hit regions.
    size: geometry.Size,
    /// The top band whose empty space drags the window (0 = none).
    drag_band: f32 = 0,
    /// How far in from each edge a press resizes the window (0 = it doesn't:
    /// the OS frame does that, or the window is maximized).
    resize_edge: f32 = 0,
    /// Within the band, the frame's tap regions (they keep their clicks).
    hits: []const view.HitRegion = &.{},
    /// A popup (the text context menu) is open: everything is content.
    menu_open: bool = false,
    /// The window is fullscreen: everything is content (a fullscreen window
    /// neither resizes from its edges nor drags by its title bar).
    fullscreen: bool = false,

    /// What a press at `p` does: an edge or corner first, then the drag band's
    /// empty space; a tap region there (not an overlay's dismiss region nor a
    /// right-click-only one) keeps the click.
    pub fn at(self: WindowHitArea, p: geometry.Point) WindowHit {
        if (self.menu_open or self.fullscreen) return .normal;
        const e = self.resize_edge;
        if (e > 0) {
            const left = p.x < e;
            const right = p.x >= self.size.width - e;
            const top = p.y < e;
            const bottom = p.y >= self.size.height - e;
            if (top and left) return .resize_top_left;
            if (top and right) return .resize_top_right;
            if (bottom and left) return .resize_bottom_left;
            if (bottom and right) return .resize_bottom_right;
            if (top) return .resize_top;
            if (bottom) return .resize_bottom;
            if (left) return .resize_left;
            if (right) return .resize_right;
        }
        if (p.y >= self.drag_band) return .normal;
        for (self.hits) |h| {
            if (h.action == .secondary or h.action == .dismiss) continue;
            if (h.rect.contains(p)) return .normal;
        }
        return .draggable;
    }
};

test "window hit: edges and corners resize, the band drags, its controls keep their clicks" {
    const Probe = struct {
        fn noop(_: ?*anyopaque) void {}
    };
    var shown = true;
    const dismiss: view.Binding(bool) = .{ .ctx = &shown, .getFn = struct {
        fn get(ctx: *anyopaque) bool {
            return @as(*bool, @ptrCast(ctx)).*;
        }
    }.get, .setFn = struct {
        fn set(ctx: *anyopaque, v: bool) void {
            @as(*bool, @ptrCast(ctx)).* = v;
        }
    }.set };
    const hits = [_]view.HitRegion{
        // A menu title in the band, then a modal's dismiss region over everything.
        .{ .rect = .{ .x = 40, .y = 0, .width = 50, .height = 32 }, .action = .{ .callback = .{ .func = Probe.noop } }, .disabled = false },
        .{ .rect = .{ .x = 0, .y = 0, .width = 800, .height = 600 }, .action = .{ .dismiss = dismiss }, .disabled = false },
    };
    const area: WindowHitArea = .{ .size = .{ .width = 800, .height = 600 }, .drag_band = 32, .resize_edge = 6, .hits = &hits };
    try std.testing.expectEqual(WindowHit.resize_top_left, area.at(.{ .x = 2, .y = 2 }));
    try std.testing.expectEqual(WindowHit.resize_top, area.at(.{ .x = 400, .y = 3 }));
    try std.testing.expectEqual(WindowHit.resize_bottom_right, area.at(.{ .x = 797, .y = 597 }));
    try std.testing.expectEqual(WindowHit.resize_left, area.at(.{ .x = 1, .y = 300 }));
    try std.testing.expectEqual(WindowHit.resize_right, area.at(.{ .x = 795, .y = 300 }));
    // The band drags, even under the dismiss region; the title keeps its click.
    try std.testing.expectEqual(WindowHit.draggable, area.at(.{ .x = 400, .y = 16 }));
    try std.testing.expectEqual(WindowHit.normal, area.at(.{ .x = 60, .y = 16 }));
    // Below the band is content.
    try std.testing.expectEqual(WindowHit.normal, area.at(.{ .x = 400, .y = 300 }));
    // Maximized (no resize edge), the top edge drags instead.
    var maximized = area;
    maximized.resize_edge = 0;
    try std.testing.expectEqual(WindowHit.draggable, maximized.at(.{ .x = 400, .y = 2 }));
    // A popup open: everything is content.
    var popup = area;
    popup.menu_open = true;
    try std.testing.expectEqual(WindowHit.normal, popup.at(.{ .x = 400, .y = 16 }));
    // Fullscreen: neither an edge nor the band does anything.
    var fullscreen = area;
    fullscreen.fullscreen = true;
    try std.testing.expectEqual(WindowHit.normal, fullscreen.at(.{ .x = 2, .y = 2 }));
    try std.testing.expectEqual(WindowHit.normal, fullscreen.at(.{ .x = 400, .y = 16 }));
}
