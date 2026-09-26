//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    /// Compact mode's rail stacks the tabs as square cells of this side; nil
    /// keeps the standard pill, padded out either side of the icon.
    var cellSize: CGFloat?
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            if let cellSize {
                Image(systemName: icon)
                    .frame(width: cellSize, height: cellSize)
                    .contentShape(Circle())
            } else {
                Image(systemName: icon)
                    .padding(.horizontal, 15)
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        Log.general.debug("Tapped")
    }
}
