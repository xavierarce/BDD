SET search_path = republica_galactique, public;

--------------------------------------------------------
-- 1. Maintenance automatique à la fin d'une mission
--------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_after_mission_completed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_vaisseau RECORD;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.statut = 'completed' AND OLD.statut <> 'completed' THEN
        FOR v_vaisseau IN
            SELECT id_vaisseau FROM mission_vaisseau WHERE id_mission = NEW.id_mission
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM maintenance
                WHERE id_mission = NEW.id_mission AND id_vaisseau = v_vaisseau.id_vaisseau
            ) THEN
                INSERT INTO maintenance (id_vaisseau, id_mission, type_maintenance, cout_estime, date_debut, remarques)
                VALUES (v_vaisseau.id_vaisseau, NEW.id_mission, 'inspection', 0, now(),
                        'Maintenance automatique post-mission générée par trigger.');
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

--------------------------------------------------------
-- 2. Vérifier cohérence base technicien / vaisseau
--------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_check_technician_same_base()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_base_vaisseau BIGINT;
    v_base_tech BIGINT;
BEGIN
    IF NEW.id_technicien IS NULL THEN RETURN NEW; END IF;

    SELECT id_base INTO v_base_vaisseau FROM vaisseau WHERE id_vaisseau = NEW.id_vaisseau;
    SELECT id_base INTO v_base_tech FROM technicien WHERE id_technicien = NEW.id_technicien;

    IF v_base_vaisseau IS NULL OR v_base_tech IS NULL THEN
        RAISE EXCEPTION 'Base non renseignée pour le technicien ou le vaisseau.';
    END IF;

    IF v_base_vaisseau <> v_base_tech THEN
        RAISE EXCEPTION 'Le technicien (base=%) n’appartient pas à la même base que le vaisseau (base=%).', v_base_tech, v_base_vaisseau;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER maintenance_technician_base_check
BEFORE INSERT OR UPDATE ON maintenance
FOR EACH ROW
EXECUTE FUNCTION trg_check_technician_same_base();

--------------------------------------------------------
-- 3. Génération automatique du code mission
--------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_generate_code_mission()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF NEW.code_mission IS NULL OR length(trim(NEW.code_mission)) = 0 THEN
            NEW.code_mission := concat('MIS-', to_char(now(),'YYYYMMDD-HH24MI'), '-', nextval(pg_get_serial_sequence('mission','id_mission')));
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER mission_generate_code
BEFORE INSERT ON mission
FOR EACH ROW
EXECUTE FUNCTION trg_generate_code_mission();
