@testable import SkylandBarCore
import XCTest

private func send(_ model: BarModel, _ arguments: [String], file: StaticString = #filePath, line: UInt = #line) -> Outcome {
    switch CommandParser.parse(arguments) {
        case .success(let commands): return model.execute(commands)
        case .failure(let error):
            XCTFail("parse failed: \(error)", file: file, line: line)
            return Outcome()
    }
}

final class ValueTests: XCTestCase {
    func testColors() {
        XCTAssertEqual(ARGB.parse("0xff11aa33")?.value, 0xFF11_AA33)
        XCTAssertEqual(ARGB.parse("0x11aa33")?.value, 0xFF11_AA33)
        XCTAssertEqual(ARGB.parse("#80112233")?.value, 0x8011_2233)
        XCTAssertNil(ARGB.parse("red"))
        XCTAssertNil(ARGB.parse("0xff11aa3"))
        XCTAssertEqual(ARGB(0xFF11_2233).withAlpha(0.5).value, 0x8011_2233)
        XCTAssertEqual(ARGB(0xFF11_2233).description, "0xff112233")
    }

    func testFonts() {
        XCTAssertEqual(FontSpec.parse("Hack Nerd Font:Bold:17.0", base: .standard), FontSpec(family: "Hack Nerd Font", style: "Bold", size: 17))
        XCTAssertEqual(FontSpec.parse("SF Pro", base: .standard), FontSpec(family: "SF Pro", style: "Bold", size: 14))
        XCTAssertEqual(FontSpec.parse("::20", base: .standard)?.size, 20)
        XCTAssertNil(FontSpec.parse("A:B:C", base: .standard))
        XCTAssertNil(FontSpec.parse("A:B:12:x", base: .standard))
    }
}

final class ParserTests: XCTestCase {
    func testSketchybarrcLines() throws {
        let commands = try CommandParser.parse([
            "--bar", "position=top", "height=32", "color=0x40000000",
            "--add", "item", "clock", "right",
            "--set", "clock", "update_freq=10", "script=$PLUGIN_DIR/clock.sh", "label=a=b",
            "--subscribe", "clock", "system_woke",
            "--add", "event", "skyland_update",
            "--trigger", "skyland_update", "FOCUSED=3",
        ]).get()
        XCTAssertEqual(commands, [
            .bar([Prop("position", "top"), Prop("height", "32"), Prop("color", "0x40000000")]),
            .add(kind: "item", name: "clock", args: ["right"]),
            .set(target: "clock", [Prop("update_freq", "10"), Prop("script", "$PLUGIN_DIR/clock.sh"), Prop("label", "a=b")]),
            .subscribe(target: "clock", events: ["system_woke"]),
            .add(kind: "event", name: "skyland_update", args: []),
            .trigger(event: "skyland_update", env: [Prop("FOCUSED", "3")]),
        ])
    }

    func testErrors() {
        for bad in [["clock"], ["--set", "clock", "label"], ["--add", "item", "x"], ["--add", "widget", "x", "left"],
                    ["--move", "a", "beside", "b"], ["--query"], ["--frobnicate"], ["--add", "graph", "g", "left", "wide"]] {
            if case .success = CommandParser.parse(bad) { XCTFail("accepted \(bad)") }
        }
    }
}

final class PropertyTests: XCTestCase {
    func testItemProperties() {
        var props = ItemProps()
        XCTAssertNil(props.apply("icon", "󰀵"))
        XCTAssertNil(props.apply("icon.font", "SF Pro:Semibold:15.0"))
        XCTAssertNil(props.apply("label.color", "0xffcdd6f4"))
        XCTAssertNil(props.apply("label.color.alpha", "0.5"))
        XCTAssertNil(props.apply("background.border_width", "2"))
        XCTAssertNil(props.apply("icon.background.corner_radius", "6"))
        XCTAssertNil(props.apply("label.shadow.drawing", "on"))
        XCTAssertNil(props.apply("drawing", "toggle"))
        XCTAssertNil(props.apply("width", "120"))
        XCTAssertNil(props.apply("updates", "when_shown"))
        XCTAssertNil(props.apply("popup.drawing", "on"))
        XCTAssertEqual(props.icon.string, "󰀵")
        XCTAssertEqual(props.icon.font, FontSpec(family: "SF Pro", style: "Semibold", size: 15))
        XCTAssertEqual(props.label.color.value, 0x80CD_D6F4)
        XCTAssertEqual(props.background.borderWidth, 2)
        XCTAssertEqual(props.icon.background.cornerRadius, 6)
        XCTAssertTrue(props.label.shadow.drawing)
        XCTAssertFalse(props.drawing)
        XCTAssertEqual(props.width, 120)
        XCTAssertTrue(props.popup.drawing)
        XCTAssertNotNil(props.apply("popup.nope", "1"))
        XCTAssertNotNil(props.apply("position", "middle"))
        XCTAssertNotNil(props.apply("label.color", "blue"))
        XCTAssertNotNil(props.apply("nope", "1"))
        XCTAssertNotNil(props.apply("y_offset", "up"))
    }

