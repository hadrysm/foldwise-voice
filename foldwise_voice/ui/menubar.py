"""Menu-bar app: status icon, mode switcher, settings, HUD wiring.

Pipeline/hotkey events arrive on worker threads and are hopped onto the
AppKit main thread with AppHelper.callAfter.
"""

from __future__ import annotations

import logging

import AppKit
import objc
from PyObjCTools import AppHelper

from ..config import Config
from ..hotkey import HotkeyListener
from ..pipeline import Pipeline
from .hud import HUD
from .settings import SettingsController

log = logging.getLogger(__name__)

ICON_IDLE = "🎤"
ICON_LISTENING = "🔴"
ICON_WORKING = "⏳"

# TCP port used as a single-instance mutex (bound for the app's lifetime).
_LOCK_PORT = 47812

_KEY_LABELS = {
    "alt_r": "right ⌥",
    "alt_l": "left ⌥",
    "cmd_r": "right ⌘",
    "cmd_l": "left ⌘",
    "ctrl_r": "right ⌃",
    "ctrl_l": "left ⌃",
    "shift_r": "right ⇧",
}


def _pretty_key(name: str) -> str:
    return _KEY_LABELS.get(name, name)


class MenuBarApp(AppKit.NSObject):
    def init(self):
        self = objc.super(MenuBarApp, self).init()
        if self is None:
            return None
        self.config = None
        self.pipeline = None
        self.listener = None
        self.hud = None
        self.settings = None
        self.status_item = None
        self._mode_items = []
        return self

    # -- setup ---------------------------------------------------------

    @objc.python_method
    def setupWithConfig_(self, config: Config):
        self.config = config
        self.hud = HUD(config=config, on_settings=lambda: self.openSettings_(None))
        self.settings = SettingsController.alloc().init()
        self.pipeline = Pipeline(config, on_state=self._on_state_bg)
        self._start_listener()
        self._build_status_item()

    @objc.python_method
    def _start_listener(self):
        if self.listener is not None:
            self.listener.stop()
        self.listener = HotkeyListener(
            ptt_key=self.config.hotkey,
            on_press=self.pipeline.start_recording,
            on_release=self.pipeline.stop_recording,
            toggle_key=self.config.toggle_hotkey,
            on_toggle=self.pipeline.toggle_recording,
        )
        self.listener.start()

    @objc.python_method
    def _build_status_item(self):
        bar = AppKit.NSStatusBar.systemStatusBar()
        self.status_item = bar.statusItemWithLength_(AppKit.NSVariableStatusItemLength)
        self.status_item.button().setTitle_(ICON_IDLE)

        menu = AppKit.NSMenu.alloc().init()
        menu.setAutoenablesItems_(False)

        header = AppKit.NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "FoldWise Voice", None, ""
        )
        header.setEnabled_(False)
        menu.addItem_(header)
        menu.addItem_(AppKit.NSMenuItem.separatorItem())

        self._mode_items = []
        for name in self.config.modes:
            item = AppKit.NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                name, b"switchMode:", ""
            )
            item.setTarget_(self)
            menu.addItem_(item)
            self._mode_items.append(item)

        menu.addItem_(AppKit.NSMenuItem.separatorItem())

        settings_item = AppKit.NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Settings…", b"openSettings:", ","
        )
        settings_item.setTarget_(self)
        menu.addItem_(settings_item)

        menu.addItem_(AppKit.NSMenuItem.separatorItem())
        quit_item = AppKit.NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Quit FoldWise Voice", b"quitApp:", "q"
        )
        quit_item.setTarget_(self)
        menu.addItem_(quit_item)

        self.status_item.setMenu_(menu)
        self._refresh_mode_checks()

    @objc.python_method
    def _refresh_mode_checks(self):
        for item in self._mode_items:
            on = item.title() == self.config.active_mode
            item.setState_(
                AppKit.NSControlStateValueOn if on else AppKit.NSControlStateValueOff
            )

    # -- pipeline state (background thread → main thread) ---------------

    @objc.python_method
    def _on_state_bg(self, state: str, detail: str):
        AppHelper.callAfter(self._applyState, state, detail)

    @objc.python_method
    def _applyState(self, state: str, detail: str):
        button = self.status_item.button()
        if state == "listening":
            button.setTitle_(ICON_LISTENING)
            self.hud.show("listening", f"Listening…  ({detail})", self.pipeline.recorder)
        elif state == "transcribing":
            button.setTitle_(ICON_WORKING)
            self.hud.show("transcribing", "Transcribing…")
        elif state == "polishing":
            button.setTitle_(ICON_WORKING)
            self.hud.show("polishing", f"Polishing with {detail}…")
        elif state == "inserted":
            button.setTitle_(ICON_IDLE)
            self.hud.flash("done", "Inserted ✓")
        elif state == "clipboard":
            button.setTitle_(ICON_IDLE)
            self.hud.flash("done", "Copied — press ⌘V to paste", seconds=2.5)
        elif state == "error":
            button.setTitle_(ICON_IDLE)
            self.hud.flash("error", "Something went wrong — see logs", seconds=2.5)
        else:  # idle
            button.setTitle_(ICON_IDLE)
            self.hud.idle()

    # -- menu actions ----------------------------------------------------

    def switchMode_(self, sender):
        try:
            self.config.set_active_mode(sender.title())
            self.config.save()
        except Exception:
            log.exception("mode switch failed")
        self._refresh_mode_checks()

    def openSettings_(self, _sender):
        self.settings.showWithConfig_onSaved_(self.config, self._settings_saved)

    @objc.python_method
    def _settings_saved(self):
        # Hotkeys and/or mode may have changed — re-register and refresh.
        self._start_listener()
        self._refresh_mode_checks()

    def quitApp_(self, _sender):
        try:
            if self.listener is not None:
                self.listener.stop()
            if self.pipeline is not None:
                self.pipeline.shutdown()
        finally:
            AppKit.NSApp.terminate_(None)


def run_app(config: Config) -> None:
    import socket

    app = AppKit.NSApplication.sharedApplication()
    app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", _LOCK_PORT))
    except OSError:
        app.activateIgnoringOtherApps_(True)
        alert = AppKit.NSAlert.alloc().init()
        alert.setMessageText_("FoldWise Voice is already running")
        alert.setInformativeText_(
            "Look for the 🎤 icon in the menu bar — on notched MacBooks it can "
            "be hidden if the bar is full (⌘-drag other icons to make room).\n\n"
            f"Hold {_pretty_key(config.hotkey)} anywhere to dictate."
        )
        alert.runModal()
        return

    controller = MenuBarApp.alloc().init()
    controller.setupWithConfig_(config)
    # Keep references alive for the app's lifetime.
    global _controller, _instance_lock
    _controller = controller
    _instance_lock = lock
    log.info("menu-bar UI running (mode: %s)", config.active_mode)
    controller.hud.flash(
        "done",
        f"FoldWise Voice ready — hold {_pretty_key(config.hotkey)} to dictate",
        seconds=4.0,
    )
    AppHelper.runEventLoop()
