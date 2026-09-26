import SwiftUI

struct ReviewView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "review.empty.title",
                systemImage: "book.pages",
                description: Text("review.empty.description")
            )
            .navigationTitle("tab.review")
        }
    }
}

