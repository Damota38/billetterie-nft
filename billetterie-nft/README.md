Billetterie événementielle basée sur NFT

Smart contract Solidity qui transforme chaque billet d'événement en NFT unique (ERC-721). Il garantit l'authenticité des billets, encadre leur revente et empêche leur double utilisation à l'entrée.

Projet final Blockchain & Smart Contracts – B3 EPSI (Projet 2 : billetterie basée sur NFT).

Le problème

La billetterie classique souffre de faux billets, de QR codes copiés et vendus plusieurs fois, d'un marché noir aux prix abusifs et d'intermédiaires coûteux. La blockchain apporte ce qui manque : des billets uniques impossibles à dupliquer, un historique public des transferts et des règles de revente inscrites directement dans le code.

Fonctionnalités

Création d'événements : nom, date, prix, nombre de places et plafond de revente.
Achat de billets : paiement en ETH, un NFT unique est créé pour l'acheteur, et l'organisateur est payé directement.
Revente encadrée : le prix de revente ne peut pas dépasser le plafond fixé par l'organisateur, qui perçoit 5 % de royalty sur chaque revente.
Contrôle à l'entrée : des contrôleurs désignés vérifient la validité d'un billet et le marquent comme utilisé, de façon irréversible.
Protections : paiement sécurisé contre la réentrance, contrôle des droits, vérification des montants, des dates et des places disponibles.

Stack technique

Solidity ^0.8.20
ERC-721 via la bibliothèque OpenZeppelin (ERC721, ReentrancyGuard)
Remix IDE pour le développement et les tests
Réseau de test : Remix VM, ou Sepolia (testnet Ethereum) en option

Structure du dépôt

billetterie-nft/
├── contracts/
│   └── Billetterie.sol
└── README.md

Démarrage rapide (Remix)

Aucune installation n'est nécessaire.

Ouvrir remix.ethereum.org.
Créer un fichier contracts/Billetterie.sol et y coller le code du contrat.
Dans l'onglet Solidity Compiler, choisir une version 0.8.20 ou plus récente et cliquer sur Compile. OpenZeppelin est téléchargé automatiquement.
Dans l'onglet Deploy & Run Transactions, choisir l'environnement Remix VM, laisser Value à 0, sélectionner Billetterie et cliquer sur Deploy.
Le contrat apparaît dans Deployed Contracts : déplier la flèche pour voir ses fonctions. Les boutons orange modifient la blockchain, les boutons bleus lisent des données.

Après toute modification du code, supprimer le contrat déployé (icône poubelle), recompiler, puis redéployer.

Déploiement sur Sepolia (optionnel)
Installer MetaMask, passer sur le réseau Sepolia et récupérer de l'ETH de test via un faucet.
Dans Remix, choisir l'environnement Injected Provider - MetaMask.
Cliquer sur Deploy et confirmer dans MetaMask.
Consulter le contrat sur l'explorateur Sepolia (Etherscan).

Fonctions principales

creerEvenement(nom, date, prix, placesMax, plafondRevente) : crée un événement. L'appelant en devient l'organisateur.
acheterBillet(idEvenement) : achète un billet au prix officiel (fonction payante).
mettreEnVente(idBillet, prix) : met son billet en vente, à un prix inférieur ou égal au plafond.
annulerVente(idBillet) : retire son billet de la vente.
acheterRevente(idBillet) : achète un billet mis en vente (fonction payante, 5 % de royalty pour l'organisateur).
ajouterControleur(idEvenement, adresse) : désigne un contrôleur (réservé à l'organisateur).
verifierBillet(idBillet, porteur) : vérifie qu'un billet est valide pour une personne (lecture seule).
validerEntree(idBillet, porteur) : marque le billet comme utilisé (réservé aux contrôleurs et à l'organisateur).

Les prix sont exprimés en wei (1 ETH = 10¹⁸ wei).

Scénarios de test

Dans Remix, la liste Account fournit plusieurs comptes de test : le compte 1 joue l'organisateur, les comptes 2 et 3 les acheteurs, le compte 4 le contrôleur. Le champ Value doit rester à 0, sauf pour les deux fonctions d'achat (pensez à le remettre à 0 après chaque achat).

Paramètres de l'événement de test pour creerEvenement (date du 1er janvier 2027, 0,1 ETH, 100 places, plafond de 0,15 ETH) :

"Concert Test",1798761600,100000000000000000,100,150000000000000000

Si cette date est dépassée au moment du test, utiliser un timestamp plus lointain.

Scénario 1 : cycle de vie d'un billet
Compte 1 : creerEvenement avec les paramètres ci-dessus.
Compte 2 : acheterBillet(0) avec 0,1 ETH. ownerOf(0) renvoie l'adresse du compte 2.
Compte 1 : ajouterControleur(0, <adresse du compte 4>).
verifierBillet(0, <adresse du compte 2>) renvoie true.
Compte 3 : validerEntree(0, <adresse du compte 2>) est refusé (« Controleur non autorise »).
Compte 4 : validerEntree(0, <adresse du compte 2>) réussit et utilise(0) passe à true.
Compte 4 : le même appel est de nouveau refusé (« Billet invalide ou deja utilise ») : la double entrée est bloquée.
Scénario 2 : revente encadrée
Compte 2 : acheterBillet(0) avec 0,1 ETH.
Compte 2 : mettreEnVente(0, 200000000000000000) (0,2 ETH) est refusé (« Prix superieur au plafond »).
Compte 2 : mettreEnVente(0, 150000000000000000) (0,15 ETH) réussit.
Compte 3 : acheterRevente(0) avec un mauvais montant est refusé (« Montant incorrect »).
Compte 3 : acheterRevente(0) avec 0,15 ETH réussit. Le billet appartient au compte 3.
Répartition : le vendeur reçoit 0,1425 ETH et l'organisateur 0,0075 ETH de royalty.
Scénario 3 : protections contre les erreurs et abus
creerEvenement avec une date dans le passé est refusé (« La date doit etre dans le futur »).
acheterBillet(5) sur un événement inexistant est refusé (« Evenement inexistant »).
acheterBillet avec un montant différent du prix est refusé (« Montant incorrect »).
Sur un événement d'une seule place, le deuxième achat est refusé (« Complet »).
Un billet déjà utilisé ne peut plus être mis en vente (« Billet deja utilise »).

Limites connues

Contournement de la revente : le plafond ne s'applique qu'aux reventes passées par ce contrat. Deux personnes peuvent se transférer un billet directement et s'échanger de l'argent hors du contrat.
Preuve de possession : à l'entrée, l'adresse du porteur est passée en paramètre, ce qui ne prouve pas que la personne contrôle ce wallet. Une application réelle ferait signer un défi (QR code dynamique) par le spectateur.
Date à l'entrée : la validation n'est pas restreinte au jour de l'événement, pour permettre les tests.
Annulation : il n'y a pas de remboursement si un événement est annulé.
Royalty : appliquée directement par le contrat (5 %), pas via le standard ERC-2981.
Prototype pédagogique : le contrat n'a pas été audité et n'est pas destiné à un usage en production.
