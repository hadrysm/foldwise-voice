import AppKit
import QuartzCore
import SwiftUI

struct StatsCalendarGridView: NSViewRepresentable {
    let month: StatsProjection.Month
    let environment: StatsEnvironmentAdaptations
    let hoveredDate: Date?
    let rovingDate: Date?
    let focusedDate: Date?
    let performance: PaneNavigationPerformance
    let marksFirstMeaningfulFrame: Bool
    let onHover: (Date?) -> Void
    let onFocus: (Date?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> StatsCalendarGridNSView {
        let view = StatsCalendarGridNSView()
        context.coordinator.connect(to: view)
        return view
    }

    func updateNSView(
        _ view: StatsCalendarGridNSView,
        context: Context
    ) {
        context.coordinator.parent = self
        view.update(
            StatsCalendarGridState(
                month: month,
                environment: environment,
                hoveredDate: hoveredDate,
                rovingDate: rovingDate,
                focusedDate: focusedDate,
                marksFirstMeaningfulFrame: marksFirstMeaningfulFrame
            ),
            performance: performance
        )
    }

    @MainActor
    final class Coordinator {
        var parent: StatsCalendarGridView

        init(parent: StatsCalendarGridView) {
            self.parent = parent
        }

        func connect(to view: StatsCalendarGridNSView) {
            view.onHover = { [weak self] date in
                self?.parent.onHover(date)
            }
            view.onFocus = { [weak self] date in
                self?.parent.onFocus(date)
            }
        }
    }
}

private struct StatsCalendarGridState {
    let month: StatsProjection.Month
    let environment: StatsEnvironmentAdaptations
    let hoveredDate: Date?
    let rovingDate: Date?
    let focusedDate: Date?
    let marksFirstMeaningfulFrame: Bool
}

@MainActor
final class StatsCalendarGridNSView: NSView {
    var onHover: ((Date?) -> Void)?
    var onFocus: ((Date?) -> Void)?

    private var month: StatsProjection.Month?
    private var environment = StatsEnvironmentAdaptations(
        reduceMotion: false,
        increaseContrast: false
    )
    private var hoveredDate: Date?
    private var rovingDate: Date?
    private var focusedDate: Date?
    private var performance: PaneNavigationPerformance?
    private var marksFirstMeaningfulFrame = false
    private var dayAccessibilityElements: [DayAccessibilityElement] = []
    private var trackingAreaReference: NSTrackingArea?
    private let focusView = StatsCalendarFocusNSView()

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusView.owner = self
        addSubview(focusView)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    fileprivate func update(
        _ state: StatsCalendarGridState,
        performance: PaneNavigationPerformance
    ) {
        let month = state.month
        let environment = state.environment
        let hadMonth = self.month != nil
        let monthChanged = self.month?.days != month.days
        let shouldCrossfade = hadMonth && monthChanged && !environment.reduceMotion
        self.month = month
        self.environment = environment
        hoveredDate = state.hoveredDate
        rovingDate = state.rovingDate
        focusedDate = state.focusedDate
        self.performance = performance
        marksFirstMeaningfulFrame = state.marksFirstMeaningfulFrame
        setAccessibilityLabel(month.accessibilityLabel)
        setAccessibilityValueDescription(month.accessibilityValue)
        setAccessibilityIdentifier("stats.calendar")
        if monthChanged {
            reconcileAccessibilityElements()
        } else {
            updateAccessibilityChildren()
            updateAccessibilityFocus()
        }
        needsLayout = true
        needsDisplay = true
        if shouldCrossfade {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.16
            layer?.add(transition, forKey: "stats-calendar-update")
        }
        synchronizeFocus()
    }

