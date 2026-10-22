import SwiftUI

struct RunningScreen: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel("Running on your Mac")
                Text("Behind the scenes.")
                    .type(Face.verdict).foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("Real app names. Their helpers, together. Nothing left to decipher.")
                    .type(Face.body).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.xxl)

            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.tertiary)
                TextField("Find an app or process", text: $model.appQuery)
                    .textFieldStyle(.plain)
                    .type(Face.body)
                    .focused($searchFocused)
                    .accessibilityLabel("Find an app or process")
                    .onExitCommand { model.appQuery = ""; searchFocused = false }
                if !model.appQuery.isEmpty {
                    Button { model.appQuery = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.tertiary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
                } else {
                    Text("⌘F").type(Face.caption).foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 40)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(searchFocused ? Ink.secondary : Ink.ruleStrong, lineWidth: 1)
            }
            .background {
                Button("Find an app") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden().accessibilityHidden(true)
            }
            .padding(.top, Space.xl)

            HStack {
                Text("Largest memory first").type(Face.caption)
                Spacer()
                Text("Select an app to see what it is").type(Face.caption)
            }
            .foregroundStyle(Ink.tertiary)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)

            if model.snapshot == nil {
                ProgressView("Reading running apps…").padding(.vertical, Space.xxl)
            } else {
                AppList(model: model, query: model.appQuery)
            }
        }
    }
}
