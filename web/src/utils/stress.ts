export interface StressScore {
  score: number;
  label: string;
  color: string;
}

export function calculateStressScore(hrv: number): StressScore {
  if (hrv <= 0) return { score: -1, label: '未入力', color: '#AFAFAF' };
  let score = 0;
  if (hrv >= 100) score = 5;
  else if (hrv >= 80) score = Math.round(5 + ((100 - hrv) / 20) * 10);
  else if (hrv >= 60) score = Math.round(15 + ((80 - hrv) / 20) * 20);
  else if (hrv >= 40) score = Math.round(35 + ((60 - hrv) / 20) * 25);
  else if (hrv >= 20) score = Math.round(60 + ((40 - hrv) / 20) * 20);
  else score = Math.round(Math.min(95, 80 + ((20 - hrv) / 20) * 15));

  if (score < 30) return { score, label: '低い', color: '#58CC02' };
  if (score < 55) return { score, label: '普通', color: '#78C800' };
  if (score < 75) return { score, label: 'やや高', color: '#FF9600' };
  return { score, label: '高い', color: '#FF4B4B' };
}
