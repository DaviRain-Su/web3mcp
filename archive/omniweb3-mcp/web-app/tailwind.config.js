/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#f0f9ff',
          500: '#7c3aed',
          600: '#6d28d9',
          700: '#5b21b6',
        }
      },
    },
  },
  plugins: [],
}
