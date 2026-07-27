import AppKit
import SwiftUI

struct StatsCalendarGridView: NSViewRepresentable {
    let month: StatsProjection.Month
    let environment: StatsEnvironmentAdaptations
    let hoveredDate: Date?
    let rovingDate: Date?
    let focusedDate: Date?
    let onHover: (Date?) -> Void
    let onFocus: (Date?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> StatsCalendarGridNSView {
        StatsCalendarGridNSView(
            onHover: { context.coordinator.hover($0) },
            onFocus: { context.coordinator.focus($0) }
        )
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
                focusedDate: focusedDate
            )
        )
    }

    @MainActor
    final class Coordinator {
        var parent: StatsCalendarGridView

        init(parent: StatsCalendarGridView) {
            self.parent = parent
        }

        func hover(_ date: Date?) {
            parent.onHover(date)
        }

        func focus(_ date: Date?) {
            parent.onFocus(date)
        }
    }
}

private struct StatsCalendarGridState {
    let month: StatsProjection.Month
    let environment: StatsEnvironmentAdaptations
    let hoveredDate: Date?
    let rovingDate: Date?
    let focusedDate: Date?
}

@MainActor
final class StatsCalendarGridNSView: NSView {
    private var month: StatsProjection.Month?
    private var environment = StatsEnvironmentAdaptations(
        reduceMotion: false,
        increaseContrast: false
    )
    private var hoveredDate: Date?
    private var rovingDate: Date?
    private var focusedDate: Date?
    private var dayAccessibilityElements: [DayAccessibilityElement] = []
    private var trackingAreaReference: NSTrackingArea?
    private var preparedCrossfades: [StatsCalendarCrossfadeNSView] = []
    private let focusView = StatsCalendarFocusNSView()
    private let onHover: (Date?) -> Void
    private let onFocus: (Date?) -> Void

    override var isFlipped: Bool {
        true
    }

