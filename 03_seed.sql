SET search_path = republica_galactique, public;

INSERT INTO planete (nom_planete, secteur_galactique, population, statut_politique) VALUES
('Kamino','Outer Rim', 1000000, 'loyaliste'),
('Coruscant','Core', 1000000000, 'capitale'),
('Naboo','Mid Rim', 50000000, 'loyaliste');

INSERT INTO base_republicaine (nom_base, id_planete, capacite_vaisseaux, niveau_securite) VALUES
('Base Echo', 2, 20, 8),
('Base Kamino', 1, 10, 9);

INSERT INTO usine_clonage (nom_usine, id_planete, capacite_production) VALUES
('Kamino Cloning Facility', 1, 1000);

INSERT INTO modele_genetique (nom_donneur, taux_reussite, caracteristiques) VALUES
('Jango Fett', 98.5, '{"height":"1.8m","strength":"high"}');

INSERT INTO clone (matricule, id_modele, id_usine, specialisation) VALUES
('CT-101', 1, 1, 'sniper'),
('CT-102', 1, 1, 'assault');

INSERT INTO unite_clone (nom_unite, effectif, type_unite, id_usine) VALUES
('501st Legion', 500, 'infantry', 1);

INSERT INTO vaisseau (nom_vaisseau, modele, id_base, id_planete_stationnement, id_unite) VALUES
('Venator-01','Venator',1,2,1);

INSERT INTO technicien (nom, prenom, email, specialite, id_base) VALUES
('Sky','Fixer','sky.fix@rep.gov','propulsion',1);

INSERT INTO jedi (nom, prenom, rang, planete_origine) VALUES
('Kenobi','Obi-Wan','master',2);

INSERT INTO mission (code_mission, type_mission, id_planete_cible, date_debut, date_fin, statut, objectif)
VALUES ('MIS-EX-001','escort',3, now(), now() + interval '2 days', 'planned','Escort the diplomatic envoy');

INSERT INTO mission_vaisseau (id_mission, id_vaisseau, ordre_de_depart)
VALUES (1,1,1);

-- Simule fin de mission pour déclencher le trigger
UPDATE mission SET statut = 'completed' WHERE id_mission = 1;