    func testBarProperties() {
        var bar = BarProps()
        XCTAssertNil(bar.apply("position", "bottom"))
        XCTAssertNil(bar.apply("topmost", "window"))
        XCTAssertNil(bar.apply("hidden", "toggle"))
        XCTAssertNil(bar.apply("display", "1,2"))
        XCTAssertEqual(bar.position, "bottom")
        XCTAssertEqual(bar.topmost, "window")
        XCTAssertEqual(bar.hidden, "on")
        XCTAssertTrue(bar.isShown(onDisplay: 2))
        XCTAssertFalse(bar.isShown(onDisplay: 3))
        XCTAssertNotNil(bar.apply("position", "left"))
    }
}

final class LayoutTests: XCTestCase {
    func testPlacement() {
        let slot = { (name: String, position: String, length: Double) in
            Layout.Slot(name: name, position: position, length: length, paddingLeft: 2, paddingRight: 3)
        }
        let xs = Layout.place([slot("a", "left", 10), slot("b", "left", 20), slot("r1", "right", 10), slot("r2", "right", 30),
                               slot("c", "center", 40), slot("q", "q", 10), slot("e", "e", 10)],
                              width: 1000, paddingLeft: 5, paddingRight: 7, notchWidth: 200, notchOffset: 0)
        XCTAssertEqual(xs["a"], 7) // 5 + 2
        XCTAssertEqual(xs["b"], 22) // 5 + 15 + 2
        XCTAssertEqual(xs["r1"], 980) // 1000 - 7 - 3 - 10
        XCTAssertEqual(xs["r2"], 945) // 978 - 3 - 30
        XCTAssertEqual(xs["c"], 479.5) // (1000 - 45) / 2 + 2
        XCTAssertEqual(xs["q"], 387) // 400 - 3 - 10
        XCTAssertEqual(xs["e"], 602) // 600 + 2

        // a fixed width holds the paddings: the next item starts right after it
        let fixed = Layout.Slot(name: "f", position: "left", length: 36, paddingLeft: 4, paddingRight: 4, fixed: true)
        let fs = Layout.place([fixed, slot("n", "left", 10), Layout.Slot(name: "rf", position: "right", length: 36, paddingLeft: 4, paddingRight: 4, fixed: true),
                               slot("rn", "right", 10)], width: 1000, paddingLeft: 12, paddingRight: 8, notchWidth: 0, notchOffset: 0)
        XCTAssertEqual(fs["f"], 16) // 12 + 4
        XCTAssertEqual(fs["n"], 50) // 12 + 36 + 2
        XCTAssertEqual(fs["rf"], 952) // 992 - 4 - 36
        XCTAssertEqual(fs["rn"], 943) // 992 - 36 - 3 - 10
    }

    func testLength() {
        var props = ItemProps()
        props.icon.paddingLeft = 4
        props.icon.paddingRight = 2
        props.label.paddingLeft = 1
        props.label.width = 50
        XCTAssertEqual(Layout.length(of: props) { _ in 10 }, 4 + 10 + 2 + 1 + 50)
        props.label.drawing = false
        XCTAssertEqual(Layout.length(of: props) { _ in 10 }, 16)
        props.width = 99
        XCTAssertEqual(Layout.length(of: props) { _ in 10 }, 99)
    }
}