    override func layout() {
        super.layout()
        guard let month else { return }
        let layout = StatsCalendarLayout(
            width: bounds.width,
            leadingColumnOffset: month.leadingColumnOffset,
            dayCount: month.days.count
        )
        for dayElement in dayAccessibilityElements {
            dayElement.element.setAccessibilityFrameInParentSpace(
                layout.dayFrame(at: dayElement.index)
            )
        }
        updateFocusView(layout: layout)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let month else { return }
        let layout = StatsCalendarLayout(
            width: bounds.width,
            leadingColumnOffset: month.leadingColumnOffset,
            dayCount: month.days.count
        )
        drawWeekdays(month.weekdays, layout: layout)
        for index in month.days.indices {
            drawDay(month.days[index], at: layout.dayFrame(at: index))
        }
        if marksFirstMeaningfulFrame {
            performance?.firstMeaningfulFrame(for: .stats)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let month else { return }
        let point = convert(event.locationInWindow, from: nil)
        let layout = StatsCalendarLayout(
            width: bounds.width,
            leadingColumnOffset: month.leadingColumnOffset,
            dayCount: month.days.count
        )
        let hovered = month.days.indices.first { index in
            month.days[index].state != .future
                && layout.dayFrame(at: index).contains(point)
        }.map { month.days[$0].date }
        guard hovered != hoveredDate else { return }
        hoveredDate = hovered
        onHover?(hovered)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredDate != nil else { return }
        hoveredDate = nil
        onHover?(nil)
        needsDisplay = true
    }

    fileprivate func focusViewDidFocus() {
        guard let rovingDate else { return }
        focusedDate = rovingDate
        updateAccessibilityFocus()
        onFocus?(rovingDate)
        needsDisplay = true
    }

    fileprivate func focusViewDidResign() {
        focusedDate = nil
        updateAccessibilityFocus()
        onFocus?(nil)
        needsDisplay = true
    }

    fileprivate func moveFocus(_ direction: CalendarFocusNavigator.Direction) {
        guard let month, let focusedDate else { return }
        let eligibleDates = month.days
            .filter { $0.state != .future }
            .map(\.date)
        let navigator = CalendarFocusNavigator(eligibleDates: eligibleDates)
        guard let next = navigator.move(from: focusedDate, direction: direction)
        else { return }
        rovingDate = next
        self.focusedDate = next
        let layout = StatsCalendarLayout(
            width: bounds.width,
            leadingColumnOffset: month.leadingColumnOffset,
            dayCount: month.days.count
        )
        updateFocusView(layout: layout)
        updateAccessibilityChildren()
        updateAccessibilityFocus()
        onFocus?(next)
        needsDisplay = true
    }

    private func reconcileAccessibilityElements() {
        guard let month else { return }
        dayAccessibilityElements = month.days.indices.compactMap { index in
            let day = month.days[index]
            guard day.state != .future else { return nil }
            let element = NSAccessibilityElement()
            element.setAccessibilityElement(true)
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.group)
            element.setAccessibilityLabel(day.accessibilityLabel)
            element.setAccessibilityValueDescription(day.accessibilityValue)
            element.setAccessibilityIdentifier("stats.day.\(day.dayNumber)")
            return DayAccessibilityElement(
                index: index,
                date: day.date,
                element: element
            )
        }
        updateAccessibilityChildren()
        updateAccessibilityFocus()
    }

    private func synchronizeFocus() {
        guard focusedDate != nil, window?.firstResponder !== focusView else { return }
        DispatchQueue.main.async { [weak self, weak focusView] in
            guard let self, focusedDate != nil else { return }
            window?.makeFirstResponder(focusView)
        }
    }

    private func updateAccessibilityFocus() {
        for dayElement in dayAccessibilityElements {
            dayElement.element.setAccessibilityFocused(false)
        }
        focusView.setAccessibilityFocused(
            focusView.date == focusedDate
        )
    }

    private func updateAccessibilityChildren() {
        let children: [Any] = dayAccessibilityElements.map { dayElement in
            dayElement.date == rovingDate ? focusView : dayElement.element
        }
        setAccessibilityChildren(children)
    }

    private func updateFocusView(layout: StatsCalendarLayout) {
        guard let month, let rovingDate,
              let index = month.days.firstIndex(where: { $0.date == rovingDate })
        else {
            focusView.isHidden = true
            return
        }
        focusView.isHidden = false
        focusView.frame = layout.dayFrame(at: index)
        focusView.update(day: month.days[index])
    }

    private func drawWeekdays(
        _ weekdays: [String],
        layout: StatsCalendarLayout
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor(Theme.textTertiary),
            .paragraphStyle: centeredParagraphStyle,
        ]
        for index in weekdays.indices {
            weekdays[index].draw(
                in: layout.weekdayFrame(at: index),
                withAttributes: attributes
            )
        }
    }

