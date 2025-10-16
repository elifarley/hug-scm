  // https://vitepress.dev/reference/site-config
  export default {
    base: '/hug-scm/',
    title: "Hug Source Control Management CLI",
    description: "Documentation for Hug, a Humane Git CLI",
    themeConfig: {
      search: {
        provider: 'local'
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
  }