    init(
        onHover: @escaping (Date?) -> Void,
        onFocus: @escaping (Date?) -> Void
    ) {
        self.onHover = onHover
        self.onFocus = onFocus
        super.init(frame: .zero)
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

    fileprivate func update(_ state: StatsCalendarGridState) {
        let month = state.month
        let environment = state.environment
        let monthChanged = self.month?.days != month.days
        let crossfadeFrames = changedDayFrames(
            nextMonth: month,
            nextHoveredDate: state.hoveredDate,
            reduceMotion: environment.reduceMotion
        )
        prepareCrossfades(in: crossfadeFrames)
        self.month = month
        self.environment = environment
        hoveredDate = state.hoveredDate
        rovingDate = state.rovingDate
        focusedDate = state.focusedDate
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
        startPreparedCrossfades()
        synchronizeFocus()
    }

    override func layout() {
        super.layout()
        guard let layout = calendarLayout else { return }
        for dayElement in dayAccessibilityElements {
            dayElement.element.setAccessibilityFrameInParentSpace(
                layout.dayFrame(at: dayElement.index)
            )
        }
        updateFocusView(layout: layout)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let month, let layout = calendarLayout else { return }
        drawWeekdays(month.weekdays, layout: layout)
        for index in month.days.indices {
            drawDay(month.days[index], at: layout.dayFrame(at: index))
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
        guard let month, let layout = calendarLayout else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hovered = month.days.indices.first { index in
            month.days[index].state != .future
                && layout.dayFrame(at: index).contains(point)
        }.map { month.days[$0].date }
        guard hovered != hoveredDate else { return }
        let frames = StatsCalendarCrossfadePlan.hoverFrames(
            dates: month.days.map(\.date),
            from: hoveredDate,
            to: hovered,
            layout: layout,
            reduceMotion: environment.reduceMotion
        )
        prepareCrossfades(in: frames)
        hoveredDate = hovered
        onHover(hovered)
        needsDisplay = true
        startPreparedCrossfades()
    }

    override func mouseExited(with event: NSEvent) {
        guard let month, hoveredDate != nil, let layout = calendarLayout else { return }
        prepareCrossfades(in: StatsCalendarCrossfadePlan.hoverFrames(
            dates: month.days.map(\.date),
            from: hoveredDate,
            to: nil,
            layout: layout,
            reduceMotion: environment.reduceMotion
        ))
        hoveredDate = nil
        onHover(nil)
        needsDisplay = true
        startPreparedCrossfades()
    }

    fileprivate func focusViewDidFocus() {
        guard let rovingDate else { return }
        focusedDate = rovingDate
        updateAccessibilityFocus()
        onFocus(rovingDate)
        needsDisplay = true
    }

    fileprivate func focusViewDidResign() {
        focusedDate = nil
        updateAccessibilityFocus()
        onFocus(nil)
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
        guard let layout = calendarLayout else { return }
        updateFocusView(layout: layout)
        updateAccessibilityChildren()
        updateAccessibilityFocus()
        onFocus(next)
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
            .foregroundColor: resolvedColor(
                Theme.textTertiary,
                fallback: .secondaryLabelColor
            ),
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
        resolvedColor(style.background, fallback: .windowBackgroundColor).setFill()
        NSBezierPath(
            roundedRect: frame,
            xRadius: Theme.controlRadius,
            yRadius: Theme.controlRadius
        ).fill()
        stroke(
            color: resolvedColor(style.outline, fallback: .separatorColor),
            width: style.boundaryWidth,
            frame: frame
        )
        day.dayNumber.draw(
            at: CGPoint(x: frame.minX + 7, y: frame.minY + 5),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: resolvedColor(
                    style.foreground,
                    fallback: .labelColor
                ),
            ]
        )
        if day.state == .today {
            resolvedColor(Theme.accent, fallback: .controlAccentColor).setFill()
            NSBezierPath(
                ovalIn: CGRect(x: frame.maxX - 11, y: frame.minY + 8, width: 4, height: 4)
            ).fill()
        }
        if day.state == .future || day.intensity == .neutral {
            "—".draw(
                at: CGPoint(x: frame.minX + 7, y: frame.maxY - 18),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: resolvedColor(
                        style.foreground,
                        fallback: .labelColor
                    ),
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
        let boundaryWidth = Theme.essentialBorderWidth(
            increaseContrast: environment.increaseContrast
        )
        for bar in StatsActivityStyle.waveformBars(
            intensity,
            x: frame.minX + 7,
            baseline: frame.maxY - 7
        ) {
            if bar.isFilled {
                resolvedColor(Theme.accent, fallback: .controlAccentColor).setFill()
                NSBezierPath(roundedRect: bar.frame, xRadius: 1.5, yRadius: 1.5).fill()
            } else {
                stroke(
                    color: resolvedColor(
                        Theme.essentialBorderColor(
                            increaseContrast: environment.increaseContrast
                        ),
                        fallback: .separatorColor
                    ),
                    width: boundaryWidth,
                    frame: bar.frame,
                    radius: 1.5
                )
            }
        }
    }

    private func drawFocusRing(at frame: CGRect) {
        stroke(
            color: resolvedColor(Theme.canvas, fallback: .windowBackgroundColor),
            width: Theme.focusRingWidth + Theme.focusGap,
            frame: frame.insetBy(dx: Theme.focusGap, dy: Theme.focusGap)
        )
        stroke(
            color: resolvedColor(Theme.accent, fallback: .controlAccentColor),
            width: Theme.focusRingWidth,
            frame: frame.insetBy(dx: Theme.focusGap, dy: Theme.focusGap)
        )
    }

    private func resolvedColor(_ color: Color, fallback: NSColor) -> NSColor {
        var resolved = fallback
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color)
        }
        return resolved
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

    private func changedDayFrames(
        nextMonth: StatsProjection.Month,
        nextHoveredDate: Date?,
        reduceMotion: Bool
    ) -> [CGRect] {
        guard !reduceMotion, let month, let layout = calendarLayout else { return [] }
        return month.days.indices.compactMap { index in
            let day = month.days[index]
            guard let nextDay = nextMonth.days.first(where: { $0.date == day.date })
            else { return nil }
            let intensityChanged = day.intensity != nextDay.intensity
            let hoverChanged = (day.date == hoveredDate) != (day.date == nextHoveredDate)
            return intensityChanged || hoverChanged ? layout.dayFrame(at: index) : nil
        }
    }

    private func prepareCrossfades(in frames: [CGRect]) {
        for crossfade in preparedCrossfades {
            crossfade.removeFromSuperview()
        }
        preparedCrossfades = []
        guard !environment.reduceMotion else { return }
        let uniqueFrames = frames.reduce(into: [CGRect]()) { result, frame in
            guard !result.contains(frame) else { return }
            result.append(frame)
        }
        for frame in uniqueFrames.sorted(by: {
            $0.minY == $1.minY ? $0.minX < $1.minX : $0.minY < $1.minY
        }) {
            guard let bitmap = bitmapImageRepForCachingDisplay(in: frame) else { continue }
            cacheDisplay(in: frame, to: bitmap)
            let image = NSImage(size: frame.size)
            image.addRepresentation(bitmap)
            let crossfade = StatsCalendarCrossfadeNSView(image: image)
            crossfade.frame = frame
            addSubview(crossfade, positioned: .below, relativeTo: focusView)
            preparedCrossfades.append(crossfade)
        }
    }

    private func startPreparedCrossfades() {
        guard !preparedCrossfades.isEmpty else { return }
        let crossfades = preparedCrossfades
        preparedCrossfades = []
        DispatchQueue.main.async { [weak self] in
            self?.displayIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                crossfades.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: {
                crossfades.forEach { $0.removeFromSuperview() }
            }
        }
    }

    private var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private var calendarLayout: StatsCalendarLayout? {
        guard let month else { return nil }
        return StatsCalendarLayout(
            width: bounds.width,
            leadingColumnOffset: month.leadingColumnOffset,
            dayCount: month.days.count
        )
    }

    private struct DayAccessibilityElement {
        let index: Int
        let date: Date
        let element: NSAccessibilityElement
    }
}

@MainActor
private final class StatsCalendarCrossfadeNSView: NSImageView {
    init(image: NSImage) {
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleAxesIndependently
        wantsLayer = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
