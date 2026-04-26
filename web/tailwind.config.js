/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Nunito', 'sans-serif'],
      },
      colors: {
        duo: {
          green: '#58CC02',
          'green-dark': '#46A302',
          'green-light': '#D7FFB8',
          yellow: '#FFD900',
          'yellow-dark': '#CE9700',
          orange: '#FF9600',
          'orange-dark': '#CC7000',
          blue: '#1CB0F6',
          'blue-dark': '#0E8FC5',
          red: '#FF4B4B',
          purple: '#CE82FF',
          'gray-light': '#F7F7F7',
          'gray-mid': '#E5E5E5',
          gray: '#AFAFAF',
          dark: '#3C3C3C',
        },
      },
      keyframes: {
        bounce_in: {
          '0%': { transform: 'scale(0.8)', opacity: '0' },
          '60%': { transform: 'scale(1.1)' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        wiggle: {
          '0%, 100%': { transform: 'rotate(-3deg)' },
          '50%': { transform: 'rotate(3deg)' },
        },
        pop: {
          '0%': { transform: 'scale(1)' },
          '50%': { transform: 'scale(1.2)' },
          '100%': { transform: 'scale(1)' },
        },
      },
      animation: {
        bounce_in: 'bounce_in 0.4s ease-out',
        wiggle: 'wiggle 0.5s ease-in-out',
        pop: 'pop 0.2s ease-out',
      },
    },
  },
  plugins: [],
}
