import SwiftUI
import DesignSystem
import Integrations

/// Name, scope, dates, colour, and a repo when GitHub is connected.
struct NewProjectSheet: View {
    var onCreate: (_ name: String, _ scope: String, _ colour: String, _ starts: Date?, _ ends: Date?, _ repo: String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.github) private var github
    @State private var name = ""
    @State private var scope = ""
    @State private var colour = ProjectColour.tomato
    @State private var hasDates = false
    @State private var starts = Date.now
    @State private var ends = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var repoQuery = ""
    @State private var repo: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    field("NAME", text: $name, prompt: "LifeOS 1.1")
                    field("SCOPE", text: $scope, prompt: "What's in, in one line")
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("COLOUR").brutalLabel()
                        HStack(spacing: Space.x1) {
                            ForEach(ProjectColour.allCases, id: \.self) { option in
                                Button { colour = option } label: {
                                    Rectangle().fill(option.fill.resolve(scheme)).frame(width: 40, height: 40)
                                        .overlay(Rectangle().strokeBorder(LifeOSTokens.primaryText.resolve(scheme),
                                                                          lineWidth: colour == option ? 3 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.rawValue.capitalized)
                                .accessibilityAddTraits(colour == option ? .isSelected : [])
                            }
                        }
                    }
                    Toggle(isOn: $hasDates) { Text("DATES").brutalLabel() }.tint(LifeOSTokens.primaryText.resolve(scheme))
                    if hasDates {
                        DatePicker("Starts", selection: $starts, displayedComponents: .date)
                        DatePicker("Ends", selection: $ends, in: starts..., displayedComponents: .date)
                    }
                    if case .connected = github?.state {
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text("LINK A REPO").brutalLabel()
                            TextField("Search repos", text: $repoQuery)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Picker("Repo", selection: $repo) {
                                Text("None").tag(String?.none)
                                ForEach((github?.repos ?? []).filter {
                                    repoQuery.isEmpty || $0.fullName.localizedCaseInsensitiveContains(repoQuery)
                                }, id: \.fullName) { Text($0.fullName).tag(String?.some($0.fullName)) }
                            }
                            .pickerStyle(.menu)
                            .task { await github?.loadRepos() }
                        }
                    }
                }
                .padding(Space.x3)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name.trimmingCharacters(in: .whitespaces), scope, colour.rawValue,
                                 hasDates ? starts : nil, hasDates ? ends : nil, repo)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(label).brutalLabel()
            TextField(prompt, text: text)
                .font(LifeOSType.body)
                .padding(Space.x2)
                .overlay(Rectangle().strokeBorder(LifeOSTokens.primaryText.resolve(scheme), lineWidth: 2))
        }
    }
}
