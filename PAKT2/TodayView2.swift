import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState

    @State private var displayedQuote: String = ""
    @State private var currentIndex: Int = -1
    @State private var quoteOpacity: Double = 0
    @State private var isTransitioning = false
    @State private var initialY: CGFloat? = nil

    private func showInitialQuote() {
        guard currentIndex == -1 else { return }
        let list = Messages.en
        guard !list.isEmpty else { return }
        let idx = (Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1) % list.count
        currentIndex = idx
        displayedQuote = list[idx]
        withAnimation(.easeIn(duration: 0.5)) { quoteOpacity = 1 }
    }

    private func swapQuote() {
        guard !isTransitioning else { return }
        isTransitioning = true
        Task { @MainActor in
            let list = Messages.en
            guard list.count > 1 else { isTransitioning = false; return }
            var next: Int
            repeat { next = Int.random(in: 0..<list.count) } while next == currentIndex
            // Fade out
            withAnimation(.easeInOut(duration: 0.5)) { quoteOpacity = 0 }
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Swap texte sans animation
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentIndex = next
                displayedQuote = list[next]
            }
            // Fade in
            withAnimation(.easeInOut(duration: 0.5)) { quoteOpacity = 1 }
            try? await Task.sleep(nanoseconds: 700_000_000)
            // Prêt pour le prochain scroll
            initialY = nil
            isTransitioning = false
        }
    }

    @State private var selectedCategory: ActCategory? = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Quote — prend tout l'écran, change au scroll
                    VStack(spacing: 12) {
                        Spacer()
                        Text(displayedQuote)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Theme.text)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .opacity(quoteOpacity)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textFaint)
                            .padding(.bottom, 20)
                    }
                    .frame(minHeight: UIScreen.main.bounds.height - 160)
                    .padding(.horizontal, 32)
                    .onAppear { showInitialQuote() }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .global).minY) { newY in
                                    guard !isTransitioning else { return }
                                    if initialY == nil { initialY = newY }
                                    guard let start = initialY else { return }
                                    if abs(newY - start) > 80 {
                                        swapQuote()
                                    }
                                }
                        }
                    )

                    // Category pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            categoryPill(nil, label: L10n.t("all"))
                            ForEach(ActCategory.allCases, id: \.self) { cat in
                                categoryPill(cat, label: cat.label)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)

                    // Activity cards
                    let filtered = selectedCategory == nil
                        ? Activity.suggestions
                        : Activity.suggestions.filter { $0.category == selectedCategory }

                    LazyVStack(spacing: 14) {
                        ForEach(filtered) { activity in
                            activityCard(activity)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 100)
                }
            }
        }
    }

    // MARK: - Category pill

    private func categoryPill(_ cat: ActCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = cat } }) {
            Text(label)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.bg : Theme.text)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 22).fill(Theme.text)
                    } else {
                        RoundedRectangle(cornerRadius: 22).fill(.clear).liquidGlass(cornerRadius: 22)
                    }
                }
        }
        .accessibilityLabel(label)
    }

    // MARK: - Activity card

    private func activityCard(_ activity: Activity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(activity.category.color.opacity(0.1))
                    .frame(width: 56, height: 56)
                Text(activity.emoji)
                    .font(.system(size: 26))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(activity.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(2)
            }

            Spacer()

            Text(activity.people)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textFaint)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.emoji) \(activity.title). \(activity.subtitle)")
    }
}

// MARK: - Activity model

enum ActCategory: String, CaseIterable {
    case outdoor    = "outdoor"
    case food       = "food"
    case creative   = "creative"
    case sport      = "sport"
    case chill      = "chill"
    case social     = "social"

    var label: String {
        switch self {
        case .outdoor:  return L10n.t("cat_outdoor")
        case .food:     return L10n.t("cat_food")
        case .creative: return L10n.t("cat_creative")
        case .sport:    return L10n.t("cat_sport")
        case .chill:    return L10n.t("cat_chill")
        case .social:   return L10n.t("cat_social")
        }
    }

