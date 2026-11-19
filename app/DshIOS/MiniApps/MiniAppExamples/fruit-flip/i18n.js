// The phone's language: the game's own text follows it.
const language = (() => {
  const tag = (navigator.language || 'en').toLowerCase();
  if (tag.startsWith('zh')) return /hant|tw|hk|mo/.test(tag) ? 'zh-Hant' : 'zh-Hans';
  return ['ja', 'ko', 'es'].find((code) => tag.startsWith(code)) || 'en';
})();

const strings = {
  'zh-Hans': {
    levels: ['简单', '普通', '困难'], moves: '步数', time: '用时', best: '最佳',
    hint: '翻开两张，找出一样的水果', won: '全部配对！', newBest: '新纪录',
    again: '再来一局', restart: '重新开始', hidden: '还没翻开的牌', none: '还没有',
  },
  'zh-Hant': {
    levels: ['簡單', '普通', '困難'], moves: '步數', time: '用時', best: '最佳',
    hint: '翻開兩張，找出一樣的水果', won: '全部配對！', newBest: '新紀錄',
    again: '再來一局', restart: '重新開始', hidden: '還沒翻開的牌', none: '還沒有',
  },
  en: {
    levels: ['Easy', 'Normal', 'Hard'], moves: 'Moves', time: 'Time', best: 'Best',
    hint: 'Flip two cards to find matching fruit', won: 'All matched!', newBest: 'New best',
    again: 'Play Again', restart: 'Start Over', hidden: 'Face-down card', none: 'None yet',
  },
  ja: {
    levels: ['かんたん', 'ふつう', 'むずかしい'], moves: '手数', time: 'タイム', best: 'ベスト',
    hint: '2 枚めくって、同じフルーツを見つけよう', won: '全部そろった！', newBest: '自己ベスト',
    again: 'もう一度', restart: '最初から', hidden: '裏向きのカード', none: 'まだなし',
  },
  ko: {
    levels: ['쉬움', '보통', '어려움'], moves: '이동', time: '시간', best: '최고',
    hint: '두 장을 뒤집어 같은 과일을 찾아보세요', won: '모두 맞췄어요!', newBest: '최고 기록',
    again: '한 판 더', restart: '처음부터', hidden: '뒤집힌 카드', none: '아직 없음',
  },
  es: {
    levels: ['Fácil', 'Normal', 'Difícil'], moves: 'Movimientos', time: 'Tiempo', best: 'Mejor',
    hint: 'Da la vuelta a dos cartas para encontrar frutas iguales', won: '¡Todo emparejado!', newBest: 'Nuevo récord',
    again: 'Jugar otra vez', restart: 'Empezar de nuevo', hidden: 'Carta boca abajo', none: 'Aún no',
  },
};

export const t = strings[language];
