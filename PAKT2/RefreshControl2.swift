import SwiftUI

struct RefreshControl: View {
    @Binding var isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        GeometryReader { geo in
            if geo.frame(in: .global).minY > 50 {
                Spacer()
                    .onAppear {
                        if !isRefreshing {
                            isRefreshing = true
                            action()
                        }
                    }
            }
            HStack {
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .tint(Theme.textMuted)
                }
                Spacer()
            }
            .opacity(geo.frame(in: .global).minY > 20 ? 1 : 0)
        }
        .frame(height: isRefreshing ? 44 : 0)
        .animation(.easeInOut, value: isRefreshing)
    }
}
