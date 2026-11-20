# PahaeMusic

Lecteur de musique Android développé avec **Flutter**. Il détecte les musiques du téléphone, propose un lecteur complet et permet de définir des **Best Parts** : des moments favoris d'une chanson, accessibles d'un seul toucher.

## Fonctionnalités

**Bibliothèque**
- Détection automatique des musiques du téléphone (via MediaStore)
- Recherche par titre
- Tri par date (plus récent par défaut ou plus ancien) ou par nom (A → Z ou Z → A), mémorisé entre les sessions
- Sélection multiple (appui long) pour ajouter à une playlist ou supprimer
- Suppression d'une musique du téléphone

**Lecteur**
- Lecture, pause, titre suivant et précédent
- Reculer ou avancer de 5 s ou 10 s
- Mode boucle sur un titre ou lecture en liste
- Barre de progression
- Modification du nom d'une chanson
- Ajout d'une image (pochette) à une chanson

**Best Parts**
- Plusieurs best parts par chanson
- Un clic saute directement à la minute et seconde définies
- Ajout, modification et suppression en saisissant minutes et secondes

**Playlists**
- Création de plusieurs playlists, renommage, suppression
- Ajout et retrait de titres, lecture complète d'une playlist

**Notification de lecture**
- Contrôles quand l'application est en arrière-plan : précédent, reculer, pause ou lecture, avancer, suivant
- Bouton de fermeture quand la lecture est en pause
- Pochette générée pour chaque musique (ou l'image choisie)

## Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) 3.27 ou plus récent
- Un téléphone Android (ou un émulateur) avec le débogage USB activé
- Android uniquement

## Installation

```bash
git clone <url-du-depot>
cd music_app
dart tool/setup.dart
flutter run
```

Le script `tool/setup.dart` est **indispensable** au premier lancement et après chaque modification des fichiers du dossier `tool`. Il :

1. génère le projet Android (`flutter create`) sans toucher au code Dart ;
2. copie l'icône de l'application et les icônes de notification ;
3. installe le fichier natif `MainActivity.kt` (détection des musiques, suppression, service de notification) ;
4. ajoute au manifeste les permissions et le service de lecture ;
5. nomme l'application « PahaeMusic » ;
6. lance `flutter pub get`.

## Générer l'APK

```bash
flutter build apk --release
```

L'APK se trouve dans `build/app/outputs/flutter-apk/app-release.apk`.

## Structure du projet

```
music_app/
├── lib/
│   ├── main.dart       # Application, écran principal, liste, playlists, sélection
│   ├── player.dart     # Écran du lecteur, mini-lecteur, best parts
│   ├── store.dart      # État, lecture, persistance, playlists, tri, suppression
│   ├── handler.dart    # Service de notification (audio_service)
│   └── ui.dart         # Thème, pochettes, dialogues communs
├── tool/
│   ├── setup.dart          # Script d'installation Android
│   ├── MainActivity.kt.txt # Code natif Android
│   └── res/                # Icônes (application et notification)
└── pubspec.yaml
```

## Dépendances

| Paquet | Rôle |
|---|---|
| `just_audio` | Lecture audio |
| `audio_service` | Notification et contrôles en arrière-plan |
| `permission_handler` | Permissions audio, stockage et notifications |
| `shared_preferences` | Sauvegarde des noms, best parts, playlists et tri |
| `image_picker` | Choix des images de chansons |
| `path_provider` | Stockage des images |
| `path` | Manipulation des chemins |

## Permissions Android

- **Musique et audio** (`READ_MEDIA_AUDIO`) : détecter les musiques (Android 13 et plus)
- **Stockage** : détecter et supprimer les musiques (Android 12 et moins)
- **Notifications** : afficher le lecteur dans les notifications (Android 13 et plus)
- **Service au premier plan** : continuer la lecture en arrière-plan

## Remarques

- Sur Android 11 et plus, la suppression d'une musique demande une confirmation du système en plus de celle de l'application.
- Les fichiers de moins de 30 secondes, les sonneries, les notifications, les alarmes et les dossiers WhatsApp sont ignorés.
- Si une musique récente n'apparaît pas, appuyez sur le bouton d'actualisation, ou redémarrez le téléphone pour qu'Android l'indexe.
- Si un encadré orange « Installation incomplète » s'affiche, relancez `dart tool/setup.dart` puis réinstallez l'application.

## Licence

Ce projet est sous licence PolyForm Noncommercial 1.0.0.

Cela signifie que tu peux utiliser, modifier et redistribuer le code gratuitement pour un usage non commercial (usage personnel, éducatif, associatif, expérimentation). La vente ou l'exploitation commerciale du logiciel n'est pas autorisée sans l'accord explicite de l'auteur.
