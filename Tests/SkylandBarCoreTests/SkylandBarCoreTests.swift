@testable import SkylandBarCore
import XCTest

private func run(_ model: BarModel, _ arguments: [String], file: StaticString = #filePath, line: UInt = #line) -> Outcome {
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
        XCTAssertNil(props.apply("popup.drawing", "on")) // kept for milestone 2
        XCTAssertEqual(props.icon.string, "󰀵")
        XCTAssertEqual(props.icon.font, FontSpec(family: "SF Pro", style: "Semibold", size: 15))
        XCTAssertEqual(props.label.color.value, 0x80CD_D6F4)
        XCTAssertEqual(props.background.borderWidth, 2)
        XCTAssertEqual(props.icon.background.cornerRadius, 6)
        XCTAssertTrue(props.label.shadow.drawing)
        XCTAssertFalse(props.drawing)
        XCTAssertEqual(props.width, 120)
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
        _ = run(model, ["--default", "icon.color=0xff00ff00", "--add", "item", "a", "left", "--add", "item", "b", "left",
                        "--add", "item", "c", "right"])
        XCTAssertEqual(model.items.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(model.item(named: "a")?.props.icon.color.value, 0xFF00_FF00) // defaults apply to new items
        XCTAssertFalse(run(model, ["--add", "item", "a", "left"]).errors.isEmpty) // already there

        _ = run(model, ["--set", "/[ab]/", "label=x"])
        XCTAssertEqual(model.items.map(\.props.label.string), ["x", "x", ""])

        _ = run(model, ["--move", "a", "after", "b"])
        XCTAssertEqual(model.items.map(\.name), ["b", "a", "c"])
        _ = run(model, ["--reorder", "c", "b"])
        XCTAssertEqual(model.items.map(\.name), ["c", "a", "b"])
        _ = run(model, ["--rename", "c", "clock", "--clone", "clock2", "clock"])
        XCTAssertEqual(model.items.map(\.name), ["clock", "clock2", "a", "b"])
        _ = run(model, ["--remove", "/clock/"])
        XCTAssertEqual(model.items.map(\.name), ["a", "b"])
        XCTAssertFalse(run(model, ["--set", "nothing", "label=x"]).errors.isEmpty)
    }

    func testScripts() {
        let model = BarModel()
        _ = run(model, ["--add", "event", "skyland_update",
                        "--add", "item", "ws", "left", "--set", "ws", "script=echo ws", "--subscribe", "ws", "skyland_update",
                        "--add", "item", "clock", "right", "--set", "clock", "script=date", "update_freq=10", "click_script=open -a Calendar",
                        "--add", "item", "quiet", "right", "--set", "quiet", "script=true", "updates=off"])
        let triggered = run(model, ["--trigger", "skyland_update", "FOCUSED=3"]).scripts
        XCTAssertEqual(triggered, [ScriptRun(item: "ws", script: "echo ws", env: ["FOCUSED": "3", "NAME": "ws", "SENDER": "skyland_update", "INFO": ""])])
        XCTAssertEqual(run(model, ["--update"]).scripts.map(\.item), ["ws", "clock"]) // forced: all but updates=off
        XCTAssertEqual(model.scripts(for: "routine", only: "clock").map(\.script), ["date"])
        let clicks = model.click("clock", button: "left", modifier: "none")
        XCTAssertEqual(clicks.map(\.script), ["open -a Calendar"])
        XCTAssertEqual(clicks.first?.env["BUTTON"], "left")
        XCTAssertFalse(run(model, ["--subscribe", "ws", "no_such_event"]).errors.isEmpty)
    }

    func testQuery() throws {
        let model = BarModel()
        _ = run(model, ["--bar", "height=30", "--add", "item", "clock", "right", "--set", "clock", "label=12:00"])
        model.frames = ["clock": ["display-1": Box(x: 900, y: 0, width: 60, height: 30)]]
        let bar = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(run(model, ["--query", "bar"]).output.utf8)) as? [String: Any])
        XCTAssertEqual(bar["height"] as? Double, 30)
        XCTAssertEqual(bar["items"] as? [String], ["clock"])
        let item = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(run(model, ["--query", "clock"]).output.utf8)) as? [String: Any])
        XCTAssertEqual((item["label"] as? [String: Any])?["value"] as? String, "12:00")
        XCTAssertNotNil((item["bounding_rects"] as? [String: Any])?["display-1"])
        XCTAssertFalse(run(model, ["--query", "nothing"]).errors.isEmpty)
    }
}
