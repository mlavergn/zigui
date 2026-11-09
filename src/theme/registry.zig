//! Theme registry: the catalog of built-in theme families and the logic that
//! resolves one to a concrete `Theme` for the current OS color scheme.
//!
//! A *family* (macOS, Windows 10, …) ships a light and a dark palette.
//! `forScheme` picks the right one, so the app can wire the OS appearance
//! (`app.systemTheme()`) straight through.

const std = @import("std");
const theme = @import("theme.zig");
const macos = @import("macos.zig");
const win2000 = @import("win2000.zig");
const windows10 = @import("windows10.zig");
const kde = @import("kde.zig");
const mui = @import("mui.zig");

const Theme = theme.Theme;
const ColorScheme = theme.ColorScheme;

/// The built-in theme families.
pub const Family = enum {
    macos,
    windows10,
    win2000,
    kde,
    mui,

    /// A human-readable name for menus/switchers.
    pub fn displayName(self: Family) []const u8 {
        return switch (self) {
            .macos => "macOS",
            .windows10 => "Windows 10",
            .win2000 => "Windows 2000",
            .kde => "KDE Plasma",
            .mui => "Material",
        };
    }
};

/// Resolve a family to a concrete `Theme` for `scheme`.
pub fn forScheme(family: Family, scheme: ColorScheme) Theme {
    const dark = scheme == .dark;
    return switch (family) {
        .macos => if (dark) macos.dark else macos.light,
        .windows10 => if (dark) windows10.dark else windows10.light,
        .win2000 => if (dark) win2000.dark else win2000.light,
        .kde => if (dark) kde.dark else kde.light,
        .mui => if (dark) mui.dark else mui.light,
    };
}

/// All families, in display order (handy for building a theme switcher).
pub const all = [_]Family{ .macos, .windows10, .win2000, .kde, .mui };

const testing = std.testing;

test "registry: every family has a dark palette" {
    for (all) |f| try testing.expectEqual(ColorScheme.dark, forScheme(f, .dark).scheme);
}

test "registry: macOS follows the requested scheme" {
    try testing.expectEqual(ColorScheme.dark, forScheme(.macos, .dark).scheme);
    try testing.expectEqual(ColorScheme.light, forScheme(.macos, .light).scheme);
}

test "registry: every family resolves and names itself" {
    for (all) |f| {
        const t = forScheme(f, .light);
        try testing.expect(t.name.len > 0);
        try testing.expect(f.displayName().len > 0);
    }
}

test "registry: each family draws its own title bar, with text that reads on it" {
    const Canvas = @import("../render/canvas.zig").Canvas;
    const raster = @import("../render/raster.zig");
    const Color = @import("../render/color.zig").Color;
    for (all) |f| {
        for ([_]ColorScheme{ .light, .dark }) |scheme| {
            const t = forScheme(f, scheme);
            var canvas = Canvas.init(testing.allocator);
            defer canvas.deinit();
            const rect = @import("../layout/geometry.zig").Rect{ .x = 0, .y = 0, .width = 100, .height = 32 };
            try t.drawTitleBar(.{ .canvas = &canvas, .palette = &t.colors, .metrics = &t.metrics, .scheme = t.scheme }, rect);
            var fb = try raster.Framebuffer.init(testing.allocator, 100, 32);
            defer fb.deinit();
            fb.clear(Color.fromRgb8(255, 0, 255));
            try raster.render(testing.allocator, &fb, canvas.commands.items);
            // The whole bar is painted (no magenta left), and its text contrasts with it.
            const bar = fb.at(10, 10);
            try testing.expect(!bar.approxEql(Color.fromRgb8(255, 0, 255), 0.05));
            const text = t.titleBarForeground();
            try testing.expect(@abs(text.luminance() - bar.luminance()) > 0.3);
        }
    }
    // Windows 2000's caption runs navy to sky blue, white text on it.
    const w2k = forScheme(.win2000, .light);
    try testing.expect(w2k.titleBarForeground().approxEql(Color.white, 0.01));
    // Material's bar is the accent, with on-accent text.
    const material = forScheme(.mui, .dark);
    try testing.expect(material.titleBarForeground().approxEql(material.colors.on_accent, 0.01));
}
