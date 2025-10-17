  // https://vitepress.dev/reference/site-config
  export default {
    base: '/hug-scm/',
    title: "Hug SCM CLI",
    description: "Documentation for Hug, a Humane Git CLI",
    head: [
      ['meta', { name: 'theme-color', content: '#3b82f6' }],
      ['meta', { name: 'og:title', content: 'Hug SCM CLI Documentation' }],
      ['link', { rel: 'icon', href: '/favicon.ico' }]
    ],
    themeConfig: {
      search: {
        provider: 'local'
      },
      nav: [
        { text: 'Home', link: '/' },
        { text: 'Guides', link: '/hug-for-developers' },
        { text: 'Commands', link: '/command-map' },
        { text: 'GitHub', link: 'https://github.com/elifarley/hug-scm' }
      ],
      sidebar: [
        {
          text: 'Developer Guides',
          collapsible: true,
          collapsed: false,
          items: [
            { text: 'Hug for Developers', link: '/hug-for-developers' },
          ]
        },
        {
          text: 'Command Reference',
          collapsible: true,
          collapsed: false,
          items: [
            { text: 'Command Map', link: '/command-map' },
            { text: 'Cheat Sheet', link: '/cheat-sheet' },
            {
              text: 'Core Commands',
              collapsible: true,
              collapsed: true,
              items: [
                { text: 'HEAD Operations (h*)', link: '/commands/head' },
                { text: 'Working Directory & WIP (w*)', link: '/commands/working-dir' },
                { text: 'Status & Staging (s*, a*)', link: '/commands/status-staging' },
                { text: 'Branching (b*)', link: '/commands/branching' },
                { text: 'Commits (c*)', link: '/commands/commits' },
                { text: 'Logging (l*)', link: '/commands/logging' },
                { text: 'File Inspection (f*)', link: '/commands/file-inspection' }
              ]
            }
          ]
        }
      ],
      outline: [2, 6],
      editLink: {
        pattern: 'https://github.com/elifarley/hug-scm/edit/main/docs/:path',
        text: 'Edit this page on GitHub'
      },
      footer: {
        message: 'Released under the MIT License.',
        copyright: 'Copyright © 2023 Elifarley'
      },
      socialLinks: [
        { icon: 'github', link: 'https://github.com/elifarley/hug-scm' }
      ],
      lastUpdated: {
        text: 'Last updated',
        formatOptions: {
          year: 'numeric',
          month: 'short',
          day: 'numeric'
        }
      }
    }
  }

