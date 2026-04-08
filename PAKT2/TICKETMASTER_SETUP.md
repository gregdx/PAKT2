# Eventbrite API Integration Guide 🇧🇪

## 🎟️ Configuration

### 1. Obtenir un token OAuth Eventbrite

1. Va sur **https://www.eventbrite.com/platform/**
2. Crée un compte développeur (gratuit)
3. Crée une app dans **Account Settings > Developer Links > API Keys**
4. Copie ton **Private Token** (OAuth token)

### 2. Ajouter le token dans l'app

Ouvre `TicketmasterAPI.swift` (renommé mais garde ce nom) et remplace :

```swift
private let token = "QTAUTGG4R4NAXZS6CHQD"
```

Par ton vrai token :

```swift
private let token = "ton_token_oauth_ici"
```

### 3. Permissions de localisation

Dans `Info.plist`, ajoute ces clés :

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Nous utilisons votre position pour trouver des événements près de chez vous</string>
```

## 📱 Fonctionnalités

### Onglet "Events" dans NearYouView

- ✅ Affiche les événements Eventbrite en Belgique
- ✅ Rayon configurable (1-20 km, par défaut 25 km)
- ✅ Images des événements
- ✅ Catégories (Music, Arts & Culture, Food & Drink, etc.)
- ✅ Date, heure, lieu
- ✅ Prix (gratuit ou payant)
- ✅ Lien direct vers Eventbrite

### EventDetailSheet

- 📸 Image de l'événement
- 📅 Date et heure formatées
- 📍 Venue (nom + adresse complète)
- 💶 Prix (gratuit ou payant)
- ℹ️ Description complète
- 🎫 Bouton "Get Tickets" → ouvre Eventbrite

## 🔧 API Endpoints utilisés

```swift
// Nearby events
GET /v3/events/search/
Parameters:
  - location.latitude: 50.8503
  - location.longitude: 4.3517
  - location.within: "25km"
  - expand: "venue,category"
  - sort_by: "date"
  - page_size: 50
```

## 🎨 Design

L'intégration respecte le design PAKT :

- **Liquid Glass** pour tous les cards
- **Theme colors** cohérentes
- **Animations smooth**
- **Glassmorphism** partout
- **CachedAsyncImage** optimisé

## 🚀 Limites de l'API gratuite

- ✅ **Illimité** pour les requêtes GET
- ✅ **Rate limit: 1000 req/heure** par IP
- ✅ Parfait pour une app en production

## 📊 Données retournées

Chaque événement contient :

```swift
struct EventbriteEvent {
    let id: String
    let name: String              // "Belgian Beer Weekend"
    let url: String               // Lien Eventbrite
    let logo: EventLogo?          // Image HD
    let start: EventDateTime      // Date/heure début
    let end: EventDateTime        // Date/heure fin
    let venue: EventbriteVenue?   // Lieu (nom, adresse, coords)
    let category: EventCategory?  // Catégorie
    let isFree: Bool             // Gratuit ou non
    let description: String?     // Description
}
```

## 🇧🇪 Pourquoi Eventbrite pour la Belgique ?

✅ **Très populaire en Belgique** (Bruxelles, Gand, Anvers)  
✅ **Tous types d'événements** : concerts, festivals, workshops, networking  
✅ **API gratuite et fiable**  
✅ **Excellent pour les petits événements locaux**  
✅ **Intégration officielle** avec Facebook Events  

## 🎯 Événements typiques en Belgique

- 🎵 **Concerts** : AB, Ancienne Belgique, Botanique
- 🎭 **Théâtre & spectacles**
- 🎨 **Expos & vernissages**
- 🍺 **Food & drink** : beer festivals, wine tastings
- 💼 **Networking & workshops**
- 🏃 **Sport** : runs, yoga, fitness events
- 🎉 **Festivals** : Tomorrowland, Couleur Café, etc.

## 🔄 Alternative si besoin

Si Eventbrite ne suffit pas, tu peux aussi combiner avec :

1. **Facebook Events Graph API** (nécessite review)
2. **Meetup API** (networking events)
3. **Last.fm Events** (concerts uniquement)

---

**Made for PAKT** 🤝  
Parfait pour découvrir des événements belges au lieu de scroller !

