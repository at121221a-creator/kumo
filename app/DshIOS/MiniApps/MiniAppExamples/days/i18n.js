// The phone's language: the app's own text follows it.
const language = (() => {
  const tag = (navigator.language || 'en').toLowerCase();
  if (tag.startsWith('zh')) return /hant|tw|hk|mo/.test(tag) ? 'zh-Hant' : 'zh-Hans';
  return ['ja', 'ko', 'es'].find((code) => tag.startsWith(code)) || 'en';
})();

const strings = {
  'zh-Hans': {
    future: '还有', past: '已经', today: '就是今天', unit: '天',
    rel: (n, future) => (future ? '天后' : '天前'), todayShort: '今天', yearly: '每年',
    add: '添加日子', newTitle: '新的日子', editTitle: '编辑日子',
    name: '名称', namePlaceholder: '比如：妈妈生日', date: '日期',
    repeat: '每年重复', repeatHint: '生日、纪念日会一直算到下一次',
    pin: '放在最上面', icon: '图标', color: '颜色',
    save: '保存', cancel: '取消', remove: '删除这个日子',
    empty: '还没有日子。添加一个生日、旅行或纪念日。',
    seedNewYear: '新年', seedSpring: '春分', seedStart: '装上倒数日',
  },
  'zh-Hant': {
    future: '還有', past: '已經', today: '就是今天', unit: '天',
    rel: (n, future) => (future ? '天後' : '天前'), todayShort: '今天', yearly: '每年',
    add: '新增日子', newTitle: '新的日子', editTitle: '編輯日子',
    name: '名稱', namePlaceholder: '例如：媽媽生日', date: '日期',
    repeat: '每年重複', repeatHint: '生日、紀念日會一直算到下一次',
    pin: '放在最上面', icon: '圖示', color: '顏色',
    save: '儲存', cancel: '取消', remove: '刪除這個日子',
    empty: '還沒有日子。新增一個生日、旅行或紀念日。',
    seedNewYear: '新年', seedSpring: '春分', seedStart: '裝上倒數日',
  },
  en: {
    future: 'In', past: 'It’s been', today: 'It’s today', unit: 'days', unitOne: 'day',
    rel: (n, future) => `${n === 1 ? 'day' : 'days'} ${future ? 'to go' : 'ago'}`, todayShort: 'Today', yearly: 'Yearly',
    add: 'Add a Date', newTitle: 'New Date', editTitle: 'Edit Date',
    name: 'Name', namePlaceholder: 'e.g. Mom’s birthday', date: 'Date',
    repeat: 'Repeats every year', repeatHint: 'Birthdays and anniversaries count to the next one',
    pin: 'Show at the top', icon: 'Icon', color: 'Color',
    save: 'Save', cancel: 'Cancel', remove: 'Delete This Date',
    empty: 'No dates yet. Add a birthday, a trip or an anniversary.',
    seedNewYear: 'New Year', seedSpring: 'First day of spring', seedStart: 'Started counting',
  },
  ja: {
    future: 'あと', past: 'これまで', today: '今日です', unit: '日',
    rel: (n, future) => (future ? '日後' : '日前'), todayShort: '今日', yearly: '毎年',
    add: '日付を追加', newTitle: '新しい日付', editTitle: '日付を編集',
    name: '名前', namePlaceholder: '例：母の誕生日', date: '日付',
    repeat: '毎年くり返す', repeatHint: '誕生日や記念日は次の回まで数えます',
    pin: 'いちばん上に表示', icon: 'アイコン', color: 'カラー',
    save: '保存', cancel: 'キャンセル', remove: 'この日付を削除',
    empty: 'まだ日付がありません。誕生日や旅行、記念日を追加しましょう。',
    seedNewYear: 'お正月', seedSpring: '春分の日', seedStart: 'カウントダウンを始めた日',
  },
  ko: {
    future: '앞으로', past: '벌써', today: '바로 오늘', unit: '일',
    rel: (n, future) => (future ? '일 후' : '일 전'), todayShort: '오늘', yearly: '매년',
    add: '날짜 추가', newTitle: '새 날짜', editTitle: '날짜 편집',
    name: '이름', namePlaceholder: '예: 엄마 생신', date: '날짜',
    repeat: '매년 반복', repeatHint: '생일과 기념일은 다음 날까지 계속 세요',
    pin: '맨 위에 표시', icon: '아이콘', color: '색상',
    save: '저장', cancel: '취소', remove: '이 날짜 삭제',
    empty: '아직 날짜가 없어요. 생일, 여행, 기념일을 추가해 보세요.',
    seedNewYear: '새해', seedSpring: '춘분', seedStart: '디데이를 시작한 날',
  },
  es: {
    future: 'Faltan', past: 'Han pasado', today: 'Es hoy', unit: 'días', unitOne: 'día',
    rel: (n, future) => `${n === 1 ? 'día' : 'días'}${future ? '' : ' atrás'}`, todayShort: 'Hoy', yearly: 'Cada año',
    add: 'Añadir fecha', newTitle: 'Nueva fecha', editTitle: 'Editar fecha',
    name: 'Nombre', namePlaceholder: 'p. ej. Cumpleaños de mamá', date: 'Fecha',
    repeat: 'Se repite cada año', repeatHint: 'Cumpleaños y aniversarios cuentan hasta el siguiente',
    pin: 'Mostrar arriba', icon: 'Icono', color: 'Color',
    save: 'Guardar', cancel: 'Cancelar', remove: 'Eliminar esta fecha',
    empty: 'Aún no hay fechas. Añade un cumpleaños, un viaje o un aniversario.',
    seedNewYear: 'Año Nuevo', seedSpring: 'Primer día de primavera', seedStart: 'Empecé a contar',
  },
};

export const t = strings[language];
export const locale = language;

/// "12 days" / "1 day" where the language counts that way.
export function unit(count) {
  return count === 1 && t.unitOne ? t.unitOne : t.unit;
}
