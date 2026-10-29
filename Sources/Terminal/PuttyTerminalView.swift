import UIKit
import SwiftTerm

final class PuttyTerminalView: TerminalView {
    #if DEBUG
    /// Lets UI tests read the visible screen.
    override var accessibilityValue: String? {
        get { visibleRowsText(0..<terminalDimensions.rows).joined(separator: "\n") }
        set {}
    }
    #endif
}
