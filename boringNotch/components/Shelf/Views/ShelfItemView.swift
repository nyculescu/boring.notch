//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Defaults
import SwiftUI

struct ShelfItemView: View {
    let item: ShelfItem
    let quickLookService: QuickLookService
    let dropInteraction: DropInteractionState
    @StateObject private var viewModel: ShelfItemViewModel
    @State private var selectionState: ShelfItemSelectionState
    @State private var debouncedDropTarget = false
    @Default(.compactMode) private var compactMode

    private var isSelected: Bool { selectionState.isSelected }
    private var metrics: Metrics { compactMode ? .compact : .standard }

    private var highlight: HighlightPresentation {
        if debouncedDropTarget {
            HighlightPresentation(
                fill: Color.accentColor.opacity(0.25),
                stroke: Color.accentColor.opacity(0.9),
                lineWidth: 3
            )
        } else if isSelected {
            HighlightPresentation(
                fill: Color.accentColor.opacity(0.15),
                stroke: Color.accentColor.opacity(0.8),
                lineWidth: 2
            )
        } else {
            HighlightPresentation(fill: .clear, stroke: .clear, lineWidth: 1)
        }
    }

    init(
        item: ShelfItem,
        quickLookService: QuickLookService,
        dropInteraction: DropInteractionState
    ) {
        self.item = item
        self.quickLookService = quickLookService
        self.dropInteraction = dropInteraction
        _viewModel = StateObject(wrappedValue: ShelfItemViewModel(item: item))
        _selectionState = State(initialValue: ShelfSelectionModel.shared.state(for: item.id))
    }

    var body: some View {
        itemContent
        .onChange(of: viewModel.isDropTargeted) { _, targeted in
            dropInteraction.dragDetectorTargeting = targeted
        }
        .task(id: viewModel.isDropTargeted) {
            let targeted = viewModel.isDropTargeted
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            debouncedDropTarget = targeted
        }
        .task(id: item.id) {
            await viewModel.loadThumbnail()
        }
        .onAppear {
            viewModel.onQuickLookRequest = { urls in
                quickLookService.show(urls: urls, selectFirst: true)
            }
        }
    }

    // MARK: - View Components

    private var itemContent: some View {
        VStack(alignment: .center, spacing: 2) {
            iconView
            textView
        }
        .frame(width: metrics.width)
        .padding(.vertical, metrics.verticalPadding)
        .padding(.horizontal, metrics.horizontalPadding)
        .background(backgroundView)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: debouncedDropTarget)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .overlay {
            ShelfItemInteractionView(
                item: item,
                viewModel: viewModel,
                dragPreview: {
                    DragPreviewView(
                        thumbnail: viewModel.thumbnail ?? item.icon,
                        displayName: item.displayName
                    )
                },
                onPrimaryClick: viewModel.handleClick,
                onContextClick: viewModel.handleRightClick
            )
        }
    }

    private var iconView: some View {
        Image(nsImage: viewModel.thumbnail ?? item.icon)
            .resizable().scaledToFit()
            .frame(width: metrics.iconSize, height: metrics.iconSize)
            .clipShape(RoundedRectangle(cornerRadius: metrics.iconCornerRadius))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }

    private var textView: some View {
        Text(item.displayName)
            .font(.system(size: metrics.nameFontSize, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(metrics.nameLines)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(height: metrics.nameHeight, alignment: .top)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(highlight.fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        highlight.stroke,
                        lineWidth: highlight.lineWidth
                    )
            )
    }

    private struct HighlightPresentation {
        let fill: Color
        let stroke: Color
        let lineWidth: CGFloat
    }

    private struct Metrics {
        let width: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
        let iconSize: CGFloat
        let iconCornerRadius: CGFloat
        let nameFontSize: CGFloat
        let nameLines: Int
        let nameHeight: CGFloat

        static let standard = Metrics(
            width: 105,
            verticalPadding: 10,
            horizontalPadding: 5,
            iconSize: 56,
            iconCornerRadius: 12,
            nameFontSize: 12,
            nameLines: 2,
            nameHeight: 30
        )

        /// A smaller icon over one line of name: 61pt tall, to fit the 80pt
        /// the compact shelf's scroll area has.
        static let compact = Metrics(
            width: 60,
            verticalPadding: 5,
            horizontalPadding: 3,
            iconSize: 36,
            iconCornerRadius: 8,
            nameFontSize: 10,
            nameLines: 1,
            nameHeight: 13
        )
    }
}
