import React from 'react';

interface MascotProps {
  className?: string;
  size?: number;
}

export const Mascot: React.FC<MascotProps> = ({ className, size = 200 }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 200 200"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
  >
    <defs>
      <radialGradient id="flameBg" cx="50%" cy="65%" r="55%">
        <stop offset="0%" stopColor="#FF8C00" />
        <stop offset="45%" stopColor="#FF4500" />
        <stop offset="100%" stopColor="#6B0000" />
      </radialGradient>
      <radialGradient id="bodyGlow" cx="50%" cy="35%" r="60%">
        <stop offset="0%" stopColor="#78E000" />
        <stop offset="100%" stopColor="#46A302" />
      </radialGradient>
    </defs>

    {/* ── Background ── */}
    <rect width="200" height="200" fill="url(#flameBg)" />

    {/* Flame shapes */}
    <ellipse cx="30"  cy="185" rx="32" ry="50" fill="#FF6B00" opacity="0.55" />
    <ellipse cx="170" cy="180" rx="28" ry="45" fill="#FF4500" opacity="0.45" />
    <ellipse cx="100" cy="195" rx="55" ry="28" fill="#FF8C00" opacity="0.5"  />
    <ellipse cx="60"  cy="155" rx="20" ry="35" fill="#FF5500" opacity="0.35" />
    <ellipse cx="145" cy="160" rx="18" ry="30" fill="#FF3300" opacity="0.35" />

    {/* ── Left arm (viewer's left = character's right) ── */}
    {/* Upper arm */}
    <ellipse cx="52" cy="118" rx="26" ry="15" fill="#46A302" transform="rotate(-45 52 118)" />
    {/* Bicep */}
    <ellipse cx="33" cy="94"  rx="22" ry="14" fill="#58CC02" transform="rotate(-55 33 94)" />
    {/* Forearm + fist */}
    <ellipse cx="20" cy="70"  rx="14" ry="19" fill="#46A302" transform="rotate(-15 20 70)" />
    <circle  cx="18" cy="53"  r="15"           fill="#58CC02" />

    {/* ── Right arm ── */}
    <ellipse cx="148" cy="118" rx="26" ry="15" fill="#46A302" transform="rotate(45 148 118)" />
    <ellipse cx="167" cy="94"  rx="22" ry="14" fill="#58CC02" transform="rotate(55 167 94)" />
    <ellipse cx="180" cy="70"  rx="14" ry="19" fill="#46A302" transform="rotate(15 180 70)" />
    <circle  cx="182" cy="53"  r="15"           fill="#58CC02" />

    {/* ── Torso ── */}
    <ellipse cx="100" cy="148" rx="43" ry="46" fill="url(#bodyGlow)" />
    {/* Abs */}
    <ellipse cx="91"  cy="143" rx="9" ry="7" fill="#46A302" opacity="0.55" />
    <ellipse cx="109" cy="143" rx="9" ry="7" fill="#46A302" opacity="0.55" />
    <ellipse cx="91"  cy="159" rx="9" ry="7" fill="#46A302" opacity="0.55" />
    <ellipse cx="109" cy="159" rx="9" ry="7" fill="#46A302" opacity="0.55" />
    {/* Chest line */}
    <line x1="100" y1="126" x2="100" y2="142" stroke="#46A302" strokeWidth="2" opacity="0.5" />

    {/* ── Neck ── */}
    <rect x="88" y="103" width="24" height="16" rx="8" fill="#58CC02" />

    {/* ── Head ── */}
    <circle cx="100" cy="84" r="37" fill="url(#bodyGlow)" />
    {/* Feather tuft on top */}
    <ellipse cx="100" cy="49" rx="10" ry="8"  fill="#46A302" />
    <ellipse cx="90"  cy="51" rx="7"  ry="6"  fill="#46A302" />
    <ellipse cx="110" cy="51" rx="7"  ry="6"  fill="#46A302" />

    {/* ── Eyes ── */}
    {/* Brow furrow (determined look) */}
    <line x1="78" y1="68" x2="92" y2="72" stroke="#2d7a00" strokeWidth="3" strokeLinecap="round" />
    <line x1="122" y1="68" x2="108" y2="72" stroke="#2d7a00" strokeWidth="3" strokeLinecap="round" />
    {/* Sclera */}
    <ellipse cx="87"  cy="78" rx="9"  ry="10" fill="white" />
    <ellipse cx="113" cy="78" rx="9"  ry="10" fill="white" />
    {/* Iris */}
    <circle cx="89"  cy="80" r="5.5" fill="#1a1a1a" />
    <circle cx="115" cy="80" r="5.5" fill="#1a1a1a" />
    {/* Shine */}
    <circle cx="91"  cy="77" r="2"   fill="white" />
    <circle cx="117" cy="77" r="2"   fill="white" />

    {/* ── Beak ── */}
    <polygon points="100,82 124,76 124,90" fill="#FF9600" />
    <line x1="100" y1="82" x2="124" y2="83" stroke="#CC6600" strokeWidth="1.2" opacity="0.6" />

    {/* ── Feet / boots ── */}
    {/* Legs */}
    <rect x="80"  y="183" width="11" height="14" rx="4" fill="#FF9600" />
    <rect x="109" y="183" width="11" height="14" rx="4" fill="#FF9600" />
    {/* Boot body */}
    <rect x="70"  y="191" width="28" height="9" rx="5" fill="#FF9600" />
    <rect x="102" y="191" width="28" height="9" rx="5" fill="#FF9600" />
    {/* Boot toe bump */}
    <ellipse cx="73"  cy="196" rx="6" ry="5" fill="#E67E00" />
    <ellipse cx="127" cy="196" rx="6" ry="5" fill="#E67E00" />
  </svg>
);
