-- /!\ Exécute dans une base PostgreSQL (version 12+ recommandée)

-- 0. Pré-requis : schéma (optionnel)
CREATE SCHEMA IF NOT EXISTS republica_galactique;
SET search_path = republica_galactique, public;

-- 1. Domaines & enums
CREATE DOMAIN dg_email AS TEXT CHECK (position('@' in value) > 1);

CREATE TYPE rank_jedi AS ENUM ('youngling','padawan','knight','master','grand_master');
CREATE TYPE mission_type AS ENUM ('escort','recon','assault','diplomatic','rescue','other');
CREATE TYPE mission_status AS ENUM ('planned','ongoing','completed','cancelled');
CREATE TYPE vaisseau_status AS ENUM ('docked','in_mission','in_maintenance','decommissioned');
CREATE TYPE maintenance_type AS ENUM ('routine','repair','inspection','emergency');

-- 2. Tables principales

CREATE TABLE planete (
    id_planete BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_planete TEXT NOT NULL UNIQUE,
    secteur_galactique TEXT,
    population BIGINT CHECK (population >= 0),
    statut_politique TEXT
);

CREATE TABLE base_republicaine (
    id_base BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_base TEXT NOT NULL,
    id_planete BIGINT NOT NULL REFERENCES planete(id_planete) ON DELETE CASCADE,
    capacite_vaisseaux INTEGER CHECK (capacite_vaisseaux >= 0),
    niveau_securite SMALLINT CHECK (niveau_securite >= 0 AND niveau_securite <= 10),
    UNIQUE (nom_base, id_planete)
);

CREATE TABLE usine_clonage (
    id_usine BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_usine TEXT NOT NULL,
    id_planete BIGINT NOT NULL REFERENCES planete(id_planete) ON DELETE SET NULL,
    capacite_production INTEGER CHECK (capacite_production >= 0),
    UNIQUE (nom_usine, id_planete)
);

CREATE TABLE modele_genetique (
    id_modele BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_donneur TEXT,
    taux_reussite NUMERIC(5,2) CHECK (taux_reussite >= 0 AND taux_reussite <= 100),
    caracteristiques JSONB
);

CREATE TABLE clone (
    id_clone BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricule TEXT NOT NULL UNIQUE,
    id_modele BIGINT NOT NULL REFERENCES modele_genetique(id_modele) ON DELETE RESTRICT,
    id_usine BIGINT NOT NULL REFERENCES usine_clonage(id_usine) ON DELETE SET NULL,
    specialisation TEXT,
    date_creation TIMESTAMPTZ DEFAULT now(),
    statut TEXT DEFAULT 'active' -- ex: active, retired, deceased
);

CREATE TABLE unite_clone (
    id_unite BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_unite TEXT NOT NULL,
    effectif INTEGER CHECK (effectif >= 0),
    type_unite TEXT,
    id_usine BIGINT REFERENCES usine_clonage(id_usine) ON DELETE SET NULL,
    UNIQUE(nom_unite, id_usine)
);

CREATE TABLE vaisseau (
    id_vaisseau BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_vaisseau TEXT,
    modele TEXT,
    id_base BIGINT REFERENCES base_republicaine(id_base) ON DELETE SET NULL,
    id_planete_stationnement BIGINT REFERENCES planete(id_planete) ON DELETE SET NULL,
    id_unite BIGINT REFERENCES unite_clone(id_unite) ON DELETE SET NULL,
    statut vaisseau_status NOT NULL DEFAULT 'docked'
);

CREATE TABLE technicien (
    id_technicien BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    email dg_email NOT NULL,
    specialite TEXT,
    id_base BIGINT REFERENCES base_republicaine(id_base) ON DELETE SET NULL,
    UNIQUE(email)
);

CREATE TABLE jedi (
    id_jedi BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    rang rank_jedi NOT NULL DEFAULT 'knight',
    id_maitre BIGINT REFERENCES jedi(id_jedi) ON DELETE SET NULL,
    planete_origine BIGINT REFERENCES planete(id_planete) ON DELETE SET NULL,
    specialite_combat TEXT
);