    var icon: String {
        switch self {
        case .outdoor:  return "leaf"
        case .food:     return "fork.knife"
        case .creative: return "paintbrush"
        case .sport:    return "figure.run"
        case .chill:    return "cup.and.saucer"
        case .social:   return "person.2"
        }
    }

    var color: Color {
        switch self {
        case .outdoor:  return Theme.green
        case .food:     return Theme.orange
        case .creative: return Color(red: 0.52, green: 0.18, blue: 0.72)
        case .sport:    return Theme.red
        case .chill:    return Theme.blue
        case .social:   return Color(red: 0.85, green: 0.55, blue: 0.20)
        }
    }
}

struct Activity: Identifiable {
    let id = UUID()
    let emoji: String
    let titleEN: String; let titleFR: String
    let subtitleEN: String; let subtitleFR: String
    let category: ActCategory
    let people: String

    var title: String { titleEN }
    var subtitle: String { subtitleEN }

    static let suggestions: [Activity] = [
        // Outdoor
        Activity(emoji: "🚶", titleEN: "Walk & talk", titleFR: "Marche & discussion", subtitleEN: "Go for a walk with a friend. No phones.", subtitleFR: "Va marcher avec un ami. Sans téléphone.", category: .outdoor, people: "2+"),
        Activity(emoji: "🌅", titleEN: "Watch the sunset", titleFR: "Regarde le coucher de soleil", subtitleEN: "Find a spot with a view. Just be there.", subtitleFR: "Trouve un endroit avec vue. Sois juste là.", category: .outdoor, people: "1+"),
        Activity(emoji: "🧗", titleEN: "Go climbing", titleFR: "Escalade", subtitleEN: "Indoor or outdoor. Push your limits together.", subtitleFR: "En salle ou dehors. Repousse tes limites.", category: .outdoor, people: "2+"),
        Activity(emoji: "🚴", titleEN: "Bike ride", titleFR: "Balade à vélo", subtitleEN: "Explore your city on two wheels.", subtitleFR: "Explore ta ville sur deux roues.", category: .outdoor, people: "1+"),
        Activity(emoji: "🏕️", titleEN: "Picnic in the park", titleFR: "Pique-nique au parc", subtitleEN: "Grab some food, a blanket, and enjoy.", subtitleFR: "Prends à manger, une couverture, et profite.", category: .outdoor, people: "2+"),

        // Food
        Activity(emoji: "🍳", titleEN: "Cook together", titleFR: "Cuisiner ensemble", subtitleEN: "Pick a recipe you've never tried.", subtitleFR: "Choisis une recette que t'as jamais testée.", category: .food, people: "2+"),
        Activity(emoji: "☕", titleEN: "Coffee date", titleFR: "Café entre amis", subtitleEN: "A real conversation over a good coffee.", subtitleFR: "Une vraie conversation autour d'un bon café.", category: .food, people: "2"),
        Activity(emoji: "🍕", titleEN: "Pizza night", titleFR: "Soirée pizza", subtitleEN: "Everyone makes their own. Vote for the best.", subtitleFR: "Chacun fait la sienne. On vote pour la meilleure.", category: .food, people: "3+"),
        Activity(emoji: "🧁", titleEN: "Bake something", titleFR: "Pâtisserie", subtitleEN: "Cookies, cake, bread — just bake.", subtitleFR: "Cookies, gâteau, pain — fais-toi plaisir.", category: .food, people: "1+"),

        // Creative
        Activity(emoji: "🎨", titleEN: "Paint or draw", titleFR: "Peindre ou dessiner", subtitleEN: "No talent needed. Just express yourself.", subtitleFR: "Pas besoin de talent. Exprime-toi.", category: .creative, people: "1+"),
        Activity(emoji: "📸", titleEN: "Photo walk", titleFR: "Balade photo", subtitleEN: "Walk around with a camera. See differently.", subtitleFR: "Balade-toi avec un appareil. Vois autrement.", category: .creative, people: "1+"),
        Activity(emoji: "🎸", titleEN: "Jam session", titleFR: "Session musique", subtitleEN: "Grab instruments and play. Or just sing.", subtitleFR: "Prends un instrument et joue. Ou chante.", category: .creative, people: "2+"),
        Activity(emoji: "📝", titleEN: "Write a letter", titleFR: "Écrire une lettre", subtitleEN: "To someone you care about. On paper.", subtitleFR: "À quelqu'un qui compte. Sur du vrai papier.", category: .creative, people: "1"),

        // Sport
        Activity(emoji: "🏀", titleEN: "Shoot hoops", titleFR: "Basket", subtitleEN: "Find a court. Play one-on-one.", subtitleFR: "Trouve un terrain. Joue en un contre un.", category: .sport, people: "2+"),
        Activity(emoji: "🏊", titleEN: "Go swimming", titleFR: "Nager", subtitleEN: "Pool, lake, or ocean. Just get in.", subtitleFR: "Piscine, lac ou mer. Jette-toi à l'eau.", category: .sport, people: "1+"),
        Activity(emoji: "🧘", titleEN: "Yoga or stretch", titleFR: "Yoga ou étirements", subtitleEN: "20 minutes of presence. No app needed.", subtitleFR: "20 minutes de présence. Pas besoin d'app.", category: .sport, people: "1+"),
        Activity(emoji: "🏓", titleEN: "Ping pong", titleFR: "Ping pong", subtitleEN: "Fast, fun, and surprisingly competitive.", subtitleFR: "Rapide, fun, et étonnamment compétitif.", category: .sport, people: "2"),

        // Chill
        Activity(emoji: "📖", titleEN: "Read a book", titleFR: "Lire un livre", subtitleEN: "A real one. With pages. 30 minutes.", subtitleFR: "Un vrai. Avec des pages. 30 minutes.", category: .chill, people: "1"),
        Activity(emoji: "🎲", titleEN: "Board game night", titleFR: "Soirée jeux de société", subtitleEN: "Classic. Competitive. Screen-free.", subtitleFR: "Classique. Compétitif. Sans écran.", category: .chill, people: "3+"),
        Activity(emoji: "🧩", titleEN: "Puzzle", titleFR: "Puzzle", subtitleEN: "1000 pieces. Good music. No rush.", subtitleFR: "1000 pièces. Bonne musique. Pas de rush.", category: .chill, people: "1+"),
        Activity(emoji: "🎬", titleEN: "Movie night", titleFR: "Soirée film", subtitleEN: "Pick a movie together. Popcorn mandatory.", subtitleFR: "Choisissez un film ensemble. Popcorn obligatoire.", category: .chill, people: "2+"),

        // Social
        Activity(emoji: "🍻", titleEN: "Apéro", titleFR: "Apéro", subtitleEN: "Invite friends over. Keep it real.", subtitleFR: "Invite des potes. Reste simple, reste vrai.", category: .social, people: "3+"),
        Activity(emoji: "🎤", titleEN: "Karaoke", titleFR: "Karaoké", subtitleEN: "At home or at a bar. No judgment.", subtitleFR: "Chez toi ou dans un bar. Zéro jugement.", category: .social, people: "3+"),
        Activity(emoji: "🤝", titleEN: "Volunteer", titleFR: "Bénévolat", subtitleEN: "Give your time to something meaningful.", subtitleFR: "Donne ton temps pour quelque chose qui compte.", category: .social, people: "1+"),
        Activity(emoji: "🗣️", titleEN: "Deep conversation", titleFR: "Discussion profonde", subtitleEN: "Ask real questions. Listen. No phones.", subtitleFR: "Pose de vraies questions. Écoute. Sans téléphone.", category: .social, people: "2"),
    ]
}
