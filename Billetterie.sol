// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Billetterie événementielle basée sur NFT (ERC-721)
/// @notice Chaque billet est un NFT unique. Le contrat gère la création d'événements,
///         l'achat, la revente encadrée (plafond + royalty) et le contrôle à l'entrée.
contract Billetterie is ERC721, ReentrancyGuard {
    // =====================================================================
    //                              DONNÉES
    // =====================================================================

    uint256 private _nextTokenId; // identifiant du prochain billet (0, 1, 2...)

    /// @dev Fiche d'un événement
    struct Evenement {
        string nom;
        uint256 date;            // date de l'événement (timestamp Unix)
        uint256 prix;            // prix d'un billet, en wei
        uint256 placesMax;
        uint256 placesVendues;
        uint256 plafondRevente;  // prix de revente maximum, en wei
        address organisateur;
    }

    uint256 public nombreEvenements;
    mapping(uint256 => Evenement) public evenements;      // idEvenement => événement
    mapping(uint256 => uint256) public evenementDuBillet; // idBillet => idEvenement

    // Revente
    uint256 public constant ROYALTY_POURCENT = 5; // 5 % du prix de revente pour l'organisateur
    mapping(uint256 => bool) public enVente;
    mapping(uint256 => uint256) public prixRevente;

    // Contrôle à l'entrée
    mapping(uint256 => bool) public utilise;                           // billet déjà scanné ?
    mapping(uint256 => mapping(address => bool)) public estControleur; // idEvenement => adresse => autorisé ?

    // =====================================================================
    //                             ÉVÉNEMENTS (logs)
    // =====================================================================

    event EvenementCree(uint256 indexed idEvenement, string nom, address indexed organisateur);
    event BilletAchete(uint256 indexed idBillet, uint256 indexed idEvenement, address indexed acheteur);
    event BilletMisEnVente(uint256 indexed idBillet, uint256 prix);
    event VenteAnnulee(uint256 indexed idBillet);
    event BilletRevendu(uint256 indexed idBillet, address indexed vendeur, address indexed acheteur, uint256 prix);
    event ControleurAjoute(uint256 indexed idEvenement, address indexed controleur);
    event BilletValide(uint256 indexed idBillet, address indexed controleur);

    constructor() ERC721("Billet Evenement", "TKT") {}

    // =====================================================================
    //                        1. CRÉATION D'UN ÉVÉNEMENT
    // =====================================================================

    /// @notice L'organisateur (celui qui appelle) crée un événement
    function creerEvenement(
        string memory nom,
        uint256 date,
        uint256 prix,
        uint256 placesMax,
        uint256 plafondRevente
    ) external returns (uint256) {
        require(bytes(nom).length > 0, "Nom requis");
        require(date > block.timestamp, "La date doit etre dans le futur");
        require(placesMax > 0, "Au moins 1 place");
        require(plafondRevente >= prix, "Plafond inferieur au prix initial");

        uint256 id = nombreEvenements;
        evenements[id] = Evenement(nom, date, prix, placesMax, 0, plafondRevente, msg.sender);
        nombreEvenements++;

        emit EvenementCree(id, nom, msg.sender);
        return id;
    }

    // =====================================================================
    //                        2. ACHAT D'UN BILLET
    // =====================================================================

    /// @notice Achat d'un billet au prix officiel : un NFT est créé pour l'acheteur
    function acheterBillet(uint256 idEvenement) external payable nonReentrant returns (uint256) {
        require(idEvenement < nombreEvenements, "Evenement inexistant");
        Evenement storage ev = evenements[idEvenement];

        require(block.timestamp < ev.date, "Evenement deja passe");
        require(ev.placesVendues < ev.placesMax, "Complet");
        require(msg.value == ev.prix, "Montant incorrect");

        // 1. On met d'abord à jour l'état du contrat
        ev.placesVendues++;
        uint256 idBillet = _nextTokenId;
        _nextTokenId++;
        evenementDuBillet[idBillet] = idEvenement;

        // 2. Ensuite seulement : création du NFT et paiement de l'organisateur
        _safeMint(msg.sender, idBillet);
        (bool ok, ) = payable(ev.organisateur).call{value: msg.value}("");
        require(ok, "Paiement echoue");

        emit BilletAchete(idBillet, idEvenement, msg.sender);
        return idBillet;
    }

    // =====================================================================
    //                    3. REVENTE ENCADRÉE (plafond + royalty)
    // =====================================================================

    /// @notice Le propriétaire met son billet en vente, dans la limite du plafond
    function mettreEnVente(uint256 idBillet, uint256 prix) external {
        require(ownerOf(idBillet) == msg.sender, "Pas votre billet");
        require(!utilise[idBillet], "Billet deja utilise");
        Evenement storage ev = evenements[evenementDuBillet[idBillet]];
        require(block.timestamp < ev.date, "Evenement deja passe");
        require(prix > 0 && prix <= ev.plafondRevente, "Prix superieur au plafond");

        enVente[idBillet] = true;
        prixRevente[idBillet] = prix;
        emit BilletMisEnVente(idBillet, prix);
    }

    /// @notice Le propriétaire retire son billet de la vente
    function annulerVente(uint256 idBillet) external {
        require(ownerOf(idBillet) == msg.sender, "Pas votre billet");
        require(enVente[idBillet], "Pas en vente");

        enVente[idBillet] = false;
        prixRevente[idBillet] = 0;
        emit VenteAnnulee(idBillet);
    }

    /// @notice Un autre utilisateur achète un billet mis en vente
    function acheterRevente(uint256 idBillet) external payable nonReentrant {
        require(enVente[idBillet], "Billet pas en vente");
        require(!utilise[idBillet], "Billet deja utilise");
        address vendeur = ownerOf(idBillet);
        require(vendeur != msg.sender, "Vous etes deja proprietaire");

        uint256 prix = prixRevente[idBillet];
        require(msg.value == prix, "Montant incorrect");

        Evenement storage ev = evenements[evenementDuBillet[idBillet]];
        require(block.timestamp < ev.date, "Evenement deja passe");

        // 1. Transfert du NFT (remet aussi la mise en vente à zéro, voir _update plus bas)
        _transfer(vendeur, msg.sender, idBillet);

        // 2. Répartition du paiement : royalty pour l'organisateur, le reste au vendeur
        uint256 royalty = (prix * ROYALTY_POURCENT) / 100;
        (bool ok1, ) = payable(ev.organisateur).call{value: royalty}("");
        require(ok1, "Paiement royalty echoue");
        (bool ok2, ) = payable(vendeur).call{value: prix - royalty}("");
        require(ok2, "Paiement vendeur echoue");

        emit BilletRevendu(idBillet, vendeur, msg.sender, prix);
    }

    /// @dev Sécurité : dès que le billet change de main, son éventuelle mise en vente est annulée
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        enVente[tokenId] = false;
        prixRevente[tokenId] = 0;
        return super._update(to, tokenId, auth);
    }

    // =====================================================================
    //                      4. CONTRÔLE À L'ENTRÉE
    // =====================================================================

    /// @notice L'organisateur désigne les contrôleurs de son événement
    function ajouterControleur(uint256 idEvenement, address controleur) external {
        require(idEvenement < nombreEvenements, "Evenement inexistant");
        require(evenements[idEvenement].organisateur == msg.sender, "Reserve a l'organisateur");

        estControleur[idEvenement][controleur] = true;
        emit ControleurAjoute(idEvenement, controleur);
    }

    /// @notice Lecture seule : ce billet est-il valide pour cette personne ?
    function verifierBillet(uint256 idBillet, address porteur) public view returns (bool) {
        address proprietaire = _ownerOf(idBillet); // adresse 0 si le billet n'existe pas
        return proprietaire != address(0) && proprietaire == porteur && !utilise[idBillet];
    }

    /// @notice Le contrôleur valide l'entrée : le billet passe à "utilisé", de façon irréversible
    function validerEntree(uint256 idBillet, address porteur) external {
        uint256 idEvenement = evenementDuBillet[idBillet];
        require(
            estControleur[idEvenement][msg.sender] || evenements[idEvenement].organisateur == msg.sender,
            "Controleur non autorise"
        );
        require(verifierBillet(idBillet, porteur), "Billet invalide ou deja utilise");

        utilise[idBillet] = true;
        emit BilletValide(idBillet, msg.sender);
    }
}
