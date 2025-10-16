  import { defineConfig } from 'vitepress'
   
  // https://vitepress.dev/reference/site-config
  export default defineConfig({
    base: '/hug-scm/',
    title: "Hug Source Control Management CLI",
    description: "Documentation for Hug, a Humane Git CLI",
    themeConfig: {
      search: {
        provider: 'local',
        options: {
          translations: {
            button: {
              buttonText: 'Search Hug commands and docs...'
            },
            modal: {
              searchBox: {
                leftPlaceholder: 'Search for commands or guides'
              },
              noResultsText: {
                noResultsText: 'No results found for',
                suggestedQueryText: 'Try searching for'
              }
            }
          }
        }
      },
      nav: [
        { text: 'Home', link: '/' },
        { text: 'Guides', link: '/hug-for-developers' },
        { text: 'Commands', link: '/commands/head' }
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
        },
        {
          text: 'Command Reference',
          items: [
            { text: 'HEAD Operations (h*)', link: '/commands/head' },
            { text: 'Working Directory (w*)', link: '/commands/working-dir' },
            { text: 'Status & Staging (s*, a*)', link: '/commands/status-staging' },
            { text: 'Branching (b*)', link: '/commands/branching' },
            { text: 'Commits (c*)', link: '/commands/commits' },
            { text: 'Logging (l*)', link: '/commands/logging' }
          ]
        }
      ]
    }
  })