final class ModelTests: XCTestCase {
    func testItems() {
        let model = BarModel()
        _ = send(model, ["--default", "icon.color=0xff00ff00", "--add", "item", "a", "left", "--add", "item", "b", "left",
                        "--add", "item", "c", "right"])
        XCTAssertEqual(model.items.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(model.item(named: "a")?.props.icon.color.value, 0xFF00_FF00) // defaults apply to new items
        let again = send(model, ["--add", "item", "a", "left"]) // already there: a warning, as in sketchybar
        XCTAssertFalse(again.errors.isEmpty)
        XCTAssertFalse(again.failed)

        _ = send(model, ["--set", "/[ab]/", "label=x"])
        XCTAssertEqual(model.items.map(\.props.label.string), ["x", "x", ""])

        _ = send(model, ["--move", "a", "after", "b"])
        XCTAssertEqual(model.items.map(\.name), ["b", "a", "c"])
        _ = send(model, ["--reorder", "c", "b"])
        XCTAssertEqual(model.items.map(\.name), ["c", "a", "b"])
        _ = send(model, ["--rename", "c", "clock", "--clone", "clock2", "clock"])
        XCTAssertEqual(model.items.map(\.name), ["clock", "clock2", "a", "b"])
        _ = send(model, ["--remove", "/clock/"])
        XCTAssertEqual(model.items.map(\.name), ["a", "b"])
        XCTAssertTrue(send(model, ["--set", "nothing", "label=x"]).failed)
        XCTAssertFalse(send(model, ["--remove", "/^nothing/"]).failed) // a regex matching nothing: a warning
    }

    func testScripts() {
        let model = BarModel()
        _ = send(model, ["--add", "event", "skyland_update",
                        "--add", "item", "ws", "left", "--set", "ws", "script=echo ws", "--subscribe", "ws", "skyland_update",
                        "--add", "item", "clock", "right", "--set", "clock", "script=date", "update_freq=10", "click_script=open -a Calendar",
                        "--add", "item", "quiet", "right", "--set", "quiet", "script=true", "updates=off"])
        let triggered = send(model, ["--trigger", "skyland_update", "FOCUSED=3"]).scripts
        XCTAssertEqual(triggered, [ScriptRun(item: "ws", script: "echo ws", env: ["FOCUSED": "3", "NAME": "ws", "SENDER": "skyland_update", "INFO": ""])])
        XCTAssertEqual(send(model, ["--update"]).scripts.map(\.item), ["ws", "clock"]) // forced: all but updates=off
        XCTAssertEqual(model.scripts(for: "routine", only: "clock").map(\.script), ["date"])
        let clicks = model.click("clock", button: "left", modifier: "none")
        XCTAssertEqual(clicks.map(\.script), ["open -a Calendar"])
        XCTAssertEqual(clicks.first?.env["BUTTON"], "left")
        XCTAssertFalse(send(model, ["--subscribe", "ws", "no_such_event"]).errors.isEmpty)
    }

    func testQuery() throws {
        let model = BarModel()
        _ = send(model, ["--bar", "height=30", "--add", "item", "clock", "right", "--set", "clock", "label=12:00"])
        model.frames = ["clock": ["display-1": Box(x: 900, y: 0, width: 60, height: 30)]]
        let bar = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(send(model, ["--query", "bar"]).output.utf8)) as? [String: Any])
        XCTAssertEqual(bar["height"] as? Double, 30)
        XCTAssertEqual(bar["items"] as? [String], ["clock"])
        let item = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(send(model, ["--query", "clock"]).output.utf8)) as? [String: Any])
        XCTAssertEqual((item["label"] as? [String: Any])?["value"] as? String, "12:00")
        XCTAssertNotNil((item["bounding_rects"] as? [String: Any])?["display-1"])
        XCTAssertFalse(send(model, ["--query", "nothing"]).errors.isEmpty)
    }
}

final class ComponentTests: XCTestCase {
    func testBackgroundsDrawOnceColored() {
        var props = ItemProps()
        XCTAssertFalse(props.background.drawing)
        XCTAssertNil(props.apply("background.color", "0xff112233"))
        XCTAssertTrue(props.background.drawing) // like sketchybar
        XCTAssertNil(props.apply("background.drawing", "off"))
        XCTAssertNil(props.apply("icon.background.image", "app.com.apple.finder"))
        XCTAssertTrue(props.icon.background.drawing)
        XCTAssertEqual(props.icon.background.image.string, "app.com.apple.finder")
        XCTAssertNil(props.apply("icon.background.image.scale", "0.5"))
        XCTAssertEqual(props.icon.background.image.scale, 0.5)
        XCTAssertNil(props.apply("background.glass", "on"))
        XCTAssertEqual(props.background.glass, "regular")
        XCTAssertNotNil(props.apply("background.glass", "frosted"))
    }

