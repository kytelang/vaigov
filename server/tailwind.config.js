/** Colours are driven by the CSS custom properties in styles/app.css (the theme
 *  toggle flips them), matching the Vue console's tailwind.config.js. */
module.exports = {
  content: [
    "./src/**/*.{kyx,ky}",
    "./wwwroot/*.html",
  ],
  theme: {
    extend: {
      colors: {
        bg: 'var(--bg)', panel: 'var(--panel)', panel2: 'var(--panel2)',
        line: 'var(--line)', line2: 'var(--line2)',
        txt: 'var(--txt)', dim: 'var(--dim)', muted: 'var(--muted)',
        accent: 'var(--accent)', ok: 'var(--ok)', warn: 'var(--warn)', bad: 'var(--bad)'
      },
      maxWidth: { content: '1080px' }
    }
  },
  plugins: []
}
