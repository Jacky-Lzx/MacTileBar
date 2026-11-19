import AppKit

let app = NSApplication.shared
let controller = BarController()
app.setActivationPolicy(.accessory)
app.delegate = controller
app.run()
