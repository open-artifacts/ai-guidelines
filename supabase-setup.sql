-- =============================================================
-- Diretrizes IA - Supabase Setup
-- Execute este script no SQL Editor do Supabase Dashboard
-- =============================================================

-- 1. Criar tabela de ratings
CREATE TABLE IF NOT EXISTS ratings (
    id INTEGER PRIMARY KEY,
    votes INTEGER NOT NULL DEFAULT 0,
    total_score INTEGER NOT NULL DEFAULT 0,
    average NUMERIC(4,2) NOT NULL DEFAULT 0.00
);

-- 2. Inserir dados iniciais (migrados do ratings.json atual)
INSERT INTO ratings (id, votes, total_score, average) VALUES
    (1,  7,  29,  4.14),
    (2,  4,  12,  3.00),
    (3,  1,  3,   3.00),
    (4,  1,  4,   4.00),
    (5,  1,  2,   2.00),
    (6,  3,  10,  3.33),
    (7,  2,  6,   3.00),
    (8,  3,  10,  3.33),
    (9,  2,  6,   3.00),
    (10, 2,  6,   3.00),
    (11, 4,  14,  3.50),
    (12, 30, 146, 4.87),
    (13, 8,  12,  1.50),
    (14, 9,  22,  2.44),
    (15, 2,  6,   3.00),
    (16, 4,  14,  3.50),
    (17, 5,  16,  3.20)
ON CONFLICT (id) DO NOTHING;

-- 3. Habilitar RLS (Row Level Security)
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

-- Permitir leitura pública (anon)
CREATE POLICY "ratings_select_policy" ON ratings
    FOR SELECT TO anon USING (true);

-- 4. Função RPC para submeter voto de forma atômica
--    Evita race conditions (equivalente ao lock do server.js)
CREATE OR REPLACE FUNCTION submit_rating(rating_id INTEGER, score INTEGER)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    -- Validar score
    IF score < 1 OR score > 5 THEN
        RAISE EXCEPTION 'Score deve ser entre 1 e 5';
    END IF;

    -- Atualizar atomicamente
    UPDATE ratings r
    SET votes       = r.votes + 1,
        total_score = r.total_score + score,
        average     = ROUND((r.total_score + score)::NUMERIC / (r.votes + 1), 2)
    WHERE r.id = rating_id;

    -- Retornar o registro atualizado
    SELECT row_to_json(t) INTO result
    FROM (SELECT r.id, r.votes, r.total_score AS "totalScore", r.average
          FROM ratings r WHERE r.id = rating_id) t;

    IF result IS NULL THEN
        RAISE EXCEPTION 'Rating ID % não encontrado', rating_id;
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
