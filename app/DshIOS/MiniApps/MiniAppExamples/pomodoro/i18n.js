// The phone's language: the app's own text follows it.
const language = (() => {
  const tag = (navigator.language || 'en').toLowerCase();
  if (tag.startsWith('zh')) return /hant|tw|hk|mo/.test(tag) ? 'zh-Hant' : 'zh-Hans';
  return ['ja', 'ko', 'es'].find((code) => tag.startsWith(code)) || 'en';
})();

const strings = {
  'zh-Hans': {
    modes: { focus: '专注', short: '短休息', long: '长休息' },
    start: '开始', pause: '暂停', resume: '继续', reset: '重置', skip: '跳过',
    round: (n) => `第 ${n} 个番茄`, breakTime: '休息一下', today: '今天完成',
    count: (n) => `${n} 个`, done: { focus: '专注结束，休息一下', short: '休息结束，继续专注', long: '休息结束，继续专注' },
    lengths: '时长', minutes: '分钟', every: '长休息间隔', everyUnit: '个番茄',
    note: '离开这个页面计时会继续，但到点时不会通知你。',
  },
  'zh-Hant': {
    modes: { focus: '專注', short: '短休息', long: '長休息' },
    start: '開始', pause: '暫停', resume: '繼續', reset: '重設', skip: '略過',
    round: (n) => `第 ${n} 個番茄`, breakTime: '休息一下', today: '今天完成',
    count: (n) => `${n} 個`, done: { focus: '專注結束，休息一下', short: '休息結束，繼續專注', long: '休息結束，繼續專注' },
    lengths: '時長', minutes: '分鐘', every: '長休息間隔', everyUnit: '個番茄',
    note: '離開這個頁面計時會繼續，但時間到時不會通知你。',
  },
  en: {
    modes: { focus: 'Focus', short: 'Short Break', long: 'Long Break' },
    start: 'Start', pause: 'Pause', resume: 'Resume', reset: 'Reset', skip: 'Skip',
    round: (n) => `Session ${n}`, breakTime: 'Time for a break', today: 'Done today',
    count: (n) => `${n}`, done: { focus: 'Focus done. Take a break.', short: 'Break over. Back to focus.', long: 'Break over. Back to focus.' },
    lengths: 'Durations', minutes: 'min', every: 'Long break after', everyUnit: 'sessions',
    note: 'The timer keeps running when you leave, but it can’t notify you when time is up.',
  },
  ja: {
    modes: { focus: '集中', short: '小休憩', long: '長い休憩' },
    start: 'スタート', pause: '一時停止', resume: '再開', reset: 'リセット', skip: 'スキップ',
    round: (n) => `${n} ポモドーロ目`, breakTime: 'ひと休みしよう', today: '今日の完了',
    count: (n) => `${n} 個`, done: { focus: '集中おわり。ひと休みしよう', short: '休憩おわり。集中に戻ろう', long: '休憩おわり。集中に戻ろう' },
    lengths: '時間', minutes: '分', every: '長い休憩の間隔', everyUnit: 'ポモドーロ',
    note: 'このページを離れてもタイマーは進みますが、時間になっても通知はされません。',
  },
  ko: {
    modes: { focus: '집중', short: '짧은 휴식', long: '긴 휴식' },
    start: '시작', pause: '일시 정지', resume: '계속', reset: '초기화', skip: '건너뛰기',
    round: (n) => `${n}번째 뽀모도로`, breakTime: '잠깐 쉬어요', today: '오늘 완료',
    count: (n) => `${n}개`, done: { focus: '집중 끝! 잠깐 쉬어요', short: '휴식 끝! 다시 집중해요', long: '휴식 끝! 다시 집중해요' },
    lengths: '시간', minutes: '분', every: '긴 휴식 간격', everyUnit: '뽀모도로',
    note: '이 화면을 떠나도 타이머는 계속 가지만, 시간이 다 돼도 알림은 오지 않아요.',
  },
  es: {
    modes: { focus: 'Enfoque', short: 'Pausa corta', long: 'Pausa larga' },
    start: 'Empezar', pause: 'Pausar', resume: 'Seguir', reset: 'Reiniciar', skip: 'Saltar',
    round: (n) => `Pomodoro ${n}`, breakTime: 'Hora de descansar', today: 'Hechos hoy',
    count: (n) => `${n}`, done: { focus: 'Fin del enfoque. Toca descansar.', short: 'Fin de la pausa. A concentrarse.', long: 'Fin de la pausa. A concentrarse.' },
    lengths: 'Duración', minutes: 'min', every: 'Pausa larga cada', everyUnit: 'pomodoros',
    note: 'El temporizador sigue si sales, pero no puede avisarte cuando termine.',
  },
};

export const t = strings[language];