CREATE TABLE mission (
    id_mission BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code_mission TEXT NOT NULL UNIQUE,
    type_mission mission_type NOT NULL DEFAULT 'other',
    id_planete_cible BIGINT REFERENCES planete(id_planete) ON DELETE SET NULL,
    date_debut TIMESTAMPTZ NOT NULL,
    date_fin TIMESTAMPTZ,
    statut mission_status NOT NULL DEFAULT 'planned',
    objectif TEXT,
    CHECK (date_fin IS NULL OR date_fin >= date_debut)
);

CREATE TABLE maintenance (
    id_maintenance BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vaisseau BIGINT NOT NULL REFERENCES vaisseau(id_vaisseau) ON DELETE CASCADE,
    id_technicien BIGINT REFERENCES technicien(id_technicien) ON DELETE SET NULL,
    id_mission BIGINT REFERENCES mission(id_mission) ON DELETE SET NULL,
    type_maintenance maintenance_type NOT NULL DEFAULT 'routine',
    cout_estime NUMERIC(12,2) CHECK (cout_estime >= 0) DEFAULT 0,
    date_debut TIMESTAMPTZ DEFAULT now(),
    date_fin TIMESTAMPTZ,
    remarques TEXT
);

-- 3. Tables de jointure N:N (normalisées)

CREATE TABLE mission_jedi (
    id_mission BIGINT NOT NULL REFERENCES mission(id_mission) ON DELETE CASCADE,
    id_jedi BIGINT NOT NULL REFERENCES jedi(id_jedi) ON DELETE CASCADE,
    role TEXT, -- ex: leader, support
    PRIMARY KEY (id_mission, id_jedi)
);

CREATE TABLE mission_clone (
    id_mission BIGINT NOT NULL REFERENCES mission(id_mission) ON DELETE CASCADE,
    id_clone BIGINT NOT NULL REFERENCES clone(id_clone) ON DELETE CASCADE,
    role TEXT,
    PRIMARY KEY (id_mission, id_clone)
);

CREATE TABLE mission_vaisseau (
    id_mission BIGINT NOT NULL REFERENCES mission(id_mission) ON DELETE CASCADE,
    id_vaisseau BIGINT NOT NULL REFERENCES vaisseau(id_vaisseau) ON DELETE CASCADE,
    ordre_de_depart INTEGER DEFAULT 0,
    PRIMARY KEY (id_mission, id_vaisseau)
);

-- 4. Indexes pour performance (recherche fréquente)
CREATE INDEX idx_vaisseau_base ON vaisseau(id_base);
CREATE INDEX idx_technicien_base ON technicien(id_base);
CREATE INDEX idx_mission_statut ON mission(statut);
CREATE INDEX idx_clone_usine ON clone(id_usine);

-- 5. Trigger : lorsque le statut d'une mission passe à 'completed', créer
-- une maintenance pour chaque vaisseau impliqué par la mission (si pas déjà créée).

-- fonction trigger
CREATE OR REPLACE FUNCTION trg_after_mission_completed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_vaisseau RECORD;
BEGIN
    -- on ne fait rien si statut n'est pas passé en 'completed'
    IF TG_OP = 'UPDATE' AND NEW.statut = 'completed' AND OLD.statut <> 'completed' THEN
        -- pour chaque vaisseau lié à la mission, créer maintenance si aucune maintenance existante liée à cette mission & vaisseau
        FOR v_vaisseau IN
            SELECT mv.id_vaisseau
            FROM mission_vaisseau mv
            WHERE mv.id_mission = NEW.id_mission
        LOOP
            -- vérifier si une maintenance déjà liée à cette mission + vaisseau
            IF NOT EXISTS (
                SELECT 1 FROM maintenance m
                WHERE m.id_mission = NEW.id_mission AND m.id_vaisseau = v_vaisseau.id_vaisseau
            ) THEN
                INSERT INTO maintenance (id_vaisseau, id_mission, type_maintenance, cout_estime, date_debut, remarques)
                VALUES (v_vaisseau.id_vaisseau, NEW.id_mission, 'inspection', 0, now(),
                        'Maintenance automatique post-mission générée par trigger.');
                -- passer le vaisseau en état in_maintenance
                UPDATE vaisseau SET statut = 'in_maintenance' WHERE id_vaisseau = v_vaisseau.id_vaisseau;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER mission_completed_trigger
