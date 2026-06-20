'use strict';

// ============================================================
// Configuracao (definida em js/config.js)
// ============================================================
const { SUPABASE_URL, SUPABASE_ANON_KEY } = APP_CONFIG;

// ============================================================
// Internacionalizacao
// Todas as strings de UI ficam centralizadas aqui, em vez de
// espalhadas em ternarios ao longo do codigo.
// ============================================================
const STRINGS = {
  pt: {
    pageTitle: 'Diretrizes de IA',
    siteTitle: 'Diretrizes para o Uso de Inteligência Artificial Generativa no Ensino de Programação',
    searchPlaceholder: 'Pesquisar diretrizes...',
    loading: 'Carregando...',
    rate: 'Avalie esta diretriz',
    yourVote: 'Seu voto',
    votes: 'votos',
    vote: 'voto',
    principle: 'Princípio:',
    application: 'Aplicação:',
    noResults: 'Nenhuma diretriz encontrada.',
    loadError: 'Erro ao carregar dados. Verifique a configuração do Supabase.',
    voteRemoved: 'Voto removido',
    voteError: 'Erro ao registrar voto',
    voteRegistered: (score) => `Voto registrado: ${score}★`,
    voteUpdated: (score) => `Voto atualizado para ${score}★`,
    starLabel: (n) => `Dar nota ${n} de 5`,
    ratingGroupLabel: 'Avaliação de 1 a 5 estrelas',
  },
  en: {
    pageTitle: 'AI Guidelines',
    siteTitle: 'Guidelines for Using Generative Artificial Intelligence in Programming Education',
    searchPlaceholder: 'Search guidelines...',
    loading: 'Loading...',
    rate: 'Rate this guideline',
    yourVote: 'Your vote',
    votes: 'votes',
    vote: 'vote',
    principle: 'Principle:',
    application: 'Application:',
    noResults: 'No guidelines found.',
    loadError: 'Error loading data. Check the Supabase configuration.',
    voteRemoved: 'Vote removed',
    voteError: 'Error recording vote',
    voteRegistered: (score) => `Vote recorded: ${score}★`,
    voteUpdated: (score) => `Vote updated to ${score}★`,
    starLabel: (n) => `Give ${n} out of 5`,
    ratingGroupLabel: 'Rating from 1 to 5 stars',
  },
};

function t(key, ...args) {
  const value = STRINGS[currentLanguage][key];
  return typeof value === 'function' ? value(...args) : value;
}

// ============================================================
// Estado da aplicacao
// ============================================================
let currentLanguage = 'pt';
let diretrizesData = [];
let ratingsData = [];
let myVotes = {}; // { ratingId: score }

// ============================================================
// Funcoes utilitarias
// ============================================================

// Gera um UUID v4, com fallback para navegadores sem crypto.randomUUID.
function generateUUID() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) =>
    (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)
  );
}

// Escapa texto antes de interpolar em innerHTML (defesa contra HTML inesperado).
function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Normaliza texto para busca: minusculo, sem acentos e sem pontuacao.
function normalizeText(text) {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\w\s]/g, '')
    .trim();
}

// Pinta as estrelas de 1 ate `score` com a classe informada.
function paintStars(stars, score, className) {
  stars.forEach((star, index) => {
    star.classList.remove('filled', 'user-voted');
    if (index < score) {
      star.classList.add(className);
    }
  });
}

// ============================================================
// Identificacao anonima do votante
// ============================================================
function getVoterId() {
  const key = 'diretrizes_voter_id';
  let id = localStorage.getItem(key);
  if (!id) {
    id = generateUUID();
    localStorage.setItem(key, id);
  }
  return id;
}

const VOTER_ID = getVoterId();

