//! The app hooks whose decisions need no SDL: key-ups and the quit question.
//! `app.zig` keeps one `AppHooks` and forwards SDL's events to it, so what a
//! key-up or a quit does is tested headless.

const std = @import("std");

/// The key-up and quit handlers an app may install (`app.setKeyUpHandler`,
/// `app.setQuitHandler`). Unset, a key-up does nothing and a quit ends the loop.
pub const AppHooks = struct {
    /// Called on every key-up with the SDL keycode (`SDLK_*`) and modifier
    /// mask (`SDL_KMOD_*`), beside the key-down handler. An app tells an Alt
    /// tap from the Alt of Alt+Tab with it.
    key_up: ?*const fn (key: u32, mods: u16) void = null,
    /// Asked when a quit is requested (`SDL_EVENT_QUIT`: ⌘Q, the app menu's
    /// Quit, a logout; or the main window's close button): true lets it end
    /// the loop, false keeps it running. `app.quit()` never asks.
    quit: ?*const fn () bool = null,

    /// Forward a key-up to the handler, if one is set.
    pub fn keyUp(self: AppHooks, key: u32, mods: u16) void {
        if (self.key_up) |f| f(key, mods);
    }

    /// A quit was requested: clear `running` unless the quit handler refuses.
    pub fn requestQuit(self: AppHooks, running: *bool) void {
        if (self.quit) |f| if (!f()) return;
        running.* = false;
    }
};

test "app hooks: a key-up reaches the handler with its keycode and modifiers" {
    const Probe = struct {
        var key: u32 = 0;
        var mods: u16 = 0;
        var calls: u32 = 0;
        fn up(k: u32, m: u16) void {
            key = k;
            mods = m;
            calls += 1;
        }
    };
    // None set: nothing is called.
    (AppHooks{}).keyUp(0x400000e2, 0x0100);
    try std.testing.expectEqual(@as(u32, 0), Probe.calls);
    (AppHooks{ .key_up = Probe.up }).keyUp(0x400000e2, 0x0100);
    try std.testing.expectEqual(@as(u32, 1), Probe.calls);
    try std.testing.expectEqual(@as(u32, 0x400000e2), Probe.key);
    try std.testing.expectEqual(@as(u16, 0x0100), Probe.mods);
}

test "app hooks: a refusing quit handler keeps the loop running" {
    const Probe = struct {
        var asked: u32 = 0;
        fn refuse() bool {
            asked += 1;
            return false;
        }
        fn accept() bool {
            asked += 1;
            return true;
        }
    };
    var running = true;
    (AppHooks{ .quit = Probe.refuse }).requestQuit(&running);
    try std.testing.expect(running);
    try std.testing.expectEqual(@as(u32, 1), Probe.asked);
    (AppHooks{ .quit = Probe.accept }).requestQuit(&running);
    try std.testing.expect(!running);
    try std.testing.expectEqual(@as(u32, 2), Probe.asked);
    // None set: a quit ends the loop.
    running = true;
    (AppHooks{}).requestQuit(&running);
    try std.testing.expect(!running);
}
