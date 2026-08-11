import Foundation

enum AdminTab: String, CaseIterable, Identifiable {
    case command
    case work
    case operations
    case customers
    case more

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .command: return "CommandCenter_Tab_Command"
        case .work: return "CommandCenter_Tab_Work"
        case .operations: return "CommandCenter_Tab_Operations"
        // Keep the persisted tab identifier stable while naming the mixed
        // users, staff, and conversations lane for what it actually contains.
        case .customers: return "CommandCenter_Tab_People"
        case .more: return "CommandCenter_Tab_More"
        }
    }

    var symbol: String {
        switch self {
        case .command: return "command"
        case .work: return "rectangle.stack"
        case .operations: return "waveform.path.ecg.rectangle"
        case .customers: return "person.2"
        case .more: return "ellipsis.circle"
        }
    }
}
