import SwiftUI

struct StrategyListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("strategies.built_in") {
                    ForEach(model.strategies) { strategy in
                        Button {
                            model.selectStrategy(strategy)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(strategy.name).font(.headline)
                                Spacer()
                                if model.selectedStrategyID == strategy.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(strategy.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    ContentUnavailableView(
                        "strategies.custom.empty",
                        systemImage: "slider.horizontal.3",
                        description: Text("strategies.custom.later")
                    )
                }
            }
            .navigationTitle("tab.strategies")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("strategies.add", systemImage: "plus") {}
                        .disabled(true)
                }
            }
        }
    }
}