    func testPopupsAndBrackets() {
        let model = BarModel()
        _ = send(model, ["--add", "item", "apple", "left", "--set", "apple", "popup.drawing=toggle", "popup.align=center", "popup.background.color=0xff000000",
                        "--add", "item", "apple.prefs", "popup.apple", "--add", "item", "apple.lock", "popup.apple",
                        "--add", "item", "a", "left", "--add", "item", "b", "left",
                        "--add", "bracket", "group", "a", "/^b$/", "--set", "group", "background.color=0x40ffffff"])
        let apple = model.item(named: "apple")!
        XCTAssertTrue(apple.props.popup.drawing)
        XCTAssertEqual(apple.props.popup.align, "center")
        XCTAssertTrue(apple.props.popup.background.drawing)
        XCTAssertEqual(model.popupItems(of: "apple").map(\.name), ["apple.prefs", "apple.lock"])
        XCTAssertEqual(model.members(of: model.item(named: "group")!), ["a", "b"])
        _ = send(model, ["--rename", "apple", "logo"])
        XCTAssertEqual(model.popupItems(of: "logo").map(\.name), ["apple.prefs", "apple.lock"]) // popups follow
        XCTAssertNotNil(send(model, ["--set", "logo", "popup.align=top"]).errors.first)
    }

    func testGraph() {
        let model = BarModel()
        _ = send(model, ["--add", "graph", "cpu", "right", "3", "--set", "cpu", "graph.color=0xff00ff00"])
        XCTAssertEqual(model.item(named: "cpu")?.props.graph.width, 3)
        XCTAssertNil(model.item(named: "cpu")?.props.width) // the graph is the middle part, the item stays dynamic
        _ = send(model, ["--push", "cpu", "0.1", "0.2", "2", "-1"])
        XCTAssertEqual(model.item(named: "cpu")?.graphValues, [0.2, 1, 0]) // clamped, the newest 3 kept
        XCTAssertEqual(model.item(named: "cpu")?.props.graph.fill, ARGB(0x5500_FF00)) // no fill_color: the color, lighter
        XCTAssertFalse(send(model, ["--push", "cpu", "x"]).errors.isEmpty)
        _ = send(model, ["--add", "item", "plain", "left"])
        XCTAssertFalse(send(model, ["--push", "plain", "0.5"]).errors.isEmpty)
    }

    func testSlider() {
        let model = BarModel()
        _ = send(model, ["--add", "slider", "volume", "right", "100", "--set", "volume", "script=vol", "slider.knob=o", "slider.knob.color=0xffff0000",
                        "slider.percentage=150", "--subscribe", "volume", "mouse.clicked"])
        let slider = model.item(named: "volume")!.props.slider
        XCTAssertEqual(slider.width, 100)
        XCTAssertEqual(slider.percentage, 100)
        XCTAssertEqual(slider.knob.string, "o")
        XCTAssertEqual(slider.knob.color.value, 0xFFFF_0000)
        let runs = model.slide("volume", to: 42.4, button: "left", modifier: "none")
        XCTAssertEqual(model.item(named: "volume")?.props.slider.percentage, 42)
        XCTAssertEqual(runs.map(\.env["PERCENTAGE"]), ["42"])
        XCTAssertEqual(runs.first?.env["SENDER"], "mouse.clicked")
    }

    func testSpaces() {
        let model = BarModel()
        _ = send(model, ["--add", "space", "space.1", "left", "--set", "space.1", "space=1", "script=s",
                        "--add", "space", "space.2", "left", "--set", "space.2", "space=2", "script=s",
                        "--add", "item", "watcher", "right", "--set", "watcher", "script=w", "--subscribe", "watcher", "space_change"])
        model.currentSpaces = [1: 2]
        let runs = model.spaceChange()
        XCTAssertEqual(runs.map(\.item), ["space.1", "space.2", "watcher"])
        XCTAssertEqual(runs.map { $0.env["SELECTED"] }, ["false", "true", nil])
        XCTAssertEqual(runs[1].env["SID"], "2")
        XCTAssertEqual(runs[1].env["DID"], "1")
        XCTAssertEqual(runs[2].env["INFO"], "{\"display-1\":2}")
        var props = ItemProps()
        XCTAssertNil(props.apply("space", "1,3"))
        XCTAssertTrue(props.isShown(onSpaces: [3]))
        XCTAssertFalse(props.isShown(onSpaces: [2]))
        XCTAssertTrue(props.isShown(onSpaces: [])) // not known: shown
    }

