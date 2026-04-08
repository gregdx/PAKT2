# 🎨 Guide des Animations - PAKT App

Ce guide récapitule toutes les animations ajoutées à l'application PAKT pour une expérience utilisateur fluide et engageante.

## 📱 FriendProfileView (Profil d'ami)

### Animations d'apparition
- **Avatar** : Scale + fade (0.5 → 1.0) avec spring bounce
- **Nom** : Slide up + fade avec délai 0.1s
- **Badge Veteran** : Slide up + fade avec délai 0.15s
- **Bio** : Slide up + fade avec délai 0.2s

### Effet Parallaxe au Scroll
- **Header** : Se déplace à 0.3x la vitesse du scroll
- **Avatar** : Se déplace à 0.5x + agrandit au scroll up
- **Nom** : Se déplace à 0.4x
- **Veteran badge** : Se déplace à 0.35x
- **Bio** : Se déplace à 0.25x

### Médailles (Achievements)
- **Apparition en cascade** : Chaque médaille apparaît avec délai progressif (index × 0.05s)
- **Animation bounce** : Effet SF Symbol bounce sur les icônes
- **Tap interaction** : 
  - Scale 1.15x avec spring
  - Feedback haptique (medium)
  - Effet de particules colorées (12 particules en explosion)
- **Particules** : 
  - Distribution circulaire (coordonnées polaires)
  - Apparition 0.6s, disparition 0.4s
  - Couleur adaptée à chaque médaille

### Transition de dismiss
- Asymmetric transition (slide right + opacity)
- Animation spring sur le bouton back

---

## 👤 ProfileView (Mon Profil)

