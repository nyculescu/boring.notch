//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case notch
    case appearance
    case media
    case calendar
    case shelf
    case clipboard
    case stickyNotes
    case mirror
    case battery
    case osd
    case notifications
    case shortcuts
    case about

    enum Icon {
        case system(String)
        case custom(String)
    }

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .appearance: "Appearance"
        case .media: "Media"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .stickyNotes: "Sticky Notes"
        case .mirror: "Mirror"
        case .battery: "Battery"
        case .osd: "OSD"
        case .notifications: "Notifications"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var icon: Icon {
        switch self {
        case .general: .system("gear")
        case .notch: .custom("notch")
        case .appearance: .system("paintbrush")
        case .media: .system("play.rectangle")
        case .calendar: .system("calendar")
        case .shelf: .system("tray.and.arrow.down")
        case .clipboard: .system("doc.on.clipboard")
        case .stickyNotes: .system("note.text")
        case .mirror: .system("video")
        case .battery: .system("battery.100.bolt")
        case .osd: .system("dial.medium.fill")
        case .notifications: .system("bell.badge")
        case .shortcuts: .system("keyboard")
        case .about: .system("info.circle")
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?
    let camera: CameraModel

    init(updaterController: SPUStandardUpdaterController? = nil, camera: CameraModel) {
        self.updaterController = updaterController
        self.camera = camera
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                // No Shelf page: this version drops files on the Clipboard tab instead.
                ForEach(SettingsTab.allCases.filter { $0 != .shelf }) { tab in
                    tabItem(tab)
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettings()
                case .notch:
                    NotchSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .media:
                    MediaSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .calendar:
                    CalendarSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    BatterySettingsView()
                case .shelf:
                    ShelfSettingsView()
                case .clipboard:
                    ClipboardSettingsView()
                case .stickyNotes:
                    StickyNotesSettingsView()
                case .mirror:
                    WebcamSettingsView(camera: camera)
                case .shortcuts:
                    ShortcutsSettingsView()
                case .about:
                    if let controller = updaterController {
                        AboutView(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        AboutView(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    private func tabItem(_ tab: SettingsTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            switch tab.icon {
            case .system(let imageName):
                Image(systemName: imageName)

            case .custom(let imageName):
                Image(imageName)
            }
        }
        .tag(tab)
    }
}
