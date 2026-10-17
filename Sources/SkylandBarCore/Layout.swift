/// Where items go on a bar: `left` items from the left edge in the order
/// they were added, `right` items from the right edge (the first one added is the
/// rightmost), `center` items centered, `q` / `e` items to the left / right of the notch.
/// An item takes `background.padding_left + length + background.padding_right`, or just its
/// fixed `width` (the paddings inside it); its content (and background) starts after
/// `background.padding_left`.
public enum Layout {
    public struct Slot: Equatable {
        public var name: String
        public var position: String
        public var length: Double
        public var paddingLeft: Double
        public var paddingRight: Double
        /// a fixed `width`: the item takes `length` only (its paddings inside it)
        public var fixed: Bool

        public init(name: String, position: String, length: Double, paddingLeft: Double, paddingRight: Double, fixed: Bool = false) {
            self.name = name
            self.position = position
            self.length = length
            self.paddingLeft = paddingLeft
            self.paddingRight = paddingRight
            self.fixed = fixed
        }

        var span: Double { fixed ? length : paddingLeft + length + paddingRight }
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
                result[item.name] = cursor - item.paddingRight - item.length
                cursor -= item.span
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

    /// An item's length: its fixed `width`, else its icon, its `middle` (a graph, a slider
    /// or an alias) and its label, with their paddings; a drawn text with no string still
    /// takes its paddings, and is at least as wide as its background image. `measure` gives
    /// a text's width, `image` an image's (scaled, with its paddings).
    public static func length(of props: ItemProps, middle: Double = 0, measure: (TextProps) -> Double,
                              image: (ImageProps) -> Double = { _ in 0 }) -> Double
    {
        if let width = props.width { return width }
        var total = 0.0
        if props.icon.drawing { total += textLength(props.icon, measure: measure, image: image) }
        total += middle
        if props.label.drawing { total += textLength(props.label, measure: measure, image: image) }
        if props.background.drawing && props.background.image.isShown { total = max(total, image(props.background.image)) }
        return total
    }

    /// A text's paddings and its width (fixed, or its string's, at least its image's).
    public static func textLength(_ text: TextProps, measure: (TextProps) -> Double, image: (ImageProps) -> Double) -> Double {
        text.paddingLeft + contentWidth(text, measure: measure, image: image) + text.paddingRight
    }

    public static func contentWidth(_ text: TextProps, measure: (TextProps) -> Double, image: (ImageProps) -> Double) -> Double {
        if let width = text.width { return width }
        let imageWidth = text.background.drawing && text.background.image.isShown ? image(text.background.image) : 0
        return max(measure(text), imageWidth)
    }

    /// The middle part of an item of this kind: a graph's or a slider's width; an alias
    /// gives its own (its captured image).
    public static func middle(of item: BarItem, aliasWidth: Double = 0) -> Double {
        switch item.kind {
            case "graph": return item.props.graph.width
            case "slider": return item.props.slider.width
            case "alias": return aliasWidth
            default: return 0
        }
    }

    /// A popup's items: one per row (`horizontal`: side by side), each row `rowHeight` high;
    /// each item's x and y (its row's top) from the popup's top-left, and the popup's size.
    /// `inset` keeps them off the popup's border.
    public static func popup(_ slots: [Slot], horizontal: Bool, rowHeight: Double, inset: Double)
        -> (places: [String: (x: Double, y: Double)], width: Double, height: Double)
    {
        var places: [String: (x: Double, y: Double)] = [:]
        if horizontal {
            var cursor = inset
            for slot in slots {
                places[slot.name] = (cursor + slot.paddingLeft, inset)
                cursor += slot.span
            }
            return (places, cursor + inset, rowHeight + 2 * inset)
        }
        var y = inset
        var width = 0.0
        for slot in slots {
            places[slot.name] = (inset + slot.paddingLeft, y)
            y += rowHeight
            width = max(width, slot.span)
        }
        return (places, width + 2 * inset, y + inset)
    }

    /// Where a popup `width` wide goes along the bar for an item from `itemX`, `itemLength`
    /// long: its left edge.
    public static func popupX(align: String, itemX: Double, itemLength: Double, width: Double) -> Double {
        switch align {
            case "center": return itemX + (itemLength - width) / 2
            case "right": return itemX + itemLength - width
            default: return itemX
        }
    }
}