### Header
- **Titre "Profile"** : Fade + scale
- **Boutons (Friends/Settings)** : Scale 0.5 → 1.0 avec spring
- **Badge notification rouge** : Scale 0 → 1 avec délai 0.3s
- **Avatar** : Scale 0.7 → 1.0
- **Icône caméra** : Scale 0 → 1 (apparaît sur l'avatar)
- **Nom d'utilisateur** : Scale 0.8 → 1.0

### Stats Today/Social
- **Scale 0.5 → 1.0** avec délai 0.15s
- **Séparateur** : ScaleY animation
- **Nombres** : `.contentTransition(.numericText())` pour transitions fluides

### Streak Badge 🔥
- **Scale 0.8 → 1.0** à l'apparition
- **Animation pulse** : Scale 1.3x qui pulse 3 fois si streak ≥ 3 jours
- **Auto-déclenchement** : Démarre 0.5s après apparition

### Week Chart
- **Container** : Scale 0.9 → 1.0 + fade
- **Barres du graphique** : 
  - ScaleY 0.01 → 1.0 depuis le bas
  - Délai progressif (index × 0.05s) pour effet cascade
  - Spring animation (response: 0.6, damping: 0.7)
- **Tap sur une barre** :
  - Feedback haptique léger
  - Scale 1.15x sur la barre sélectionnée
  - Transition top slide pour les détails
- **Detail card** : Slide from top + opacity

### Médailles
- **Container** : Scale 0.9 → 1.0 + fade avec délai 0.45s
- **Chaque médaille** : 
  - Scale 0.5 → 1.0
  - Délai progressif (index × 0.04s)
  - Spring bounce
- **Tap sur médaille** :
  - Feedback haptique (medium)
  - Scale 1.2x temporaire
  - Symbol bounce effect
- **Compteur** : `.contentTransition(.numericText())`
- **Chevron See All** : Rotation 180° au toggle

### Séquence d'apparition
1. **0s** : Header (response: 0.6)
2. **0.15s** : Stats + Streak (response: 0.7)
3. **0.3s** : Chart (response: 0.8)
4. **0.45s** : Medals (response: 0.8)

---

## 🏆 ChallengeResultView (Résultat du Challenge)

### Célébration de Victoire (isSuccess = true)

#### Intro Slide
- **Emoji 🏆** : 
  - Scale 0.3 → 1.0
  - Rotation 360° → 0°
  - Spring bounce (response: 0.6)
- **Nom du groupe** : Slide up 30px + fade
- **"CHALLENGE COMPLETE"** : Scale 0.8 → 1.0
- **Badge durée** : Scale 0.5 → 1.0 avec capsule background

#### Effets Spéciaux 🎆
- **Confettis** :
  - 80 pièces colorées
  - Chute depuis le haut avec rotation aléatoire (-720° à 720°)
  - 8 couleurs différentes
  - Durée : 3s chute + 1.5s fade out
  - Déclenché à 0.8s après apparition
  
- **Feux d'artifice** :
  - Nouveau feu toutes les 0.4s
  - 20 particules par explosion
  - Distribution circulaire parfaite (2π radians)
  - Explosion pendant 0.8s
  - Fade out gravitationnel 0.6s
  - Couleurs : rouge, bleu, jaune, orange, violet, rose, vert, blanc
  - Actifs pendant 4 secondes totales

- **Feedback haptique** : UINotificationFeedbackGenerator (.success)

#### Winner Slide (mode compétitif)
- **Badge "THE WINNER"** : Fade + tracking 4
- **Avatar** : 
  - Scale + shadow vert
  - Border animé
  - Taille : 110px
- **Nom** : Black font 38pt avec slide
- **Score** : Huge 56pt en vert avec spring

#### Ranking Slide
- **Titre** : Fade avec tracking
- **Chaque membre** :
  - Délai progressif : 0.15 + (index × 0.08s)
  - Slide from left + scale
  - Emoji pour top 3 : 🥇🥈🥉
  - Badge rang pour les autres

#### Best/Worst Day Slides
- **Stats** : Cascade d'apparition
- **Avatar** : Scale + colored border
- **Score géant** : 64pt bold avec color coding

#### Group Stats Slide
- **4 stat cards** :
  - Délais : 0.3s, 0.4s, 0.5s, 0.6s
  - Scale + opacity
  - Color accents (green/orange/white/red)

#### Play Again Slide
- **Emoji 🔥** : Bounce in
- **Titre** : Black 38pt scale in
- **Boutons** :
  - "Restart Challenge" : Blanc bold
  - "Harder Goal" : Semi-transparent
  - Animations au press

### Background Gradients
- **7 dégradés uniques** pour chaque slide
- Transition fluide (0.5s easeInOut) entre slides
- Couleurs profondes pour contraste optimal

### Navigation
- **Progress dots** : 
  - Capsule active : 18px width
  - Dots inactifs : 6px
  - Smooth transition 0.3s
- **Swipe hint** : Fade in à 1s + chevron

---

## 🎯 Principes d'Animation Utilisés

### Timing Functions
- **Spring** : Mouvement naturel et rebondissant
  - Response: 0.3-0.8s (plus rapide = plus snappy)
  - Damping: 0.5-0.8 (plus bas = plus de rebond)
- **EaseOut** : Démarrage rapide, fin douce
- **EaseIn** : Démarrage doux, fin rapide
- **EaseInOut** : Doux aux deux extrémités

### Délais en Cascade
- Médailles/Items : index × 0.04-0.05s
- Slides/Sections : 0.1-0.2s entre éléments
- Permet une lecture visuelle séquentielle

### Feedback Haptique
- **Light** : Tap sur graphique
- **Medium** : Tap sur médaille
- **Success** : Victoire challenge

### Transitions
- **Scale** : 0.3-0.9 → 1.0 (plus petit = plus dramatique)
- **Opacity** : 0 → 1 (toujours avec autre transform)
- **Offset** : 20-30px pour slides
- **Rotation** : 360° pour célébrations

### Performance
- `.contentTransition(.numericText())` : Smooth number updates
- `.allowsHitTesting(false)` : Effets décoratifs n'interfèrent pas
- Timers invalidés dans `.onDisappear`
- Animations conditionnelles (only if success)

---

## 🚀 Améliorations Futures Possibles

1. **Shimmer Effect** sur médailles récemment débloquées
2. **3D Rotation** sur avatars au tap
3. **Particle trails** en suivant le doigt
4. **Sound effects** synchronisés aux animations
5. **Liquid Glass morphing** entre écrans
6. **Skeleton loaders** pendant chargement
7. **Pull-to-refresh** avec animation custom
8. **Gamification** : XP bars avec fill animation

---

## 📊 Récapitulatif des Animations par Fichier

| Fichier | Animations | Complexité |
|---------|-----------|------------|
| FriendProfileView | 15+ | ⭐⭐⭐⭐ |
| ProfileView | 20+ | ⭐⭐⭐⭐⭐ |
| ChallengeResultView | 30+ | ⭐⭐⭐⭐⭐ |
| **TOTAL** | **65+ animations** | 🎨🔥 |

---

Dernière mise à jour : 4 avril 2026