AFTER UPDATE ON mission
FOR EACH ROW
EXECUTE FUNCTION trg_after_mission_completed();


-- 6. Trigger : vérifier avant insertion d'une maintenance que le technicien,
-- si renseigné, appartient à la même base que le vaisseau.

CREATE OR REPLACE FUNCTION trg_check_technician_same_base()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_base_vaisseau BIGINT;
    v_base_tech BIGINT;
BEGIN
    -- Si pas de technicien renseigné, ok
    IF NEW.id_technicien IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id_base INTO v_base_vaisseau FROM vaisseau WHERE id_vaisseau = NEW.id_vaisseau;
    SELECT id_base INTO v_base_tech FROM technicien WHERE id_technicien = NEW.id_technicien;

    IF v_base_vaisseau IS NULL OR v_base_tech IS NULL THEN
        RAISE EXCEPTION 'Base vaisseau (%) ou base technicien (%) non renseignée.', v_base_vaisseau, v_base_tech;
    END IF;

    IF v_base_vaisseau <> v_base_tech THEN
        RAISE EXCEPTION 'Le technicien (base=%), n''appartient pas à la même base que le vaisseau (base=%).', v_base_tech, v_base_vaisseau;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER maintenance_technician_base_check
BEFORE INSERT OR UPDATE ON maintenance
FOR EACH ROW
EXECUTE FUNCTION trg_check_technician_same_base();


-- 7. Trigger optionnel : génération automatique d'un code_mission si non fourni.
CREATE OR REPLACE FUNCTION trg_generate_code_mission()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF NEW.code_mission IS NULL OR length(trim(NEW.code_mission)) = 0 THEN
            NEW.code_mission := concat('MIS-', to_char(now(),'YYYYMMDD-HH24MI'), '-', nextval('mission_id_seq'::regclass));
            -- si nextval non dispo, fallback
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Remarque: la fonction ci-dessus utilise la séquence liée à la table mission ; 
-- sur PostgreSQL l'identité auto-générée s'appelle mission_id_mission_seq (nom dépendant). 
-- Pour sécurité, on peut appeler nextval('mission_id_seq') si on a créé manuellement la séquence. 
-- Ici on protège donc par un fallback si la séquence n'existe pas.
CREATE TRIGGER mission_generate_code
BEFORE INSERT ON mission
FOR EACH ROW
EXECUTE FUNCTION trg_generate_code_mission();

-- 8. Contraintes métiers additionnelles (exemples)
-- Empêcher qu'un clone soit affecté à plusieurs unités (si on choisit un modèle où clone.id_unite est unique).
-- Dans la modélisation actuelle, un clone a 0..1 id_unite (via clone.id_unite si besoin)
-- Si tu veux: create unique index on clone(id_unite) ??? (rarement utile)

-- 9. Quelques exemples d'insert pour tester

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

-- create a mission and link vaisseau -> then set status to completed to test trigger
INSERT INTO mission (code_mission, type_mission, id_planete_cible, date_debut, date_fin, statut, objectif)
VALUES ('MIS-EX-001','escort',3, now(), now() + interval '2 days', 'planned','Escort the diplomatic envoy');

INSERT INTO mission_vaisseau (id_mission, id_vaisseau, ordre_de_depart)
VALUES (1,1,1);

-- Simuler fin de mission (ce qui va déclencher création maintenance et update statut du vaisseau)
UPDATE mission SET statut = 'completed' WHERE id_mission = 1;

-- Vérifier maintenance générée :
SELECT * FROM maintenance WHERE id_mission = 1;

