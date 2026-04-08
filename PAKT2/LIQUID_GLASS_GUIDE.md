# 🪟 Guide Liquid Glass - PAKT App

## Vue d'ensemble

Le système Liquid Glass de PAKT offre 5 styles différents d'effets de verre, allant du très transparent au presque opaque. Chaque style crée une profondeur visuelle unique et s'adapte automatiquement aux thèmes clair/foncé.

---

## 🎨 Les 5 Styles

### 1. `.ultraThin` - Ultra Transparent
**Usage** : Messages, input fields, petits boutons d'action

```swift
Text("Hello")
    .liquidGlass(cornerRadius: 18, style: .ultraThin)
```

**Caractéristiques** :
- Material : `.ultraThinMaterial`
- Gradient : 8% → 3% blanc
- Border : 0.2 → 0.05 opacity
- Shadow : 0.03 opacity, 4pt radius
- **Effet** : Presque invisible, laisse passer la couleur de fond

**Où l'utiliser** :
- Bulles de chat (comme iMessage)
- Input de texte
- Boutons header (Friends/Settings dans ProfileView)
- Tags/badges légers

---

### 2. `.thin` - Léger et Translucide
**Usage** : Cards, containeurs secondaires, sections de contenu

```swift
VStack {
    // Contenu
}
.liquidGlass(cornerRadius: 14, style: .thin)
```

**Caractéristiques** :
- Material : `.thinMaterial`
- Gradient : 12% → 5% blanc
- Border : 0.25 → 0.08 opacity
- Shadow : 0.05 opacity, 6pt radius
- **Effet** : Très léger, élégant, moderne

**Où l'utiliser** :
- Cards de profil (médailles, stats)
- Insight cards
- Chart containers
- Groupe cards dans ProfileView

---

### 3. `.regular` - Équilibré (Défaut)
**Usage** : Containeurs principaux, modals, panels

```swift
VStack {
    // Contenu principal
}
.liquidGlass(cornerRadius: 16, style: .regular)
// ou simplement
.liquidGlass(cornerRadius: 16)
```

**Caractéristiques** :
- Material : `.regularMaterial`
- Gradient : 15% → 8% blanc
- Border : 0.3 → 0.1 opacity
- Shadow : 0.08 opacity, 8pt radius
- **Effet** : Équilibre parfait visibilité/transparence

**Où l'utiliser** :
- Modals principales
- Settings panels
- Navigation bars custom
- Cards importantes

---

### 4. `.thick` - Plus Opaque
**Usage** : Overlays, popups, éléments qui doivent se détacher

```swift
VStack {
    // Contenu overlay
}
.liquidGlass(cornerRadius: 20, style: .thick)
```

**Caractéristiques** :
- Material : `.thickMaterial`
- Gradient : 20% → 12% blanc
- Border : 0.35 → 0.12 opacity
- Shadow : 0.12 opacity, 10pt radius
- **Effet** : Bien visible, se détache du fond

**Où l'utiliser** :
- Confirmation dialogs
- Popovers
- Achievement unlock notifications
- Success/Error toasts

---

### 5. `.solid` - Presque Opaque
**Usage** : Navigation bars, tab bars, headers fixes

```swift
HStack {
    // Header content
}
.liquidGlass(cornerRadius: 0, style: .solid)
```

**Caractéristiques** :
- Material : `.thickMaterial`
- Gradient : 30% → 20% blanc
- Border : 0.4 → 0.15 opacity
- Shadow : 0.15 opacity, 12pt radius
- **Effet** : Très visible, presque opaque mais garde un léger blur

**Où l'utiliser** :
- Tab bar custom
- Fixed navigation headers
- Bottom sheets
- Persistent UI elements

---

## 🏗️ Anatomie Technique

Chaque style Liquid Glass combine **4 couches** :

```
┌─────────────────────────────────┐
│  1. Border Gradient (top→bottom)│ ← Effet de lumière
├─────────────────────────────────┤
│  2. Color Gradient              │ ← Profondeur
├─────────────────────────────────┤
│  3. Blur Material               │ ← Frosted glass
├─────────────────────────────────┤
│  4. Drop Shadow                 │ ← Élévation
└─────────────────────────────────┘
```

### Paramètres par Style

| Style | Material | Gradient Opacity | Border Top | Shadow |
|-------|----------|------------------|------------|--------|
| `.ultraThin` | ultraThin | 0.3 | 0.2 | 0.03 |
| `.thin` | thin | 0.4 | 0.25 | 0.05 |
| `.regular` | regular | 0.5 | 0.3 | 0.08 |
| `.thick` | thick | 0.6 | 0.35 | 0.12 |
| `.solid` | thick | 0.8 | 0.4 | 0.15 |

