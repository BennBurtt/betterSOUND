# betterSOUND

Petite app macOS pour voir et régler toutes les entrées et sorties son, et tout réinitialiser d'un clic.

## Fonctions

- Logo betterSOUND en icône et en haut de la fenêtre.
- Liste toutes les **sorties** (haut-parleurs, casques Bluetooth, HDMI, AirPlay, USB…) et **entrées** (micros).
- Pour chaque appareil : le choisir par défaut, régler le volume, couper ou réactiver le son.
- Mise à jour automatique quand un appareil est branché ou débranché.
- **Tout réinitialiser** (⌘R) : réactive le son partout, remet les volumes au niveau choisi (50 % en sortie et 75 % en entrée par défaut), centre la balance et, si l'option est cochée, remet les haut-parleurs et le micro intégrés par défaut.
- **Redémarrer le service audio** : relance `coreaudiod`. Utile quand le son grésille, se coupe ou disparaît. Le mot de passe administrateur est demandé.

## Installation

Il faut les outils de développement Apple (une seule fois) :

```bash
xcode-select --install
```

Ensuite, dans ce dossier :

```bash
chmod +x build.sh && ./build.sh
```

```bash
open betterSOUND.app
```

Vous pouvez glisser `betterSOUND.app` dans `/Applications`. Il faut macOS 13 Ventura ou plus récent.

> Au premier lancement, si macOS bloque l'app, faites un clic droit sur l'app puis **Ouvrir**.

## Remarque

Certains appareils (sorties HDMI, certaines cartes son USB) ne permettent pas de régler le volume depuis le Mac. L'app affiche alors « Volume non réglable par logiciel ».
