# Kyte web app

A hypermedia web app scaffolded with `kyte init web`. It follows a vertical-slice layout: each use
case lives under `src/Features/<Feature>/` with its own handler, and `src/main.ky` is the
composition root that wires the routes. Handlers return HTML fragments that your hypermedia
framework (see `wwwroot/index.html`) swaps into the page.

## Run

```sh
kyte build
./build/debug/bin/<project> --port 8080   # or: kyte run
# open http://127.0.0.1:8080/
```

## Styling with Tailwind CSS

Styles are built by the Tailwind CLI from `styles/app.css` into `wwwroot/index.css`, which
`wwwroot/index.html` links. The content globs that tell Tailwind which files to scan for class
names live in `tailwind.config.js`. This follows the official guide:
https://tailwindcss.com/docs/installation/tailwind-cli

Install the Tailwind CLI once:

```sh
npm install tailwindcss @tailwindcss/cli
```

Then keep it running in watch mode, so `wwwroot/index.css` is rebuilt every time you edit a view.
If it is not running, a class you just used will be missing until you run it again:

```sh
npx @tailwindcss/cli -i ./styles/app.css -o ./wwwroot/index.css --watch
```

For a production build, run it once with `--minify` as part of your pipeline:

```sh
npx @tailwindcss/cli -i ./styles/app.css -o ./wwwroot/index.css --minify
```

These are also wired as `npm run css:watch` and `npm run css` in `package.json`.

## Optional: the kyte-ui component kit

[kyte-ui](https://github.com/kytelang/kyte-ui) is a small, presentational component kit for KYX,
styled with Tailwind. It is optional and not included by default. To add it:

1. Declare the dependency in `project.json`, then `kyte build` to fetch it:

   ```json
   { "dependencies": ["https://github.com/kytelang/kyte-ui"] }
   ```

2. Use components in your views with qualified tags:

   ```kyte
   import ui;
   pub fn card(name: string): Html {
       return <ui.Card title={name}>
           <ui.Badge tone={ui.Tone.Success}>active</ui.Badge>
       </ui.Card>;
   }
   ```

3. Make Tailwind emit the kit's classes. Its component source is in the fetched dependency, not
   your project, so add the kit's class safelist to Tailwind's content. Download `safelist.txt`
   from the kyte-ui repo into `styles/kyte-ui.safelist.txt`, then add it to `tailwind.config.js`:

   ```js
   content: [
     "./src/**/*.{kyx,ky}",
     "./wwwroot/*.html",
     "./styles/kyte-ui.safelist.txt",
   ],
   ```

   Keep `npm run css:watch` running so the classes land in `wwwroot/index.css`.

4. For the interactive widgets (tab switching, modal reopen, toast dismiss, dropdown close),
   download `kyte-ui.js` from the kyte-ui repo into `wwwroot/` and link it in `index.html`:

   ```html
   <script src="/kyte-ui.js" defer></script>
   ```

5. For the kit's `dark:` variants, enable Tailwind's class strategy in `styles/app.css` and toggle
   a `.dark` class on `<html>` yourself:

   ```css
   @custom-variant dark (&:where(.dark, .dark *));
   ```

See the guide chapter "The kyte-ui component kit" for the full component list and details.