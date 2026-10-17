/// Where items go on a bar, like sketchybar: `left` items from the left edge in the order
/// they were added, `right` items from the right edge (the first one added is the
/// rightmost), `center` items centered, `q` / `e` items to the left / right of the notch.
/// An item takes `background.padding_left + length + background.padding_right`; its
/// content (and background) starts after `background.padding_left`.
public enum Layout {
    public struct Slot: Equatable {
        public var name: String
        public var position: String
        public var length: Double
        public var paddingLeft: Double
        public var paddingRight: Double

        public init(name: String, position: String, length: Double, paddingLeft: Double, paddingRight: Double) {
            self.name = name
            self.position = position
            self.length = length
            self.paddingLeft = paddingLeft
            self.paddingRight = paddingRight
        }

        var span: Double { paddingLeft + length + paddingRight }
    }

    /// The x of each item's content, by name, on a bar `width` wide.
    public static func place(_ slots: [Slot], width: Double, paddingLeft: Double, paddingRight: Double,
                             notchWidth: Double, notchOffset: Double) -> [String: Double]
    {
        var result: [String: Double] = [:]
        // left to right from `start`
        func forward(_ items: [Slot], from start: Double) {
            var cursor = start
            for item in items {
                result[item.name] = cursor + item.paddingLeft
                cursor += item.span
            }
        }
        // right to left from `end`, the first item at the end
        func backward(_ items: [Slot], from end: Double) {
            var cursor = end
            for item in items {
                cursor -= item.paddingRight + item.length
                result[item.name] = cursor
                cursor -= item.paddingLeft
            }
        }
        let notchLeft = (width - notchWidth) / 2 + notchOffset
        forward(slots.filter { $0.position == "left" }, from: paddingLeft)
        backward(slots.filter { $0.position == "right" }, from: width - paddingRight)
        let center = slots.filter { $0.position == "center" }
        forward(center, from: (width - center.reduce(0) { $0 + $1.span }) / 2)
        backward(slots.filter { $0.position == "q" }, from: notchLeft)
        forward(slots.filter { $0.position == "e" }, from: notchLeft + notchWidth)
        return result
    }

    /// An item's length: its fixed `width`, else its icon and label with their paddings
    /// (a drawn text with no string still takes its paddings). `measure` gives a text's width.
    public static func length(of props: ItemProps, measure: (TextProps) -> Double) -> Double {
        if let width = props.width { return width }
        var total = 0.0
        for text in [props.icon, props.label] where text.drawing {
            total += text.paddingLeft + (text.width ?? measure(text)) + text.paddingRight
        }
        return total
    }
}
