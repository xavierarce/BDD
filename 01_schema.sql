-- /!\ PostgreSQL 12+ requis
-- 01_schema.sql : Définitions des types, tables, contraintes, et index

CREATE SCHEMA IF NOT EXISTS republica_galactique;
SET search_path = republica_galactique, public;

--------------------------------------------------------
-- 1. DOMAINES ET ENUMS
--------------------------------------------------------
CREATE DOMAIN dg_email AS TEXT CHECK (position('@' in value) > 1);

CREATE TYPE rank_jedi AS ENUM ('youngling','padawan','knight','master','grand_master');
CREATE TYPE mission_type AS ENUM ('escort','recon','assault','diplomatic','rescue','other');
CREATE TYPE mission_status AS ENUM ('planned','ongoing','completed','cancelled');
CREATE TYPE vaisseau_status AS ENUM ('docked','in_mission','in_maintenance','decommissioned');
CREATE TYPE maintenance_type AS ENUM ('routine','repair','inspection','emergency');

--------------------------------------------------------
-- 2. TABLES PRINCIPALES
--------------------------------------------------------

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
    niveau_securite SMALLINT CHECK (niveau_securite BETWEEN 0 AND 10),
    UNIQUE (nom_base, id_planete)
);

CREATE TABLE usine_clonage (
    id_usine BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_usine TEXT NOT NULL,
    id_planete BIGINT REFERENCES planete(id_planete) ON DELETE SET NULL,
    capacite_production INTEGER CHECK (capacite_production >= 0),
    UNIQUE (nom_usine, id_planete)
);

CREATE TABLE modele_genetique (
    id_modele BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_donneur TEXT,
    taux_reussite NUMERIC(5,2) CHECK (taux_reussite BETWEEN 0 AND 100),
    caracteristiques JSONB
);

CREATE TABLE clone (
    id_clone BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricule TEXT NOT NULL UNIQUE,
    id_modele BIGINT NOT NULL REFERENCES modele_genetique(id_modele) ON DELETE RESTRICT,
    id_usine BIGINT REFERENCES usine_clonage(id_usine) ON DELETE SET NULL,
    specialisation TEXT,
    date_creation TIMESTAMPTZ DEFAULT now(),
    statut TEXT DEFAULT 'active'
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
    email dg_email NOT NULL UNIQUE,
    specialite TEXT,
    id_base BIGINT REFERENCES base_republicaine(id_base) ON DELETE SET NULL
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

--------------------------------------------------------
-- 3. TABLES DE RELATION N:N
--------------------------------------------------------

CREATE TABLE mission_jedi (
    id_mission BIGINT NOT NULL REFERENCES mission(id_mission) ON DELETE CASCADE,
    id_jedi BIGINT NOT NULL REFERENCES jedi(id_jedi) ON DELETE CASCADE,
    role TEXT,
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

--------------------------------------------------------
-- 4. INDEXES POUR PERFORMANCE
--------------------------------------------------------
CREATE INDEX idx_vaisseau_base ON vaisseau(id_base);
CREATE INDEX idx_technicien_base ON technicien(id_base);
CREATE INDEX idx_mission_statut ON mission(statut);
CREATE INDEX idx_clone_usine ON clone(id_usine);
