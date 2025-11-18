import { defineConfig } from 'vitepress'
  import { pagefindPlugin } from 'vitepress-plugin-pagefind'

  // https://vitepress.dev/reference/site-config
  export default defineConfig({
    vite: {
      plugins: [pagefindPlugin()],
    },
    base: '/hug-scm/',
    sitemap: {
      hostname: 'https://elifarley.github.io/hug-scm/'
    },
    title: "Hug SCM CLI",
    description: "Documentation for Hug, a Humane Git CLI",
    head: [
      ['meta', { name: 'theme-color', content: '#3b82f6' }],
      ['meta', { name: 'og:title', content: 'Hug SCM CLI Documentation' }],
      ['link', { rel: 'icon', href: '/favicon.png' }],
      ['script', { async: true, src: 'https://www.googletagmanager.com/gtag/js?id=G-J56MPE18TS' }],
      ['script', {}, `
        window.dataLayer = window.dataLayer || [];
        function gtag(){dataLayer.push(arguments);}
        gtag('js', new Date());
        gtag('config', 'G-J56MPE18TS');
      `]
    ],
    themeConfig: {
      search: {
        provider: 'pagefind'
      },
      logo: '/hug-icon.png',
      nav: [
        { text: 'Home', link: '/' },
        { text: 'Getting Started', link: '/getting-started' },
        { text: 'Workflows', link: '/workflows' },
        { text: 'Commands', link: '/command-map' },
        { text: 'Try it online', link: 'https://codespaces.new/elifarley/hug-scm' },
        { text: 'GitHub', link: 'https://github.com/elifarley/hug-scm' }
      ],
      sidebar: [
        {
          text: 'Guides',
          collapsible: true,
          collapsed: false,
          items: [
            { text: 'Installation', link: '/installation' },
            { text: 'Getting Started', link: '/getting-started' },
            { text: 'Workflows', link: '/workflows' },
            { text: '📚 Legacy: Beginner\'s Guide', link: '/hug-for-beginners' },
            { text: '📚 Legacy: Core Concepts', link: '/core-concepts' },
            { text: '📚 Legacy: Practical Workflows', link: '/practical-workflows' },
            { text: '📚 Legacy: Cookbook', link: '/cookbook' }
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
                { text: 'Utilities (clone, etc.)', link: '/commands/utilities' },
                { text: 'HEAD Operations (h*)', link: '/commands/head' },
                { text: 'Working Directory & WIP (w*)', link: '/commands/working-dir' },
                { text: 'Status & Staging (s*, a*)', link: '/commands/status-staging' },
                { text: 'Branching (b*)', link: '/commands/branching' },
                { text: 'Commits (c*)', link: '/commands/commits' },
                { text: 'Logging (l*)', link: '/commands/logging' },
                { text: 'File Inspection (f*)', link: '/commands/file-inspection' },
                { text: 'Tagging (t*)', link: '/commands/tagging' },
                { text: 'Rebase (r*)', link: '/commands/rebase' },
                { text: 'Merge (m*)', link: '/commands/merge' }
              ]
            }
          ]
        },
        {
          text: 'MCP Server',
          collapsible: true,
          collapsed: true,
          items: [
            { text: 'Overview', link: '/mcp-server/index' },
            { text: 'Quick Start', link: '/mcp-server/quickstart' },
            { text: 'Usage', link: '/mcp-server/usage' },
            { text: 'Architecture', link: '/mcp-server/architecture' },
            { text: 'Examples', link: '/mcp-server/examples' }
          ]
        }
      ],
      outline: [2, 6],
      editLink: {
        pattern: 'https://github.com/elifarley/hug-scm/edit/main/docs/:path',
        text: 'Edit this page on GitHub'
      },
      footer: {
        message: 'Released under the Apache 2.0 License.',
        copyright: 'Copyright © 2025 Elifarley'
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
  })