    func testScrolledText() {
        var text = TextProps()
        text.string = "abcdef"
        text.maxChars = 4
        XCTAssertTrue(text.scrolls)
        XCTAssertEqual(text.shown, "abcd")
        XCTAssertEqual(text.scrolled(0), "abcd")
        XCTAssertEqual(text.scrolled(4), "ef  ")
        XCTAssertEqual(text.scrolled(8), " abc")
        XCTAssertEqual(text.scrolled(9), "abcd") // 6 letters and 3 spaces: back after 9
    }
}

final class LayoutPartsTests: XCTestCase {
    func testMiddleAndImages() {
        var props = ItemProps()
        props.icon.paddingRight = 2
        props.label.paddingLeft = 3
        XCTAssertEqual(Layout.length(of: props, middle: 50, measure: { _ in 10 }), 10 + 2 + 50 + 3 + 10)
        _ = props.apply("label.background.image", "artwork.png")
        XCTAssertEqual(Layout.length(of: props, measure: { _ in 10 }, image: { _ in 40 }), 10 + 2 + 3 + 40)
        _ = props.apply("background.image", "big.png")
        // the item's own image is wider than icon and label (12 + 3 + 40): it sets the length
        XCTAssertEqual(Layout.length(of: props, measure: { _ in 10 }, image: { $0.string == "big.png" ? 100 : 40 }), 100)
    }

    func testPopup() {
        let slots = [Layout.Slot(name: "a", position: "popup", length: 50, paddingLeft: 2, paddingRight: 3),
                     Layout.Slot(name: "b", position: "popup", length: 80, paddingLeft: 0, paddingRight: 0)]
        let vertical = Layout.popup(slots, horizontal: false, rowHeight: 20, inset: 1)
        XCTAssertEqual(vertical.places["a"]?.x, 3)
        XCTAssertEqual(vertical.places["a"]?.y, 1)
        XCTAssertEqual(vertical.places["b"]?.y, 21)
        XCTAssertEqual(vertical.width, 82) // the widest, 80, and the inset each side
        XCTAssertEqual(vertical.height, 42)
        let horizontal = Layout.popup(slots, horizontal: true, rowHeight: 20, inset: 0)
        XCTAssertEqual(horizontal.places["b"]?.x, 55)
        XCTAssertEqual(horizontal.width, 135)
        XCTAssertEqual(horizontal.height, 20)
        XCTAssertEqual(Layout.popupX(align: "center", itemX: 100, itemLength: 20, width: 60), 80)
        XCTAssertEqual(Layout.popupX(align: "right", itemX: 100, itemLength: 20, width: 60), 60)
    }
}

final class AnimationTests: XCTestCase {
    func testCurves() {
        for curve in Curve.allCases {
            XCTAssertEqual(curve.value(0), 0, accuracy: 1e-9, "\(curve)")
            XCTAssertEqual(curve.value(1), 1, accuracy: 1e-9, "\(curve)")
            XCTAssertGreaterThan(curve.value(0.5), 0, "\(curve)")
            XCTAssertLessThan(curve.value(0.5), 1, "\(curve)")
        }
        XCTAssertEqual(ARGB.mix(ARGB(0xFF00_0000), ARGB(0x00FF_FFFF), 0.5).value, 0x8080_8080)
    }

    func testAnimatedSet() {
        let model = BarModel()
        var now = 100.0
        model.clock = { now }
        _ = send(model, ["--add", "item", "a", "left", "--set", "a", "y_offset=0", "label.color=0xff000000"])
        let outcome = send(model, ["--animate", "linear", "30", "--set", "a", "y_offset=10", "label.color=0xffffffff", "label=new"])
        XCTAssertTrue(outcome.animating)
        let a = { model.displayed(model.item(named: "a")!) }
        XCTAssertEqual(model.item(named: "a")?.props.yOffset, 10) // the model holds the target
        XCTAssertEqual(a().yOffset, 0)
        XCTAssertEqual(a().label.string, "new") // not a number: at once
        now += 0.25 // 15 of 30 frames
        XCTAssertEqual(a().yOffset, 5, accuracy: 1e-9)
        XCTAssertEqual(a().label.color.value, 0xFF80_8080)
        // a new animation starts from where the item is
        _ = send(model, ["--animate", "linear", "60", "--set", "a", "y_offset=0"])
        XCTAssertEqual(a().yOffset, 5, accuracy: 1e-9)
        now += 0.5
        XCTAssertEqual(a().yOffset, 2.5, accuracy: 1e-9)
        now += 0.5
        model.endFinishedAnimations()
        XCTAssertFalse(model.isAnimating)
        XCTAssertEqual(a().yOffset, 0)
        // without --animate, at once; --animate lasts for its message only
        _ = send(model, ["--set", "a", "y_offset=7"])
        XCTAssertEqual(a().yOffset, 7)
        XCTAssertFalse(model.isAnimating)
        XCTAssertFalse(send(model, ["--animate", "bounce", "10"]).errors.isEmpty)
    }

