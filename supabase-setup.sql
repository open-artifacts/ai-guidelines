-- =============================================================
-- Diretrizes IA - Supabase Setup (v2 - Modelo Normalizado)
-- Execute este script no SQL Editor do Supabase Dashboard
--
-- ATENÇÃO: Se você já rodou a v1, execute primeiro:
--   DROP FUNCTION IF EXISTS submit_rating(INTEGER, INTEGER);
--   DROP POLICY IF EXISTS "ratings_select_policy" ON ratings;
--   DROP TABLE IF EXISTS ratings;
-- =============================================================

-- 1. Tabela de votos individuais
CREATE TABLE IF NOT EXISTS votes (
    rating_id  INTEGER NOT NULL,
    voter_id   UUID    NOT NULL,
    score      INTEGER NOT NULL CHECK (score >= 1 AND score <= 5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (rating_id, voter_id)
);

-- Índice para buscar votos de um voter_id rapidamente
CREATE INDEX IF NOT EXISTS idx_votes_voter ON votes (voter_id);

-- 2. View de agregação (substitui a tabela ratings)
CREATE OR REPLACE VIEW ratings_summary AS
SELECT
    rating_id,
    COUNT(*)::INTEGER           AS votes,
    ROUND(AVG(score), 2)        AS average
FROM votes
GROUP BY rating_id;

-- 3. RLS (Row Level Security)
ALTER TABLE votes ENABLE ROW LEVEL SECURITY;

-- Leitura pública
CREATE POLICY "votes_select_policy" ON votes
    FOR SELECT TO anon USING (true);

-- 4. Função RPC: submeter ou atualizar voto (UPSERT atômico)
CREATE OR REPLACE FUNCTION submit_vote(
    p_rating_id INTEGER,
    p_voter_id  UUID,
    p_score     INTEGER
)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    IF p_score < 1 OR p_score > 5 THEN
        RAISE EXCEPTION 'Score deve ser entre 1 e 5';
    END IF;

    INSERT INTO votes (rating_id, voter_id, score, updated_at)
    VALUES (p_rating_id, p_voter_id, p_score, now())
    ON CONFLICT (rating_id, voter_id)
    DO UPDATE SET score = p_score, updated_at = now();

    SELECT row_to_json(t) INTO result
    FROM (
        SELECT
            rating_id   AS "ratingId",
            COUNT(*)    AS "votes",
            ROUND(AVG(score), 2) AS "average"
        FROM votes
        WHERE rating_id = p_rating_id
        GROUP BY rating_id
    ) t;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Função RPC: remover voto
CREATE OR REPLACE FUNCTION remove_vote(
    p_rating_id INTEGER,
    p_voter_id  UUID
)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    DELETE FROM votes
    WHERE rating_id = p_rating_id AND voter_id = p_voter_id;

    SELECT row_to_json(t) INTO result
    FROM (
        SELECT
            p_rating_id         AS "ratingId",
            COALESCE(COUNT(*), 0)    AS "votes",
            COALESCE(ROUND(AVG(score), 2), 0) AS "average"
        FROM votes
        WHERE rating_id = p_rating_id
    ) t;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Função RPC: buscar votos de um voter_id
CREATE OR REPLACE FUNCTION get_voter_votes(p_voter_id UUID)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_agg(row_to_json(t)) INTO result
    FROM (
        SELECT rating_id AS "ratingId", score
        FROM votes
        WHERE voter_id = p_voter_id
    ) t;

    RETURN COALESCE(result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
