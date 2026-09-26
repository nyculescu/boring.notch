//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var shelfState = ShelfStateViewModel.shared
    @ObservedObject private var clipboard = ClipboardHistoryManager.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.clipboardHistoryEnabled) private var clipboardHistoryEnabled
    /// .vertical stacks the tabs into compact mode's rail: its panel is too
    /// narrow for a tab bar beside the notch.
    var axis: Axis = .horizontal
    @Namespace var animation

    private let tabHeight: CGFloat = 26

    private var visibleTabs: [TabModel] {
        tabs.filter { tab in
            switch tab.view {
            case .home: true
            case .shelf: boringShelf
            case .clipboard: clipboardHistoryEnabled
            }
        }
    }

    /// Tabs show when a tab besides Home has something to offer, or always if
    /// the user asked. Decided here rather than by each host, so the standard
    /// header and the compact rail can't disagree.
    private var hasTabsToShow: Bool {
        let shelfTab = (!shelfState.isEmpty || coordinator.alwaysShowTabs) && boringShelf
        let clipboardTab = (!clipboard.items.isEmpty || coordinator.alwaysShowTabs) && clipboardHistoryEnabled
        return shelfTab || clipboardTab
    }

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 4))

        if hasTabsToShow {
            layout {
                ForEach(visibleTabs) { tab in
                    TabButton(
                        label: tab.label,
                        icon: tab.icon,
                        selected: coordinator.currentView == tab.view,
                        cellSize: axis == .vertical ? tabHeight : nil
                    ) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: tabHeight)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
                }
            }
            .clipShape(Capsule())
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel(camera: CameraModel()))
}
