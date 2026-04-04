import SwiftUI

/// Bottom toolbar — Apple Weather liquid glass style:
/// Glass capsule with page dots (center) + glass circle list button (right)
struct FloatingBottomBar: View {
    let currentPage: Int
    let pageCount: Int
    let onListTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            // Page dots capsule — only show when multiple cities
            if pageCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        if index == 0 {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(currentPage == 0 ? .white : .white.opacity(0.3))
                        } else {
                            Circle()
                                .fill(currentPage == index ? .white : .white.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .animation(.easeInOut(duration: 0.2), value: currentPage)
            }

            // List button
            Button(action: onListTap) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
