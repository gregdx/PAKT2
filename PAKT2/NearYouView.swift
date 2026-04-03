import SwiftUI

struct NearYouView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(L10n.t("near_you_title"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 24)

                Spacer()

                // Coming soon placeholder
                VStack(spacing: 20) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.textFaint)

                    Text(L10n.t("near_you_coming"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)

                    Text(L10n.t("near_you_desc"))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 40)

                Spacer()
                Spacer()
            }
        }
    }
}
