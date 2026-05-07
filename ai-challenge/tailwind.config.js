/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#6C63FF',
          dark:    '#5A52D5',
          light:   '#EEF2FF',
        },
        gold:   '#F59E0B',
        silver: '#9CA3AF',
        bronze: '#B45309',
        stage: {
          dojo:    '#10B981',
          builder: '#3B82F6',
          creator: '#8B5CF6',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      animation: {
        'pulse-slow': 'pulse 3s ease-in-out infinite',
        'bounce-slow': 'bounce 2s infinite',
      },
    },
  },
  plugins: [],
};
