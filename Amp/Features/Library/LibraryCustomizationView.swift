import SwiftUI

/// Own the preference bindings inside the sheet, with one explicit touch target per row.
struct LibraryCustomizationView: View {
    @AppStorage(LibraryCustomizationPreferences.orderKey) private var storedOrder = LibraryCustomizationPreferences.defaultOrder
    @AppStorage(LibraryCustomizationPreferences.hiddenKey) private var hiddenSections = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    private static let rowHeight: CGFloat = 44
    private static let visibilityIconSize: CGFloat = 20

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LibraryCategory.ordered(storedOrder)) { category in
                        let visible = !LibraryCategory.hidden(hiddenSections).contains(category)
                        HStack {
                            Label(category.title, systemImage: category.icon).foregroundStyle(palette.onSurface)
                            Spacer()
                            Button { toggle(category) } label: {
                                Image(systemName: visible ? "eye" : "eye.slash")
                                    .font(.system(size: Self.visibilityIconSize, weight: .semibold))
                                    .foregroundStyle(visible ? palette.primary : palette.onSurfaceVariant)
                                    .frame(width: Self.rowHeight, height: Self.rowHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(visible ? LibraryCustomizationText.hide : LibraryCustomizationText.show) \(category.title)")
                            .accessibilityValue(visible ? LibraryCustomizationText.visible : LibraryCustomizationText.hidden)
                            .accessibilityIdentifier("libraryCategoryVisible.\(category.rawValue)")
                        }
                        .frame(minHeight: Self.rowHeight)
                        .accessibilityElement(children: .contain)
                    }
                    .onMove { source, destination in
                        var order = LibraryCategory.ordered(storedOrder)
                        order.move(fromOffsets: source, toOffset: destination)
                        storedOrder = order.map(\.rawValue).joined(separator: ",")
                    }
                } footer: { Text(LibraryCustomizationText.instructions) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(LibraryCustomizationText.action)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Restore defaults") {
                            storedOrder = LibraryCustomizationPreferences.defaultOrder
                            hiddenSections = ""
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Customization options")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func toggle(_ category: LibraryCategory) {
        var hidden = LibraryCategory.hidden(hiddenSections)
        if hidden.contains(category) { hidden.remove(category) }
        else { hidden.insert(category) }
        hiddenSections = hidden.map(\.rawValue).sorted().joined(separator: ",")
    }
}