    private func drawDay(
        _ day: StatsProjection.Day,
        at frame: CGRect
    ) {
        let isFocused = day.date == focusedDate
        let style = StatsActivityStyle(
            day: day,
            focused: isFocused,
            hovered: day.date == hoveredDate,
            increaseContrast: environment.increaseContrast
        )
        NSColor(style.background).setFill()
        NSBezierPath(
            roundedRect: frame,
            xRadius: Theme.controlRadius,
            yRadius: Theme.controlRadius
        ).fill()
        stroke(
            color: NSColor(style.outline),
            width: style.boundaryWidth,
            frame: frame
        )
        day.dayNumber.draw(
            at: CGPoint(x: frame.minX + 7, y: frame.minY + 5),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor(style.foreground),
            ]
        )
        if day.state == .today {
            NSColor(Theme.accent).setFill()
            NSBezierPath(
                ovalIn: CGRect(x: frame.maxX - 11, y: frame.minY + 8, width: 4, height: 4)
            ).fill()
        }
        if day.state == .future || day.intensity == .neutral {
            "—".draw(
                at: CGPoint(x: frame.minX + 7, y: frame.maxY - 18),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor(style.foreground),
                ]
            )
        } else {
            drawWaveform(day.intensity, at: frame)
        }
        guard isFocused else { return }
        drawFocusRing(at: frame)
    }

    private func drawWaveform(
        _ intensity: StatsProjection.Day.Intensity,
        at frame: CGRect
    ) {
        let baseline = frame.maxY - 7
        let pattern = StatsActivityStyle.waveformFillPattern(intensity)
        let boundaryWidth = Theme.essentialBorderWidth(
            increaseContrast: environment.increaseContrast
        )
        for index in StatsActivityStyle.waveformBarHeights.indices {
            let height = StatsActivityStyle.waveformBarHeights[index]
            let barFrame = CGRect(
                x: frame.minX + 7 + CGFloat(index) * 5,
                y: baseline - height,
                width: 3,
                height: height
            )
            if pattern[index] {
                NSColor(Theme.accent).setFill()
                NSBezierPath(roundedRect: barFrame, xRadius: 1.5, yRadius: 1.5).fill()
            } else {
                stroke(
                    color: NSColor(Theme.essentialBorderColor(
                        increaseContrast: environment.increaseContrast
                    )),
                    width: boundaryWidth,
                    frame: barFrame,
                    radius: 1.5
                )
            }
        }
    }

    private func drawFocusRing(at frame: CGRect) {
        stroke(
            color: NSColor(Theme.canvas),
            width: Theme.focusRingWidth + Theme.focusGap,
            frame: frame.insetBy(dx: Theme.focusGap, dy: Theme.focusGap)
        )
        stroke(
            color: NSColor(Theme.accent),
            width: Theme.focusRingWidth,
            frame: frame.insetBy(dx: Theme.focusGap, dy: Theme.focusGap)
        )
    }

    private func stroke(
        color: NSColor,
        width: CGFloat,
        frame: CGRect,
        radius: CGFloat = Theme.controlRadius
    ) {
        color.setStroke()
        let path = NSBezierPath(
            roundedRect: frame.insetBy(dx: width / 2, dy: width / 2),
            xRadius: radius,
            yRadius: radius
        )
        path.lineWidth = width
        path.stroke()
    }

    private var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private struct DayAccessibilityElement {
        let index: Int
        let date: Date
        let element: NSAccessibilityElement
    }
}

@MainActor
private final class StatsCalendarFocusNSView: NSView {
    weak var owner: StatsCalendarGridNSView?
    private(set) var date: Date?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(day: StatsProjection.Day) {
        date = day.date
        setAccessibilityLabel(day.accessibilityLabel)
        setAccessibilityValueDescription(day.accessibilityValue)
        setAccessibilityIdentifier("stats.day.\(day.dayNumber)")
    }

    override func becomeFirstResponder() -> Bool {
        owner?.focusViewDidFocus()
        return true
    }

    override func resignFirstResponder() -> Bool {
        owner?.focusViewDidResign()
        return true
    }

    override func keyDown(with event: NSEvent) {
        let direction: CalendarFocusNavigator.Direction?
        switch event.keyCode {
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        case 36, 49: return
        default:
            super.keyDown(with: event)
            return
        }
        if let direction {
            owner?.moveFocus(direction)
        }
    }
}