    func testAnimatedBar() {
        let model = BarModel()
        var now = 0.0
        model.clock = { now }
        _ = send(model, ["--animate", "sin", "60", "--bar", "height=40"])
        XCTAssertTrue(model.isBarAnimating)
        XCTAssertEqual(model.displayedBar.height, 25)
        now = 1
        XCTAssertEqual(model.displayedBar.height, 40)
        model.endFinishedAnimations()
        XCTAssertFalse(model.isAnimating)
    }
}

final class SkylandTests: XCTestCase {
    func testEvents() {
        let workspace = skylandEvent(["_event": "focused-workspace-changed", "workspace": "2", "prevWorkspace": "1"])
        XCTAssertEqual(workspace.map(\.event), ["skyland_workspace_change", "aerospace_workspace_change"])
        XCTAssertEqual(workspace.first?.env, ["FOCUSED_WORKSPACE": "2", "PREV_WORKSPACE": "1"])
        let focus = skylandEvent(["_event": "focus-changed", "workspace": "3", "windowId": 42])
        XCTAssertEqual(focus.first?.env["WINDOW_ID"], "42")
        XCTAssertEqual(skylandEvent(["_event": "mode-changed", "mode": "resize"]).map(\.env["MODE"]), ["resize", "resize"])
        XCTAssertEqual(skylandEvent(["_event": "focused-monitor-changed", "workspace": "1", "monitorId": 2]).first?.env["MONITOR"], "2")
        XCTAssertTrue(skylandEvent(["_event": "something-new"]).isEmpty)
    }

    func testSubscriptions() {
        let model = BarModel()
        _ = send(model, ["--add", "item", "ws", "left", "--set", "ws", "script=ws.sh", "--subscribe", "ws", "aerospace_workspace_change"])
        XCTAssertTrue(model.isSubscribed(to: "aerospace_workspace_change")) // built in: no --add event needed
        XCTAssertFalse(model.isSubscribed(to: "space_windows_change"))
        let runs = model.scripts(for: "aerospace_workspace_change", info: "{}", env: ["FOCUSED_WORKSPACE": "2"])
        XCTAssertEqual(runs.first?.env["FOCUSED_WORKSPACE"], "2")
    }
}

final class MachTests: XCTestCase {
    func testWire() {
        let bytes = Wire.message(["--set", "clock", "label=12:00"])
        XCTAssertEqual(bytes, Array("--set\0clock\0label=12:00\0\0".utf8))
        XCTAssertEqual(Wire.arguments(bytes), ["--set", "clock", "label=12:00"])
        XCTAssertEqual(Wire.arguments(Array("--update\0".utf8)), ["--update"]) // one NUL only
        XCTAssertEqual(Wire.arguments([]), [])
        XCTAssertEqual(Wire.event(["SENDER": "routine", "NAME": "cpu"]), Array("NAME\0cpu\0SENDER\0routine\0\0".utf8))
    }

    func testHelpers() {
        let model = BarModel()
        // what SbarLua does: no script, its event loop's name as mach_helper
        _ = send(model, ["--add", "item", "lua", "left", "--set", "lua", "mach_helper=git.felix.sbar.123", "update_freq=5",
                         "--subscribe", "lua", "front_app_switched"])
        XCTAssertTrue(model.item(named: "lua")!.props.hasScript)
        let runs = model.scripts(for: "front_app_switched", info: "Safari")
        XCTAssertEqual(runs.map(\.helper), ["git.felix.sbar.123"])
        XCTAssertEqual(runs.first?.script, "")
        XCTAssertEqual(runs.first?.env["INFO"], "Safari")
        XCTAssertEqual(model.scripts(for: "routine", only: "lua").count, 1)
        _ = send(model, ["--set", "lua", "event_port=git.felix.other"])
        XCTAssertEqual(model.item(named: "lua")?.props.machHelper, "git.felix.other")
    }
}