---

## 📱 Utilisation dans PAKT

### ProfileView
```swift
// Boutons header - ultra légers
.liquidGlass(cornerRadius: 10, style: .ultraThin)

// Charts et stats - légers mais visibles
.liquidGlass(cornerRadius: 16, style: .thin)

// Medals card - container secondaire
.liquidGlass(cornerRadius: 16, style: .thin)
```

### GroupChatView
```swift
// Message bubbles - iMessage style
.liquidGlass(cornerRadius: 18, style: .ultraThin)

// Input field - même style que messages
.liquidGlass(cornerRadius: 20, style: .ultraThin)
```

### Buttons et Actions
```swift
// Primary buttons - bien visibles
.liquidGlass(cornerRadius: 16, style: .thin)

// Floating action buttons
.liquidGlass(cornerRadius: .infinity, style: .regular)
```

---

## 🎯 Best Practices

### 1. Hiérarchie Visuelle
Utilisez les styles pour créer de la profondeur :
- Background elements → `.ultraThin` / `.thin`
- Main content → `.thin` / `.regular`
- Overlays → `.thick` / `.solid`

### 2. Contraste Texte
- `.ultraThin` / `.thin` : Utilisez du texte bold
- `.regular` : Texte normal OK
- `.thick` / `.solid` : Tous les poids fonctionnent

### 3. Coins Arrondis
Plus le style est léger, plus les coins peuvent être arrondis :
- Messages : 18-20px
- Cards : 14-16px
- Containers : 12-14px
- Buttons : 10-16px

### 4. Layering
Évitez de stacker plusieurs `.thin` ou `.ultraThin` - ça devient invisible.
Préférez :
```swift
// ❌ Ne pas faire
VStack {
    Text("...")
        .liquidGlass(style: .thin)
}
.liquidGlass(style: .thin)

// ✅ Faire
VStack {
    Text("...")
}
.liquidGlass(style: .thin)
```

### 5. Animations
Le Liquid Glass s'anime bien avec :
- `.scaleEffect()` - bounce, press effects
- `.opacity()` - fade in/out
- `.offset()` - slide transitions

---

## 🌈 Adaptation Thème

Le Liquid Glass s'adapte automatiquement :

**Light Mode** :
- Borders plus subtiles
- Shadow plus visible
- Gradient blanc

**Dark Mode** :
- Borders plus lumineuses (effet néon)
- Shadow moins visible
- Même gradient (adapté par Material)

---

## 🔮 iOS 26+ Native Glass

Sur iOS 26+, le système utilise automatiquement `.glassEffect()` natif :
```swift
if #available(iOS 26, *) {
    content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
}
```

Ceci donne un vrai effet Liquid Glass avec :
- Morphing en temps réel
- Réaction au touch/pointer
- Meilleure performance GPU

---

## 🎨 Exemples Visuels

### Message Style (ultraThin)
```
┌─────────────────────────────┐
│ Hey! This is a message 💬  │ ← Presque invisible
└─────────────────────────────┘
```

### Card Style (thin)
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  📊 Today's Stats          ┃ ← Léger, élégant
┃  2h 15m                    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Button Style (regular)
```
╔═════════════════════════════╗
║   Continue  →               ║ ← Bien défini
╚═════════════════════════════╝
```

---

## 🚀 Migration

Pour migrer du vieux `.liquidGlass()` vers les styles :

### Avant
```swift
.liquidGlass(cornerRadius: 14)
```

### Après - Choisir le style approprié
```swift
// Messages, inputs
.liquidGlass(cornerRadius: 14, style: .ultraThin)

// Cards, containers
.liquidGlass(cornerRadius: 14, style: .thin)

// Buttons, actions (ou laisser default)
.liquidGlass(cornerRadius: 14, style: .regular)
// ou simplement
.liquidGlass(cornerRadius: 14)
```

---

## 📐 Recommandations par Type de Contenu

| Type | Style | Corner Radius |
|------|-------|---------------|
| Chat bubbles | `.ultraThin` | 18-20 |
| Text inputs | `.ultraThin` | 20-24 |
| Small buttons | `.ultraThin` | 10-12 |
| Stat cards | `.thin` | 14-16 |
| Profile cards | `.thin` | 16-18 |
| Charts | `.thin` | 14-16 |
| Primary buttons | `.thin` | 14-16 |
| Modals | `.regular` | 16-20 |
| Alerts | `.thick` | 16-20 |
| Tab bar | `.solid` | 0 (top only) |
| Nav bar | `.solid` | 0 (bottom only) |

---

Dernière mise à jour : 4 avril 2026
Version : 2.0 - Système Liquid Glass Multi-Style
