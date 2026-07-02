"""Settings window: Ollama model, active mode, hotkeys, permission status.

Main-thread only (the menubar app opens it via callAfter).
"""

from __future__ import annotations

import logging

import AppKit
import Foundation
import objc
from PyObjCTools import AppHelper

from ..config import Config
from ..hotkey import parse_key
from ..insert import accessibility_trusted
from ..ollama_api import list_models

log = logging.getLogger(__name__)

_W, _H = 460, 360
ACCESSIBILITY_PANE_URL = (
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
)


def _label(text: str, frame) -> AppKit.NSTextField:
    t = AppKit.NSTextField.alloc().initWithFrame_(frame)
    t.setStringValue_(text)
    t.setBezeled_(False)
    t.setDrawsBackground_(False)
    t.setEditable_(False)
    t.setSelectable_(False)
    return t


class SettingsController(AppKit.NSObject):
    """Owns the NSWindow; created once and reshown on demand."""

    def init(self):
        self = objc.super(SettingsController, self).init()
        if self is None:
            return None
        self.config = None
        self.on_saved = None
        self.window = None
        self._record_listener = None
        return self

    # -- construction -------------------------------------------------

    @objc.python_method
    def _build(self):
        style = AppKit.NSWindowStyleMaskTitled | AppKit.NSWindowStyleMaskClosable
        win = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            ((0, 0), (_W, _H)), style, AppKit.NSBackingStoreBuffered, False
        )
        win.setTitle_("FoldWise Voice Settings")
        win.setReleasedWhenClosed_(False)
        win.center()
        c = win.contentView()

        y = _H - 48

        c.addSubview_(_label("Ollama model:", ((20, y), (130, 22))))
        self.model_popup = AppKit.NSPopUpButton.alloc().initWithFrame_pullsDown_(
            ((155, y - 3), (280, 26)), False
        )
        c.addSubview_(self.model_popup)
        y -= 30
        self.model_note = _label("", ((155, y), (280, 18)))
        self.model_note.setFont_(AppKit.NSFont.systemFontOfSize_(10))
        self.model_note.setTextColor_(AppKit.NSColor.secondaryLabelColor())
        c.addSubview_(self.model_note)

        y -= 38
        c.addSubview_(_label("Active mode:", ((20, y), (130, 22))))
        self.mode_popup = AppKit.NSPopUpButton.alloc().initWithFrame_pullsDown_(
            ((155, y - 3), (280, 26)), False
        )
        c.addSubview_(self.mode_popup)

        y -= 44
        c.addSubview_(_label("Push-to-talk key:", ((20, y), (130, 22))))
        self.ptt_field = AppKit.NSTextField.alloc().initWithFrame_(
            ((155, y - 2), (180, 24))
        )
        c.addSubview_(self.ptt_field)
        btn = AppKit.NSButton.alloc().initWithFrame_(((340, y - 4), (95, 28)))
        btn.setTitle_("Record…")
        btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        btn.setTarget_(self)
        btn.setAction_(b"recordPtt:")
        c.addSubview_(btn)

        y -= 36
        c.addSubview_(_label("Toggle key:", ((20, y), (130, 22))))
        self.toggle_field = AppKit.NSTextField.alloc().initWithFrame_(
            ((155, y - 2), (180, 24))
        )
        self.toggle_field.setPlaceholderString_("empty = disabled")
        c.addSubview_(self.toggle_field)
        btn2 = AppKit.NSButton.alloc().initWithFrame_(((340, y - 4), (95, 28)))
        btn2.setTitle_("Record…")
        btn2.setBezelStyle_(AppKit.NSBezelStyleRounded)
        btn2.setTarget_(self)
        btn2.setAction_(b"recordToggle:")
        c.addSubview_(btn2)

        y -= 30
        hint = _label(
            "Key names: alt_r, cmd_r, ctrl_r, f19, … or a single character. "
            "Hold the push-to-talk key while speaking.",
            ((20, y - 8), (420, 28)),
        )
        hint.setFont_(AppKit.NSFont.systemFontOfSize_(10))
        hint.setTextColor_(AppKit.NSColor.secondaryLabelColor())
        c.addSubview_(hint)

        y -= 34
        self.pause_audio_check = AppKit.NSButton.alloc().initWithFrame_(
            ((20, y), (420, 22))
        )
        self.pause_audio_check.setButtonType_(AppKit.NSButtonTypeSwitch)
        self.pause_audio_check.setTitle_(
            "Pause music & mute other audio while dictating"
        )
        c.addSubview_(self.pause_audio_check)

        y -= 42
        self.ax_label = _label("", ((20, y), (280, 22)))
        self.ax_label.setFont_(AppKit.NSFont.systemFontOfSize_(11))
        c.addSubview_(self.ax_label)
        ax_btn = AppKit.NSButton.alloc().initWithFrame_(((285, y - 4), (150, 28)))
        ax_btn.setTitle_("Open Accessibility…")
        ax_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        ax_btn.setTarget_(self)
        ax_btn.setAction_(b"openAccessibility:")
        c.addSubview_(ax_btn)

        # Bottom row.
        edit_btn = AppKit.NSButton.alloc().initWithFrame_(((20, 16), (140, 30)))
        edit_btn.setTitle_("Edit modes.json…")
        edit_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        edit_btn.setTarget_(self)
        edit_btn.setAction_(b"openModesFile:")
        c.addSubview_(edit_btn)

        self.status_label = _label("", ((170, 22), (170, 20)))
        self.status_label.setFont_(AppKit.NSFont.systemFontOfSize_(11))
        c.addSubview_(self.status_label)

        save_btn = AppKit.NSButton.alloc().initWithFrame_(((350, 16), (90, 30)))
        save_btn.setTitle_("Save")
        save_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        save_btn.setKeyEquivalent_("\r")
        save_btn.setTarget_(self)
        save_btn.setAction_(b"save:")
        c.addSubview_(save_btn)

        self.window = win

    # -- populate + show ----------------------------------------------

    def showWithConfig_onSaved_(self, config: Config, on_saved):
        self.config = config
        self.on_saved = on_saved
        if self.window is None:
            self._build()
        self._populate()
        AppKit.NSApp.activateIgnoringOtherApps_(True)
        self.window.makeKeyAndOrderFront_(None)

    @objc.python_method
    def _populate(self):
        current = self.config.llm_model
        models = list_models()
        self.model_popup.removeAllItems()
        if models:
            self.model_popup.addItemsWithTitles_(models)
            self.model_note.setStringValue_(
                "Installed Ollama models. Applies to all LLM modes."
            )
        else:
            self.model_note.setStringValue_(
                "Ollama isn't running — showing the configured model only."
            )
        if current and current not in models:
            self.model_popup.addItemWithTitle_(current)
        if current:
            self.model_popup.selectItemWithTitle_(current)

        self.mode_popup.removeAllItems()
        self.mode_popup.addItemsWithTitles_(list(self.config.modes))
        self.mode_popup.selectItemWithTitle_(self.config.active_mode)

        self.ptt_field.setStringValue_(self.config.hotkey)
        self.toggle_field.setStringValue_(self.config.toggle_hotkey or "")
        self.pause_audio_check.setState_(
            AppKit.NSControlStateValueOn
            if self.config.pause_audio
            else AppKit.NSControlStateValueOff
        )
        self.status_label.setStringValue_("")
        self._refresh_ax()

    @objc.python_method
    def _refresh_ax(self):
        if accessibility_trusted():
            self.ax_label.setStringValue_("Accessibility: ✓ granted (auto-paste on)")
            self.ax_label.setTextColor_(AppKit.NSColor.systemGreenColor())
        else:
            self.ax_label.setStringValue_("Accessibility: ✗ missing (clipboard only)")
            self.ax_label.setTextColor_(AppKit.NSColor.systemOrangeColor())

    # -- key recording -------------------------------------------------

    @objc.python_method
    def _stop_record_listener(self):
        if self._record_listener is not None:
            self._record_listener.stop()
            self._record_listener = None

    @objc.python_method
    def _record_into(self, field):
        from pynput import keyboard

        # Only one recorder at a time — otherwise clicking Record… on both
        # fields would make the next keypress fill both.
        self._stop_record_listener()
        field.setStringValue_("press any key…")

        def on_press(key):
            name = getattr(key, "name", None)
            if name is None:
                name = getattr(key, "char", None) or ""
            AppHelper.callAfter(field.setStringValue_, name)
            return False  # one keypress, then stop the listener

        self._record_listener = keyboard.Listener(on_press=on_press)
        self._record_listener.start()

    def recordPtt_(self, _sender):
        self._record_into(self.ptt_field)

    def recordToggle_(self, _sender):
        self._record_into(self.toggle_field)

    # -- actions -------------------------------------------------------

    def openAccessibility_(self, _sender):
        url = Foundation.NSURL.URLWithString_(ACCESSIBILITY_PANE_URL)
        AppKit.NSWorkspace.sharedWorkspace().openURL_(url)

    def openModesFile_(self, _sender):
        AppKit.NSWorkspace.sharedWorkspace().openFile_(str(self.config.path.resolve()))

    def save_(self, _sender):
        self._stop_record_listener()
        ptt = self.ptt_field.stringValue().strip()
        toggle = self.toggle_field.stringValue().strip() or None
        try:
            parse_key(ptt)
            if toggle:
                parse_key(toggle)
        except ValueError as e:
            self.status_label.setStringValue_(f"⚠️ {e}")
            self.status_label.setTextColor_(AppKit.NSColor.systemRedColor())
            return

        model = self.model_popup.titleOfSelectedItem()
        if model:
            self.config.set_llm_model(model)
        self.config.set_active_mode(self.mode_popup.titleOfSelectedItem())
        self.config.hotkey = ptt
        self.config.toggle_hotkey = toggle
        self.config.pause_audio = bool(self.pause_audio_check.state())
        try:
            self.config.save()
        except Exception as e:
            log.exception("saving modes.json failed")
            self.status_label.setStringValue_(f"⚠️ save failed: {e}")
            self.status_label.setTextColor_(AppKit.NSColor.systemRedColor())
            return

        self.status_label.setStringValue_("Saved ✓")
        self.status_label.setTextColor_(AppKit.NSColor.systemGreenColor())
        if self.on_saved is not None:
            self.on_saved()