final class WorkspaceComponentTests: XCTestCase {
    let workspacesJSON = """
        [{"workspace":"1","workspace-is-focused":true,"workspace-is-visible":true,"monitor-appkit-nsscreen-screens-id":1},
         {"workspace":"2","workspace-is-focused":false,"workspace-is-visible":true,"monitor-appkit-nsscreen-screens-id":2},
         {"workspace":"3","workspace-is-focused":false,"workspace-is-visible":false,"monitor-appkit-nsscreen-screens-id":1}]
        """
    let windowsJSON = """
        [{"workspace":"1","app-name":"Safari"},{"workspace":"1","app-name":"Safari"},{"workspace":"1","app-name":"Code"},
         {"workspace":"2","app-name":"Music"}]
        """

    func testParse() {
        let list = SkylandData.workspaces(workspacesJSON, windows: windowsJSON)
        XCTAssertEqual(list, [
            WorkspaceInfo(name: "1", display: 1, focused: true, visible: true, apps: ["Safari", "Safari", "Code"]),
            WorkspaceInfo(name: "2", display: 2, focused: false, visible: true, apps: ["Music"]),
            WorkspaceInfo(name: "3", display: 1, focused: false, visible: false, apps: []),
        ])
        XCTAssertEqual(SkylandData.focusedWindow("[{\"app-name\":\"Code\",\"app-bundle-id\":\"com.microsoft.VSCode\",\"window-title\":\"main.swift\"}]"),
                       FocusedWindow(app: "Code", bundleId: "com.microsoft.VSCode", title: "main.swift"))
        XCTAssertNil(SkylandData.focusedWindow("[]"))
        XCTAssertEqual(SkylandData.workspaces("not json", windows: "[]"), [])
    }

    func testWorkspaceItems() {
        let model = BarModel()
        _ = send(model, ["--add", "item", "logo", "left", "--add", "workspaces", "ws", "left", "--add", "item", "after", "left",
                         "--set", "ws", "label={apps}", "icon.color=0xff888888", "background.drawing=off",
                         "focused.icon.color=0xffffffff", "focused.background.drawing=on", "empty.label=·", "empty.icon.color=0xff444444"])
        XCTAssertEqual(model.items.map(\.name), ["logo", "ws", "after"]) // nothing from skyland yet
        model.setWorkspaces(SkylandData.workspaces(workspacesJSON, windows: windowsJSON))
        XCTAssertEqual(model.items.map(\.name), ["logo", "ws", "ws.1", "ws.2", "ws.3", "after"]) // right after the component
        let one = model.item(named: "ws.1")!.props, three = model.item(named: "ws.3")!.props
        XCTAssertEqual(one.icon.string, "1") // {name} when the icon is not set
        XCTAssertEqual(one.label.string, "Safari Code") // {apps}: each app once
        XCTAssertEqual(one.icon.color.value, 0xFFFF_FFFF) // focused
        XCTAssertTrue(one.background.drawing)
        XCTAssertEqual(one.display, "1")
        XCTAssertEqual(model.item(named: "ws.2")?.props.display, "2") // on its monitor
        XCTAssertEqual(three.label.string, "·") // empty
        XCTAssertEqual(three.icon.color.value, 0xFF44_4444)
        XCTAssertFalse(three.background.drawing)
        XCTAssertEqual(model.workspace(of: "ws.3"), "3")
        XCTAssertTrue(model.scrollsWorkspaces("ws.1"))
        XCTAssertNil(model.workspace(of: "logo"))

        // the focus moves: the items follow; the component's options and errors
        _ = send(model, ["--set", "ws", "workspaces.monitor=off", "workspaces.scroll=off"])
        model.setWorkspaces(SkylandData.workspaces(workspacesJSON.replacingOccurrences(of: "\"workspace-is-focused\":true", with: "\"workspace-is-focused\":false"),
                                                   windows: windowsJSON))
        XCTAssertEqual(model.item(named: "ws.1")?.props.icon.color.value, 0xFF88_8888)
        XCTAssertEqual(model.item(named: "ws.2")?.props.display, "all")
        XCTAssertFalse(model.scrollsWorkspaces("ws.1"))
        XCTAssertFalse(send(model, ["--set", "ws", "workspaces.colour=1"]).errors.isEmpty)
        XCTAssertFalse(send(model, ["--set", "ws", "focused.nope=1"]).errors.isEmpty)
        _ = send(model, ["--remove", "ws"])
        XCTAssertEqual(model.items.map(\.name), ["logo", "after"]) // its items go with it
    }

