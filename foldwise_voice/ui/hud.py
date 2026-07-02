"""Floating status pill.

Always visible: when idle it collapses to a tiny SuperWhisper-style bar with
dim, gently breathing level bars; while dictating it expands into the full
pill with the status dot, label, and live waveform.

The pill is interactive:
  * drag it anywhere — the position is saved to modes.json and restored,
  * hover over it to reveal a gear that opens Settings (idle pill grows a
    little on hover so the gear has room).

All methods must be called on the main (AppKit) thread — the menubar app
hops threads with AppHelper.callAfter before touching the HUD.
"""

from __future__ import annotations

import math

import AppKit
import Foundation
import objc

_W, _H = 340, 64            # expanded pill (listening / working / flash)
_MINI_W, _MINI_H = 90, 16   # collapsed idle pill
_HOVER_W, _HOVER_H = 150, 26  # idle pill grown on hover (room for the gear)
_BARS = 26
_MINI_BARS = 12
_GEAR = 18                  # gear glyph box, anchored to the right edge
_BOTTOM_MARGIN = 96
_DRAG_THRESHOLD = 3.0
_RESIZE_SECS = 0.18
_UNHOVER_DELAY = 0.18       # hysteresis: edge flicker must not re-trigger resizes


class _HUDView(AppKit.NSView):
    """Draws the pill: colored dot + label + live level bars + hover gear."""

    def initWithFrame_(self, frame):
        self = objc.super(_HUDView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.state = "idle"
        self.label = ""
        self.levels = [0.0] * _BARS
        self.phase = 0.0
        self.recorder = None
        self.hud = None
        self.hovering = False
        self.gear_rect = Foundation.NSMakeRect(0, 0, 0, 0)
        self._drag_start = None
        self._win_origin = None
        self._dragged = False
        opts = (
            AppKit.NSTrackingMouseEnteredAndExited
            | AppKit.NSTrackingActiveAlways
            | AppKit.NSTrackingInVisibleRect
        )
        area = AppKit.NSTrackingArea.alloc().initWithRect_options_owner_userInfo_(
            Foundation.NSMakeRect(0, 0, 0, 0), opts, self, None
        )
        self.addTrackingArea_(area)
        return self

    def tick_(self, _timer):
        self.phase += 0.15
        if self.state == "listening" and self.recorder is not None:
            level = self.recorder.level
        else:
            level = 0.0
        self.levels = self.levels[1:] + [level]
        self.setNeedsDisplay_(True)

    def isFlipped(self):
        return False

    def acceptsFirstMouse_(self, _event):
        return True  # react to the first click even when another app is active

    def drawRect_(self, _rect):
        b = self.bounds()
        w, h = b.size.width, b.size.height
        mini = self.state == "idle"

        pill = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            b, h / 2, h / 2
        )
        bg_alpha = 0.78 if mini else 0.94
        AppKit.NSColor.colorWithCalibratedWhite_alpha_(0.07, bg_alpha).setFill()
        pill.fill()
        AppKit.NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.10).setStroke()
        pill.setLineWidth_(1.0)
        pill.stroke()

        if not mini:
            if self.state == "listening":
                dot_color = AppKit.NSColor.systemRedColor()
            elif self.state in ("transcribing", "polishing"):
                dot_color = AppKit.NSColor.systemOrangeColor()
            elif self.state == "error":
                dot_color = AppKit.NSColor.systemYellowColor()
            else:
                dot_color = AppKit.NSColor.systemGreenColor()

            # Pulsing status dot.
            pulse = 0.72 + 0.28 * (0.5 + 0.5 * math.sin(self.phase * 2))
            dot_color.colorWithAlphaComponent_(pulse).setFill()
            r = 5.0
            AppKit.NSBezierPath.bezierPathWithOvalInRect_(
                ((22, h / 2 + 8 - r), (2 * r, 2 * r))
            ).fill()

            # Label.
            attrs = {
                AppKit.NSFontAttributeName: AppKit.NSFont.systemFontOfSize_weight_(
                    13, AppKit.NSFontWeightSemibold
                ),
                AppKit.NSForegroundColorAttributeName: AppKit.NSColor.whiteColor(),
            }
            s = Foundation.NSString.stringWithString_(self.label)
            s.drawAtPoint_withAttributes_((40, h / 2 + 1), attrs)

        # Level bars (waveform while listening, gentle wave while working,
        # dim slow breathing while idle).
        n = _MINI_BARS if mini else _BARS
        levels = self.levels[-n:]
        if mini:
            bar_w, gap = 3.0, 2.0
            AppKit.NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.45).setFill()
        else:
            bar_w, gap = 4.0, 3.0
            AppKit.NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.85).setFill()
        total = n * bar_w + (n - 1) * gap
        x0 = (w - total) / 2
        for i in range(n):
            if self.state == "listening":
                lvl = min(1.0, (levels[i] ** 0.5) * 1.6)
                bh = 2.0 + lvl * 14.0
            elif self.state in ("transcribing", "polishing"):
                bh = 4.0 + 5.0 * (0.5 + 0.5 * math.sin(self.phase + i * 0.55))
            elif mini:
                bh = 2.0 + 3.0 * (0.5 + 0.5 * math.sin(self.phase * 0.6 + i * 0.4))
            else:
                bh = 2.5
            base_y = (h - bh) / 2 if mini else 12.0
            rect = ((x0 + i * (bar_w + gap), base_y), (bar_w, bh))
            AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
                rect, bar_w / 2, bar_w / 2
            ).fill()

        # Hover-only settings gear, anchored to the right edge.
        if self.hovering:
            g = _GEAR
            self.gear_rect = Foundation.NSMakeRect(w - g - 7, (h - g) / 2, g, g)
            AppKit.NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.14).setFill()
            AppKit.NSBezierPath.bezierPathWithOvalInRect_(self.gear_rect).fill()
            attrs = {
                AppKit.NSFontAttributeName: AppKit.NSFont.systemFontOfSize_(12),
                AppKit.NSForegroundColorAttributeName: (
                    AppKit.NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.9)
                ),
            }
            glyph = Foundation.NSString.stringWithString_("⚙")
            size = glyph.sizeWithAttributes_(attrs)
            gx = self.gear_rect.origin.x + (g - size.width) / 2
            gy = self.gear_rect.origin.y + (g - size.height) / 2
            glyph.drawAtPoint_withAttributes_((gx, gy), attrs)
        else:
            self.gear_rect = Foundation.NSMakeRect(0, 0, 0, 0)

    # -- hover -----------------------------------------------------------

    def mouseEntered_(self, _event):
        if self.hud is not None:
            self.hud._set_hover(True)

    def mouseExited_(self, _event):
        if self.hud is not None:
            self.hud._set_hover(False)

    # -- drag / click ------------------------------------------------------

    def mouseDown_(self, _event):
        self._drag_start = AppKit.NSEvent.mouseLocation()
        self._win_origin = self.window().frame().origin
        self._dragged = False

    def mouseDragged_(self, _event):
        if self._drag_start is None:
            return
        loc = AppKit.NSEvent.mouseLocation()
        dx = loc.x - self._drag_start.x
        dy = loc.y - self._drag_start.y
        if abs(dx) > _DRAG_THRESHOLD or abs(dy) > _DRAG_THRESHOLD:
            self._dragged = True
        if self._dragged:
            self.window().setFrameOrigin_(
                (self._win_origin.x + dx, self._win_origin.y + dy)
            )
            if self.hud is not None:
                # Keep the anchor in sync while dragging so nothing that
                # resizes the pill mid-drag can snap it back to where the
                # drag started.
                self.hud._anchor_from_frame()

    def mouseUp_(self, event):
        if self.hud is None:
            return
        if self._dragged:
            self.hud._position_dragged()
        else:
            p = self.convertPoint_fromView_(event.locationInWindow(), None)
            if self.hovering and Foundation.NSPointInRect(p, self.gear_rect):
                self.hud._open_settings()
        self._drag_start = None
        # A hover change during the drag was deferred — apply it now.
        self.hud._sync_hover_size()

    # One-shot timer target: drop back to the idle mini pill after a flash.
    def hideTick_(self, _timer):
        if self.hud is not None:
            self.hud.idle()

    # One-shot timer target: hover-exit hysteresis elapsed.
    def unhoverTick_(self, _timer):
        if self.hud is not None:
            self.hud._apply_hover(False)


