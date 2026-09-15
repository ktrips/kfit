import React, { useEffect, useRef, useState } from 'react';
import { useLoopTrim } from '../hooks/useLoopTrim';

interface RotatingVideoProps {
  sources: string[];
  intervalMs?: number;
  className?: string;
  style?: React.CSSProperties;
}

/**
 * 複数の動画を一定間隔でクロスフェード切替する。
 * 裏側の<video>に次の動画を事前ロード＆再生しておいてから
 * opacityだけを切り替えるため、切替の一瞬に何も表示されない
 * 空白（背後のアイコン表示等）が生じない。
 */
export const RotatingVideo: React.FC<RotatingVideoProps> = ({ sources, intervalMs = 10_000, className, style }) => {
  const videoRefA = useRef<HTMLVideoElement>(null);
  const videoRefB = useRef<HTMLVideoElement>(null);
  const [activeIsA, setActiveIsA] = useState(true);
  const currentIdxRef = useRef(0);

  useLoopTrim(videoRefA);
  useLoopTrim(videoRefB);

  useEffect(() => {
    if (sources.length === 0) return;
    if (videoRefA.current) videoRefA.current.src = sources[0];
    if (videoRefB.current) videoRefB.current.src = sources[1 % sources.length];
    currentIdxRef.current = 0;
    setActiveIsA(true);
  }, [sources]);

  useEffect(() => {
    if (sources.length <= 1) return undefined;
    const timer = setInterval(() => {
      const nextIdx = (currentIdxRef.current + 1) % sources.length;
      const nextNextIdx = (currentIdxRef.current + 2) % sources.length;
      const incoming = activeIsA ? videoRefB.current : videoRefA.current;
      const outgoing = activeIsA ? videoRefA.current : videoRefB.current;

      incoming?.play().catch(() => {});
      currentIdxRef.current = nextIdx;
      setActiveIsA((v) => !v);

      if (outgoing) {
        outgoing.src = sources[nextNextIdx];
        outgoing.load();
      }
    }, intervalMs);
    return () => clearInterval(timer);
  }, [sources, activeIsA, intervalMs]);

  const videoStyle = (visible: boolean): React.CSSProperties => ({
    position: 'absolute',
    inset: 0,
    width: '100%',
    height: '100%',
    objectFit: 'cover',
    opacity: visible ? 1 : 0,
    transition: 'opacity 400ms ease',
  });

  return (
    <div className={className} style={{ position: 'relative', width: '100%', height: '100%', ...style }}>
      <video ref={videoRefA} autoPlay muted playsInline preload="auto" style={videoStyle(activeIsA)} />
      <video ref={videoRefB} autoPlay muted playsInline preload="auto" style={videoStyle(!activeIsA)} />
    </div>
  );
};
