# Ticketmaster API Integration Guide

## 🎟️ Configuration

### 1. Obtenir une clé API Ticketmaster

1. Va sur **https://developer.ticketmaster.com/**
2. Clique sur **"Get Your API Key"**
3. Crée un compte (gratuit)
4. Dans ton dashboard, copie ta **API Key**

### 2. Ajouter la clé dans l'app

Ouvre `TicketmasterAPI.swift` et remplace :

```swift
private let apiKey = "YOUR_API_KEY_HERE"
```

Par ta vraie clé :

```swift
private let apiKey = "ta_vraie_cle_api_ici"
```

### 3. Ajouter les permissions de localisation

Dans `Info.plist`, ajoute ces clés :

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Nous utilisons votre position pour trouver des événements près de chez vous</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Nous utilisons votre position pour trouver des événements près de chez vous</string>
```

## 📱 Fonctionnalités

### Onglet "Events" dans NearYouView

- ✅ Affiche les événements Ticketmaster proches de la position de l'utilisateur
- ✅ Rayon configurable (1-20 km, par défaut 25 km)
- ✅ Images HD des événements
- ✅ Catégories (Music, Sports, Arts, etc.)
- ✅ Date, heure, lieu
- ✅ Prix (si disponible)
- ✅ Lien direct vers l'achat de billets

### EventDetailSheet

- 📸 Image hero de l'événement
- 📅 Date et heure formatées
- 📍 Venue (nom + adresse complète)
- 💶 Prix (min-max ou "À partir de")
- ℹ️ Description et notes importantes
- 🎫 Bouton "Get Tickets" → ouvre Ticketmaster

## 🔧 API Endpoints utilisés

```swift
// Nearby events
GET /discovery/v2/events.json
Parameters:
  - apikey: your_api_key
  - latlong: "50.8503,4.3517"  // Bruxelles
  - radius: 25
  - unit: "km"
  - size: 50
  - sort: "date,asc"
```

## 🎨 Design

L'intégration respecte complètement le design actuel de PAKT :

- **Liquid Glass** pour tous les cards
- **Theme.text / Theme.textMuted** pour les couleurs
- **Animations smooth** au chargement
- **Glassmorphism** sur tous les éléments
- **CachedAsyncImage** pour les images optimisées

## 🚀 Limites de l'API gratuite

- ✅ **5000 requêtes/jour**
- ✅ **Rate limit: 5 req/sec**
- ✅ Parfait pour une app en développement

## 📊 Données retournées

Chaque événement contient :

```swift
struct TMEvent {
    let id: String
    let name: String              // "Coldplay - Music of the Spheres"
    let url: String               // Lien Ticketmaster
    let images: [TMImage]         // Photos HD
    let dates: TMDates            // Date/heure
    let venue: TMVenue?           // Lieu (nom, adresse, coords)
    let priceRanges: [TMPriceRange]? // Prix min/max
    let classifications: [...]    // Catégorie, genre
    let info: String?             // Description
    let pleaseNote: String?       // Notes importantes
}
```

## 🔄 Alternatives

Si tu veux d'autres sources d'événements :

1. **Eventbrite** : events.eventbriteapi.com
2. **SeatGeek** : api.seatgeek.com
3. **Bandsintown** : rest.bandsintown.com

Ticketmaster est recommandé car :
- ✅ Meilleure couverture en Europe
- ✅ API la plus fiable
- ✅ Images HD de qualité
- ✅ Catégories riches (Music, Sports, Theatre, etc.)

## 🎯 Next Steps

Pour améliorer encore :

1. **Filtres par catégorie** (Music, Sports, Arts, etc.)
2. **Recherche par mot-clé**
3. **Favoris** (save events)
4. **Inviter un ami** à un événement (comme les Venues)
5. **Calendar sync** (ajouter au calendrier iOS)

---

**Made for PAKT** 🤝  
Aide tes utilisateurs à découvrir des événements au lieu de scroller !