    func testAnimatedFocus() {
        let model = BarModel()
        var now = 0.0
        model.clock = { now }
        _ = send(model, ["--add", "workspaces", "ws", "left", "--set", "ws", "workspaces.animation=tanh", "workspaces.animation_frames=30",
                         "focused.y_offset=4"])
        model.setWorkspaces(SkylandData.workspaces(workspacesJSON, windows: windowsJSON))
        XCTAssertFalse(model.isAnimating) // the first time, nothing to animate from
        let moved = workspacesJSON.replacingOccurrences(of: "\"workspace\":\"1\",\"workspace-is-focused\":true", with: "\"workspace\":\"1\",\"workspace-is-focused\":false")
            .replacingOccurrences(of: "\"workspace\":\"3\",\"workspace-is-focused\":false", with: "\"workspace\":\"3\",\"workspace-is-focused\":true")
        XCTAssertTrue(model.setWorkspaces(SkylandData.workspaces(moved, windows: windowsJSON)))
        XCTAssertEqual(model.displayed(model.item(named: "ws.1")!).yOffset, 4) // on its way down
        XCTAssertEqual(model.displayed(model.item(named: "ws.3")!).yOffset, 0) // on its way up
        now = 0.25
        XCTAssertEqual(model.displayed(model.item(named: "ws.3")!).yOffset, 4 * Curve.tanh.value(0.5), accuracy: 1e-9)
    }

    func testTitle() {
        let model = BarModel()
        _ = send(model, ["--add", "title", "t", "center", "--set", "t", "title.app_icon=on"])
        XCTAssertEqual(model.item(named: "t")?.props.label.string, "Desktop")
        model.setFocusedWindow(FocusedWindow(app: "Code", bundleId: "com.microsoft.VSCode", title: "main.swift"))
        XCTAssertEqual(model.item(named: "t")?.props.label.string, "Code: main.swift")
        XCTAssertEqual(model.item(named: "t")?.props.icon.background.image.string, "app.com.microsoft.VSCode")
        _ = send(model, ["--set", "t", "title.format=title", "title.empty=—"])
        XCTAssertEqual(model.item(named: "t")?.props.label.string, "main.swift")
        model.setFocusedWindow(nil)
        XCTAssertEqual(model.item(named: "t")?.props.label.string, "—")
        XCTAssertFalse(model.item(named: "t")!.props.icon.background.drawing)
    }
}

final class NotchTests: XCTestCase {
    func testNotch() {
        let model = BarModel()
        let added = send(model, ["--add", "notch", "island", "--set", "island", "notch.width=360", "notch.animation=tanh", "notch.horizontal=on",
                                 "--add", "item", "island.song", "popup.island", "--set", "island.song", "label=song"])
        XCTAssertTrue(added.notchChanged)
        XCTAssertEqual(model.notch?.name, "island")
        XCTAssertEqual(model.notch?.props.position, "notch") // never on the bar
        XCTAssertEqual(model.notch?.options["width"], "360")
        XCTAssertEqual(model.popupItems(of: "island").map(\.name), ["island.song"])
        XCTAssertFalse(send(model, ["--set", "island", "notch.width=wide"]).errors.isEmpty)
        XCTAssertFalse(send(model, ["--set", "island", "notch.animation=bounce"]).errors.isEmpty)
        XCTAssertFalse(send(model, ["--set", "island", "notch.size=1"]).errors.isEmpty)
        if case .success = CommandParser.parse(["--add", "notch", "two", "left"]) { XCTFail("a notch takes no position") }

        // opened by a script (toggle), by the mouse
        XCTAssertTrue(send(model, ["--set", "island", "notch.open=toggle"]).notchChanged)
        XCTAssertEqual(model.notch?.options["open"], "on")
        XCTAssertFalse(model.setNotchOpen(true)) // already
        XCTAssertTrue(model.setNotchOpen(false))
        XCTAssertEqual(model.notch?.options["open"], "off")

        _ = send(model, ["--add", "item", "fan", "left", "--set", "fan", "script=x", "--subscribe", "fan", "notch_open"])
        XCTAssertEqual(model.scripts(for: "notch_open").map(\.item), ["fan"]) // built in, no --add event
    }
}
