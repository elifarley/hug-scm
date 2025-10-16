  import { defineConfig } from 'vitepress'
   
  // https://vitepress.dev/reference/site-config
  export default defineConfig({
    base: '/hug-scm/',
    title: "Hug Source Control Management CLI",
    description: "Documentation for Hug, a Humane Git CLI",
    themeConfig: {
      search: {
        provider: 'local'
      },
      nav: [
        { text: 'Home', link: '/' },
        { text: 'Guides', link: '/hug-for-developers' }
      ],
      sidebar: [
        {
          text: 'Developer Guides',
          items: [
            { text: 'Hug for Developers', link: '/hug-for-developers' },
            { text: 'Hug Head Demo', link: '/hug-head-demo' },
            { text: 'Hug Logging Demo', link: '/hug-logging-demo' },
            { text: 'Hug Working Dir Demo', link: '/hug-working-dir-demo' }
          ]
        }
      ]
    }
  })