// ============================================================
// Cliente REST minimo para Supabase (sem SDK)
// ============================================================
const supabase = {
  headers: {
    apikey: SUPABASE_ANON_KEY,
    Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },

  async rpc(name, body) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      throw new Error(`RPC ${name} falhou (HTTP ${res.status})`);
    }
    return res.json();
  },

  // Resumo agregado de todos os ratings (via view).
  async fetchRatings() {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/ratings_summary?select=rating_id,votes,average&order=rating_id`,
      { headers: this.headers }
    );
    if (!res.ok) throw new Error('Erro ao carregar ratings');
    const rows = await res.json();
    return rows.map((r) => ({
      id: r.rating_id,
      votes: r.votes,
      average: parseFloat(r.average),
    }));
  },

  // Votos do usuario atual, como mapa { ratingId: score }.
  async fetchMyVotes() {
    const votes = await this.rpc('get_voter_votes', { p_voter_id: VOTER_ID });
    const map = {};
    if (Array.isArray(votes)) {
      votes.forEach((v) => {
        map[v.ratingId] = v.score;
      });
    }
    return map;
  },

  // Submete ou atualiza voto (UPSERT atomico no banco).
  submitVote(ratingId, score) {
    return this.rpc('submit_vote', {
      p_rating_id: ratingId,
      p_voter_id: VOTER_ID,
      p_score: score,
    });
  },

  // Remove voto.
  removeVote(ratingId) {
    return this.rpc('remove_vote', {
      p_rating_id: ratingId,
      p_voter_id: VOTER_ID,
    });
  },
};

// ============================================================
// Toast de feedback
// ============================================================
let toastTimer = null;
function showToast(message) {
  const toast = document.getElementById('toast');
  toast.textContent = message;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 2200);
}

// ============================================================
// Carregamento de dados
// ============================================================
async function loadData() {
  try {
    const [diretrizesResponse, ratings, votes] = await Promise.all([
      fetch('diretrizes.json'),
      supabase.fetchRatings(),
      supabase.fetchMyVotes(),
    ]);

    const diretrizesJSON = await diretrizesResponse.json();
    diretrizesData = diretrizesJSON.diretrizes;
    ratingsData = ratings;
    myVotes = votes;

    renderCards();
  } catch (error) {
    console.error('Erro ao carregar dados:', error);
    document.getElementById('cardsContainer').innerHTML =
      `<div class="no-results">${t('loadError')}</div>`;
  }
}

// ============================================================
// Renderizacao dos cards
// ============================================================
function renderCards(searchTerm = '') {
  const container = document.getElementById('cardsContainer');
  container.innerHTML = '';

  const normalizedSearch = normalizeText(searchTerm);
  let hasResults = false;

  diretrizesData.forEach((diretriz) => {
    const langData = currentLanguage === 'pt' ? diretriz.pt : diretriz.en;
    const titulo = langData.titulo || langData.title || '';
    const principio = langData.principio || langData.principle || '';
    const aplicacao = langData.aplicacao || langData.application || '';

    const normalizedFullText = normalizeText(`${titulo} ${principio} ${aplicacao}`);
    if (normalizedSearch && !normalizedFullText.includes(normalizedSearch)) {
      return;
    }

    hasResults = true;
    container.appendChild(buildCard(diretriz, { titulo, principio, aplicacao }));
  });

  if (!hasResults) {
    container.innerHTML = `<div class="no-results">${t('noResults')}</div>`;
  }
}

// Monta um card completo (conteudo + widget de avaliacao).
function buildCard(diretriz, { titulo, principio, aplicacao }) {
  const rating = ratingsData.find((r) => r.id === diretriz.id);
  const average = rating ? rating.average.toFixed(1) : '0.0';
  const votes = rating ? rating.votes : 0;
  const communityScore = rating ? Math.round(rating.average) : 0;
  const userScore = myVotes[diretriz.id] || 0;
  const hasVoted = userScore > 0;

  const card = document.createElement('div');
  card.className = 'card';

  // Estrelas em repouso: voto do usuario (roxo) ou media da comunidade (amarelo).
  const displayScore = hasVoted ? userScore : communityScore;
  const restingClass = hasVoted ? 'user-voted' : 'filled';
  const focusStar = hasVoted ? userScore : 1;
  const labelId = `rating-label-${diretriz.id}`;

  const starsHTML = [1, 2, 3, 4, 5]
    .map(
      (star) => `
        <span class="star ${star <= displayScore ? restingClass : ''}"
              role="radio"
              data-star="${star}"
              tabindex="${star === focusStar ? '0' : '-1'}"
              aria-checked="${star === userScore ? 'true' : 'false'}"
              aria-label="${t('starLabel', star)}">★</span>`
    )
    .join('');

  let html = '<div class="card-content">';
  html += `<div class="card-title">${escapeHtml(titulo)}</div>`;
  html += `<div class="card-principle"><span class="principle-label">${t('principle')}</span> ${escapeHtml(principio)}</div>`;
  if (aplicacao) {
    html += `<div class="card-application"><span class="application-label">${t('application')}</span> ${escapeHtml(aplicacao)}</div>`;
  }
  html += '</div>';

  html += `
    <div class="rating-section">
      <span class="rating-label" id="${labelId}">${hasVoted ? t('yourVote') : t('rate')}</span>
      <div class="stars" role="radiogroup" aria-labelledby="${labelId}" aria-label="${t('ratingGroupLabel')}" data-id="${diretriz.id}">
        ${starsHTML}
      </div>
      <div class="rating-info">
        <span>
          <span class="average-score">${average}/5.0</span>
          <span> (${votes} ${votes === 1 ? t('vote') : t('votes')})</span>
        </span>
        <span class="user-vote-badge ${hasVoted ? 'visible' : ''}" data-badge="${diretriz.id}">
          ${hasVoted ? `${userScore}★` : ''}
        </span>
      </div>
    </div>
  `;

  card.innerHTML = html;
  wireRatingEvents(card, diretriz.id, communityScore);
  return card;
}

// Liga os eventos de mouse e teclado do widget de avaliacao.
function wireRatingEvents(card, diretrizId, communityScore) {
  const starsContainer = card.querySelector('.stars');
  const stars = Array.from(card.querySelectorAll('.star'));

  // Estado de repouso: voto do usuario ou media da comunidade.
  const restoreResting = () => {
    const userScore = myVotes[diretrizId] || 0;
    if (userScore > 0) {
      paintStars(stars, userScore, 'user-voted');
    } else {
      paintStars(stars, communityScore, 'filled');
    }
  };

  stars.forEach((star, index) => {
    const value = index + 1;

    star.addEventListener('click', () => handleVote(diretrizId, value));

    star.addEventListener('mouseover', () => paintStars(stars, value, 'user-voted'));
  });

  starsContainer.addEventListener('mouseleave', restoreResting);

  // Navegacao por teclado (setas, Home/End, Enter/Espaco).
  starsContainer.addEventListener('keydown', (event) => {
    const current = stars.findIndex((s) => s.getAttribute('tabindex') === '0');
    let next = current;

    switch (event.key) {
      case 'ArrowRight':
      case 'ArrowUp':
        next = Math.min(stars.length - 1, current + 1);
        break;
      case 'ArrowLeft':
      case 'ArrowDown':
        next = Math.max(0, current - 1);
        break;
      case 'Home':
        next = 0;
        break;
      case 'End':
        next = stars.length - 1;
        break;
      case 'Enter':
      case ' ':
        event.preventDefault();
        handleVote(diretrizId, current + 1);
        return;
      default:
        return;
    }

    event.preventDefault();
    stars[current].setAttribute('tabindex', '-1');
    stars[next].setAttribute('tabindex', '0');
    stars[next].focus();
    paintStars(stars, next + 1, 'user-voted');
  });

  // Ao sair do grupo com o teclado, volta ao estado de repouso.
  starsContainer.addEventListener('focusout', (event) => {
    if (!starsContainer.contains(event.relatedTarget)) {
      restoreResting();
    }
  });
}

// ============================================================
// Logica de votacao
// ============================================================
async function handleVote(diretrizId, score) {
  try {
    const currentVote = myVotes[diretrizId] || 0;

    if (currentVote === score) {
      // Clicou na mesma estrela: remove o voto (toggle).
      const result = await supabase.removeVote(diretrizId);
      delete myVotes[diretrizId];
      updateRatingsLocal(diretrizId, result);
      showToast(t('voteRemoved'));
    } else {
      // Novo voto ou alteracao.
      const result = await supabase.submitVote(diretrizId, score);
      myVotes[diretrizId] = score;
      updateRatingsLocal(diretrizId, result);
      showToast(currentVote > 0 ? t('voteUpdated', score) : t('voteRegistered', score));
    }

    // Animacao de pulso na estrela clicada.
    const starEl = document.querySelector(
      `.stars[data-id="${diretrizId}"] .star[data-star="${score}"]`
    );
    if (starEl) {
      starEl.classList.remove('pulse');
      void starEl.offsetWidth; // forca reflow para reiniciar a animacao
      starEl.classList.add('pulse');
    }

    renderCards(document.getElementById('searchInput').value);
  } catch (error) {
    console.error('Erro ao votar:', error);
    showToast(t('voteError'));
  }
}

function updateRatingsLocal(diretrizId, result) {
  if (!result) return;
  const updated = {
    id: result.ratingId || diretrizId,
    votes: result.votes,
    average: parseFloat(result.average),
  };
  const idx = ratingsData.findIndex((r) => r.id === diretrizId);
  if (idx !== -1) {
    ratingsData[idx] = updated;
  } else {
    ratingsData.push(updated);
  }
}

// ============================================================
// Idioma
// ============================================================
function detectSystemLanguage() {
  const browserLanguage = navigator.language || navigator.userLanguage || 'pt';
  return browserLanguage.startsWith('en') ? 'en' : 'pt';
}

function applyLanguage(lang) {
  currentLanguage = lang;

  document.getElementById('ptBtn').classList.toggle('active', lang === 'pt');
  document.getElementById('enBtn').classList.toggle('active', lang === 'en');
  document.documentElement.lang = lang === 'pt' ? 'pt-BR' : 'en-US';

  document.getElementById('pageTitle').textContent = t('pageTitle');
  document.getElementById('siteTitle').textContent = t('siteTitle');
  document.getElementById('searchInput').placeholder = t('searchPlaceholder');

  renderCards(document.getElementById('searchInput').value);
}

// ============================================================
// Inicializacao
// ============================================================
document.getElementById('ptBtn').addEventListener('click', () => applyLanguage('pt'));
document.getElementById('enBtn').addEventListener('click', () => applyLanguage('en'));
document.getElementById('searchInput').addEventListener('input', (e) => renderCards(e.target.value));

loadData();

window.addEventListener('load', () => {
  applyLanguage(detectSystemLanguage());
});