class HUD:
    def __init__(self, config=None, on_settings=None):
        self.config = config
        self.on_settings = on_settings
        self.panel = None
        self.view = None
        self._timer = None
        self._hide_timer = None
        self._unhover_timer = None
        self._hovering = False
        # Anchor: (center_x, bottom_y) of the pill in screen coordinates.
        self._anchor = None
        if config is not None and config.hud_position:
            self._anchor = tuple(config.hud_position)

    def _ensure_panel(self):
        if self.panel is not None:
            return
        rect = ((0, 0), (_W, _H))
        panel = AppKit.NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            rect,
            AppKit.NSWindowStyleMaskBorderless | AppKit.NSWindowStyleMaskNonactivatingPanel,
            AppKit.NSBackingStoreBuffered,
            False,
        )
        panel.setLevel_(AppKit.NSStatusWindowLevel)
        panel.setOpaque_(False)
        panel.setBackgroundColor_(AppKit.NSColor.clearColor())
        panel.setHasShadow_(True)
        panel.setIgnoresMouseEvents_(False)
        panel.setHidesOnDeactivate_(False)
        panel.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorFullScreenAuxiliary
        )
        view = _HUDView.alloc().initWithFrame_(rect)
        view.hud = self
        panel.setContentView_(view)
        self.panel, self.view = panel, view
        self._set_size(_MINI_W, _MINI_H, animate=False)

    def _default_anchor(self) -> tuple[float, float]:
        screen = AppKit.NSScreen.mainScreen()
        if screen is not None:
            f = screen.visibleFrame()
            return (f.origin.x + f.size.width / 2, f.origin.y + _BOTTOM_MARGIN)
        return (400.0, _BOTTOM_MARGIN)

    @staticmethod
    def _screen_frame_at(cx: float, yb: float):
        """visibleFrame of the screen containing the anchor (fallback: main)."""
        for s in AppKit.NSScreen.screens():
            f = s.frame()
            if (
                f.origin.x <= cx <= f.origin.x + f.size.width
                and f.origin.y <= yb <= f.origin.y + f.size.height
            ):
                return s.visibleFrame()
        screen = AppKit.NSScreen.mainScreen()
        return screen.visibleFrame() if screen is not None else None

    def _set_size(self, w: float, h: float, animate: bool = True):
        """Resize the pill around its anchor (center-x, bottom-y), clamped
        to the visible frame of the screen it sits on."""
        cx, yb = self._anchor or self._default_anchor()
        x, y = cx - w / 2, yb
        f = self._screen_frame_at(cx, yb)
        if f is not None:
            x = max(f.origin.x + 4, min(x, f.origin.x + f.size.width - w - 4))
            y = max(f.origin.y + 4, min(y, f.origin.y + f.size.height - h - 4))
        frame = Foundation.NSMakeRect(x, y, w, h)
        if animate:
            # animator() is asynchronous — setFrame_display_animate_ would
            # block the main thread and queue mouse events, which is what
            # made hover/drag on the mini pill stutter and replay animations.
            AppKit.NSAnimationContext.beginGrouping()
            AppKit.NSAnimationContext.currentContext().setDuration_(_RESIZE_SECS)
            self.panel.animator().setFrame_display_(frame, True)
            AppKit.NSAnimationContext.endGrouping()
        else:
            self.panel.setFrame_display_(frame, True)

    def _start_timer(self):
        if self._timer is None:
            self._timer = (
                Foundation.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                    1 / 30.0, self.view, b"tick:", None, True
                )
            )

    def _cancel_hide(self):
        if self._hide_timer is not None:
            self._hide_timer.invalidate()
            self._hide_timer = None

    # -- hover / drag / settings (called by the view) ---------------------

    def _set_hover(self, on: bool):
        self._cancel_unhover()
        if on:
            self._apply_hover(True)
        else:
            # Delay the shrink: a cursor grazing the pill's edge (or briefly
            # outrunning it during a drag) must not start a shrink/grow loop.
            self._unhover_timer = (
                Foundation.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                    _UNHOVER_DELAY, self.view, b"unhoverTick:", None, False
                )
            )

    def _apply_hover(self, on: bool):
        if on == self._hovering:
            return
        self._hovering = on
        self.view.hovering = on
        if self.view.state == "idle" and self.view._drag_start is None:
            w, h = (_HOVER_W, _HOVER_H) if on else (_MINI_W, _MINI_H)
            self._set_size(w, h)
        self.view.setNeedsDisplay_(True)

    def _cancel_unhover(self):
        if self._unhover_timer is not None:
            self._unhover_timer.invalidate()
            self._unhover_timer = None

    def _anchor_from_frame(self):
        """Track the pill's live position as its anchor (used mid-drag)."""
        f = self.panel.frame()
        self._anchor = (f.origin.x + f.size.width / 2, f.origin.y)

    def _sync_hover_size(self):
        """Re-apply the size for the current hover state (after a drag)."""
        if self.view.state == "idle":
            w, h = (_HOVER_W, _HOVER_H) if self._hovering else (_MINI_W, _MINI_H)
            self._set_size(w, h)

    def _position_dragged(self):
        """A drag ended — remember (and persist) the new anchor."""
        f = self.panel.frame()
        self._anchor = (f.origin.x + f.size.width / 2, f.origin.y)
        if self.config is not None:
            self.config.hud_position = [round(v, 1) for v in self._anchor]
            try:
                self.config.save()
            except Exception:
                pass  # position still applies for this session

    def _open_settings(self):
        if self.on_settings is not None:
            self.on_settings()

    # -- public API --------------------------------------------------------

    def idle(self) -> None:
        """Collapse to the always-visible mini pill."""
        self._ensure_panel()
        self._cancel_hide()
        self.view.state = "idle"
        self.view.label = ""
        self.view.recorder = None
        self._start_timer()
        if self._hovering:
            self._set_size(_HOVER_W, _HOVER_H)
        else:
            self._set_size(_MINI_W, _MINI_H)
        self.panel.orderFrontRegardless()

    def show(self, state: str, label: str, recorder=None) -> None:
        self._ensure_panel()
        self._cancel_hide()
        expanding = self.view.state == "idle"
        self.view.state = state
        self.view.label = label
        self.view.recorder = recorder
        self._start_timer()
        if expanding or self.panel.frame().size.width != _W:
            self._set_size(_W, _H)
        self.panel.orderFrontRegardless()

    def flash(self, state: str, label: str, seconds: float = 1.4) -> None:
        """Show a final status briefly, then collapse back to the mini pill."""
        self.show(state, label)
        self._hide_timer = (
            Foundation.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                seconds, self.view, b"hideTick:", None, False
            )
        )

    def hide(self) -> None:
        """Fully remove the pill (used on quit)."""
        self._cancel_hide()
        self._cancel_unhover()
        if self._timer is not None:
            self._timer.invalidate()
            self._timer = None
        if self.panel is not None:
            self.panel.orderOut_(None)
