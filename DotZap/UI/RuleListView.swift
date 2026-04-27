// DotZap — auto-deletes Apple metadata junk on every mounted volume.
// Copyright (C) 2026 Brandon Villar
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI

struct RuleListView: View {
    @ObservedObject private var state = AppState.shared
    @State private var showingAddForm: Bool = false
    @State private var pendingDeletionId: UUID?

    @State private var newName: String = ""
    @State private var newPattern: String = ""
    @State private var newMatchType: CleanRule.MatchType = .exact

    private var builtInRules: [CleanRule] { state.rules.filter(\.isBuiltIn) }
    private var customRules: [CleanRule] { state.rules.filter { !$0.isBuiltIn } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                section(title: "Built-in Rules") {
                    ForEach(builtInRules) { rule in
                        RuleRow(rule: rule, pendingDeletionId: $pendingDeletionId)
                            .padding(.horizontal, 10)
                    }
                }

                section(title: "Custom Rules") {
                    if showingAddForm {
                        addForm
                            .padding(.horizontal, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if customRules.isEmpty && !showingAddForm {
                        Text("No custom rules yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(customRules) { rule in
                            RuleRow(rule: rule, pendingDeletionId: $pendingDeletionId)
                                .padding(.horizontal, 10)
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showingAddForm.toggle()
                                if !showingAddForm { resetForm() }
                            }
                        } label: {
                            Label(showingAddForm ? "Cancel" : "Add Rule",
                                  systemImage: showingAddForm ? "xmark" : "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(GlassButtonStyle(prominent: !showingAddForm))
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.top, 6)
            content()
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Custom Rule")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextField("Name (e.g. Photoshop Temp)", text: $newName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            TextField("Pattern (e.g. *.psd~ or .DocumentRevisions-V100)", text: $newPattern)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            Picker("", selection: $newMatchType) {
                ForEach(CleanRule.MatchType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Cancel") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        resetForm()
                        showingAddForm = false
                    }
                }
                .buttonStyle(GlassButtonStyle())

                Button("Save") {
                    state.addCustomRule(name: newName, pattern: newPattern, matchType: newMatchType)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        resetForm()
                        showingAddForm = false
                    }
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                       || newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func resetForm() {
        newName = ""
        newPattern = ""
        newMatchType = .exact
    }
}

private struct RuleRow: View {
    let rule: CleanRule
    @ObservedObject private var state = AppState.shared
    @Binding var pendingDeletionId: UUID?

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { state.setRuleEnabled(id: rule.id, enabled: $0) }
        )
    }

    private var isPendingDelete: Bool { pendingDeletionId == rule.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name)
                        .font(.system(size: 12, weight: .medium))
                    Text("\(rule.matchType.label) · \(rule.pattern)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                if rule.isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            pendingDeletionId = isPendingDelete ? nil : rule.id
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(isPendingDelete ? .red : .secondary)
                    }
                    .buttonStyle(GlassIconButtonStyle())
                }
            }
            .padding(10)

            if isPendingDelete {
                HStack {
                    Text("Delete this rule?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            pendingDeletionId = nil
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    Button("Delete") {
                        let id = rule.id
                        withAnimation(.easeInOut(duration: 0.2)) {
                            pendingDeletionId = nil
                        }
                        state.deleteRule(id: id)
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var iconName: String {
        if rule.isBuiltIn { return "checkmark.seal.fill" }
        switch rule.matchType {
        case .exact:  return "equal"
        case .prefix: return "arrow.right.to.line.compact"
        case .glob:   return "asterisk"
        }
    }
}
