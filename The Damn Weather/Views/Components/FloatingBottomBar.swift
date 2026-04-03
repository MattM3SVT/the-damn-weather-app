import SwiftUI

/// Floating bottom toolbar — Apple Weather style:
/// Location arrow + page dots (center) | List button (right)
struct FloatingBottomBar: View {
    let currentPage: Int
    let pageCount: Int
    let onListTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            // Left spacer to balance the list button
            Color.clear
                .frame(width: 44, height: 44)

            Spacer()

            // Page dots with location arrow on first dot
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    if index == 0 {
                        // Current location indicator
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(currentPage == 0 ? .white : .white.opacity(0.35))
                    } else {
                        Circle()
                            .fill(currentPage == index ? .white : .white.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: currentPage)

            Spacer()

            // List button
            Button(action: onListTap) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.12), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    }
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.25), .white.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
