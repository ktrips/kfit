import { useEffect } from 'react';

/**
 * トレーニング動画の末尾に焼き込まれたブランドカット（静止ポーズ＋ロゴ演出、
 * 約1秒弱）を再生させないよう、終端の手前でループさせる。
 * ネイティブのloop属性は動画の最後まで再生してから戻るため、このカットが
 * 毎ループ一瞬映ってしまう。
 */
export function useLoopTrim(ref: React.RefObject<HTMLVideoElement>, marginSec = 1.0, deps: readonly unknown[] = []) {
  useEffect(() => {
    const v = ref.current;
    if (!v) return undefined;
    const onTimeUpdate = () => {
      if (v.duration && v.currentTime >= v.duration - marginSec) {
        v.currentTime = 0;
        v.play().catch(() => {});
      }
    };
    v.addEventListener('timeupdate', onTimeUpdate);
    return () => v.removeEventListener('timeupdate', onTimeUpdate);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ref, marginSec, ...deps]);
}
