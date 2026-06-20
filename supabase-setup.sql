-- =============================================================
-- Diretrizes IA - Supabase Setup (v3 - Modelo Normalizado + Keep-Alive)
-- Execute este script no SQL Editor do Supabase Dashboard
--
-- ATENCAO: Se voce ja rodou a v1, execute primeiro:
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

-- Indice para buscar votos de um voter_id rapidamente
CREATE INDEX IF NOT EXISTS idx_votes_voter ON votes (voter_id);

-- 2. View de agregacao (substitui a tabela ratings)
CREATE OR REPLACE VIEW ratings_summary AS
SELECT
    rating_id,
    COUNT(*)::INTEGER           AS votes,
    ROUND(AVG(score), 2)        AS average
FROM votes
GROUP BY rating_id;

-- 3. RLS (Row Level Security)
ALTER TABLE votes ENABLE ROW LEVEL SECURITY;

-- Leitura publica
DROP POLICY IF EXISTS "votes_select_policy" ON votes;
CREATE POLICY "votes_select_policy" ON votes
    FOR SELECT TO anon USING (true);

-- 4. Funcao RPC: submeter ou atualizar voto (UPSERT atomico)
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

-- 5. Funcao RPC: remover voto
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

-- 6. Funcao RPC: buscar votos de um voter_id
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

-- =============================================================
-- 7. KEEP-ALIVE
-- O Supabase pausa projetos Free apos 7 dias sem atividade NO BANCO.
-- Visitas ao dashboard e respostas em cache nao contam: e preciso uma
-- query que realmente chegue ao Postgres. A estrategia aqui e uma
-- escrita periodica nesta tabela (ver .github/workflows/keepalive.yml).
--
-- A tabela guarda UMA unica linha (singleton), entao nao ha crescimento
-- de dados: cada ping apenas atualiza o timestamp e incrementa o contador.
-- =============================================================
CREATE TABLE IF NOT EXISTS heartbeat (
    id        INTEGER PRIMARY KEY DEFAULT 1,
    last_ping TIMESTAMPTZ NOT NULL DEFAULT now(),
    pings     BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT heartbeat_singleton CHECK (id = 1)
);

-- Sem policies: acesso direto a tabela fica bloqueado para o anon.
-- O unico caminho e a funcao keepalive() abaixo (SECURITY DEFINER).
ALTER TABLE heartbeat ENABLE ROW LEVEL SECURITY;

-- 8. Funcao RPC: keepalive
-- Faz um UPSERT (escrita real, impossivel de cachear) e devolve o status.
CREATE OR REPLACE FUNCTION keepalive()
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    INSERT INTO heartbeat (id, last_ping, pings)
    VALUES (1, now(), 1)
    ON CONFLICT (id) DO UPDATE
        SET last_ping = now(),
            pings     = heartbeat.pings + 1;

    SELECT row_to_json(t) INTO result
    FROM (
        SELECT last_ping AS "lastPing", pings
        FROM heartbeat
        WHERE id = 1
    ) t;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
