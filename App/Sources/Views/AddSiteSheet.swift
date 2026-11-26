import SiteKit
import SwiftUI

struct AddSiteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var plan: SquarespacePlan = .unknown
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Squarespace Site")
                .font(.title2.weight(.semibold))
            Text("The app reads the site's public pages to check that it's on Squarespace and to find its version and template. Nothing on the site changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Address", text: $address, prompt: Text("www.example.com"))
                    .onSubmit(add)
                Picker("Plan", selection: $plan) {
                    ForEach(SquarespacePlan.allCases) { plan in
                        Text(plan.displayName).tag(plan)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 120)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text("Checking the site…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Site", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func add() {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            do {
                try await model.addSite(address: address, plan: plan)
                isWorking = false
                dismiss()
            } catch {
                isWorking = false
                errorText = error.localizedDescription
            }
        }
    }
}
