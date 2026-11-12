import { describe, it, expect } from 'vitest'
import { filterMenuItems } from '../../src/utils/filter-menu-items'
import { nativeMenuItems } from '../../src/layouts/config'

// Flatten a menu tree into "Group > Sub > Page" strings so assertions read like the sidebar.
const pagePaths = (items, trail = []) =>
  items.flatMap((item) =>
    item.items
      ? pagePaths(item.items, [...trail, item.title])
      : [[...trail, item.title].join(' > ')]
  )

const leafPages = (items) =>
  items.flatMap((item) => (item.items ? leafPages(item.items) : [item]))

const menu = [
  {
    title: 'Email & Exchange',
    type: 'header',
    permissions: ['Exchange.Mailbox.*', 'Exchange.Contact.*'],
    items: [
      {
        title: 'Administration',
        permissions: ['Exchange.Mailbox.*'],
        items: [
          {
            title: 'Mailboxes',
            path: '/email/administration/mailboxes',
            permissions: ['Exchange.Mailbox.*'],
          },
          {
            title: 'Contacts',
            path: '/email/administration/contacts',
            permissions: ['Exchange.Contact.*'],
          },
        ],
      },
    ],
  },
  {
    title: 'Dashboard',
    path: '/',
    permissions: ['CIPP.Core.*'],
  },
]

describe('filterMenuItems', () => {
  it('shows a page when the user has a permission matching its wildcard', () => {
    const result = filterMenuItems(menu, { permissions: ['CIPP.Core.Read'] })
    expect(pagePaths(result)).toEqual(['Dashboard'])
  })

  it('matches exact permission strings', () => {
    const exactMenu = [
      { title: 'Logbook', path: '/cipp/logs', permissions: ['CIPP.Core.Read'] },
    ]
    expect(
      pagePaths(filterMenuItems(exactMenu, { permissions: ['CIPP.Core.Read'] }))
    ).toEqual(['Logbook'])
    expect(
      filterMenuItems(exactMenu, { permissions: ['CIPP.Core.ReadWrite'] })
    ).toEqual([])
  })

  it('shows a page inside a group even when the group permission does not match', () => {
    const result = filterMenuItems(menu, {
      permissions: ['Exchange.Contact.Read', 'Exchange.Contact.ReadWrite'],
    })
    expect(pagePaths(result)).toEqual([
      'Email & Exchange > Administration > Contacts',
    ])
  })

  it('removes a group when none of its pages are visible', () => {
    const result = filterMenuItems(menu, {
      permissions: ['Identity.User.Read'],
    })
    expect(result).toEqual([])
  })

  it('hides pages that declare no permissions', () => {
    const openMenu = [{ title: 'Open', path: '/open' }]
    expect(
      filterMenuItems(openMenu, { permissions: ['CIPP.Core.Read'] })
    ).toEqual([])
  })

  it('hides pages listed in hiddenPages', () => {
    const result = filterMenuItems(menu, {
      permissions: ['Exchange.Mailbox.Read', 'Exchange.Contact.Read'],
      hiddenPages: ['/email/administration/mailboxes'],
    })
    expect(pagePaths(result)).toEqual([
      'Email & Exchange > Administration > Contacts',
    ])
  })

  it('returns nothing when permissions are missing', () => {
    expect(filterMenuItems(menu, {})).toEqual([])
    expect(filterMenuItems(menu, { permissions: undefined })).toEqual([])
  })

  it('does not mutate the source menu', () => {
    const before = JSON.stringify(menu)
    filterMenuItems(menu, { permissions: ['Exchange.Contact.Read'] })
    expect(JSON.stringify(menu)).toEqual(before)
  })

  describe('against the real navigation config', () => {
    const pagesWithPermissions = leafPages(nativeMenuItems).filter(
      (page) => page.permissions?.length > 0
    )

    it('gives a user with every permission every page', () => {
      const allPermissions = [
        ...new Set(
          pagesWithPermissions.flatMap((page) =>
            page.permissions.flatMap((perm) => [
              perm.replace('*', 'Read'),
              perm.replace('*', 'ReadWrite'),
            ])
          )
        ),
      ]
      const visible = leafPages(
        filterMenuItems(nativeMenuItems, { permissions: allPermissions })
      )
      expect(visible.length).toEqual(pagesWithPermissions.length)
    })

    it.each(pagesWithPermissions.map((page) => [page.title, page]))(
      'shows %s to a role granted only that page permission',
      (_title, page) => {
        const permissions = page.permissions.map((perm) =>
          perm.replace('*', 'Read')
        )
        const visible = leafPages(
          filterMenuItems(nativeMenuItems, { permissions })
        )
        expect(visible).toContainEqual(page)
      }
    )

    it('shows only Contacts pages from Exchange for a contacts-only custom role', () => {
      const result = filterMenuItems(nativeMenuItems, {
        permissions: [
          'CIPP.Core.Read',
          'Exchange.Contact.Read',
          'Exchange.Contact.ReadWrite',
        ],
      })
      const exchangePages = pagePaths(result).filter((path) =>
        path.startsWith('Email & Exchange')
      )
      expect(exchangePages).toEqual([
        'Email & Exchange > Administration > Contacts',
        'Email & Exchange > Administration > Contact Templates',
      ])
      // The sign-in permission alone opens nothing under Tools or CIPP (issue #652).
      const otherPages = pagePaths(result).filter(
        (path) => path.startsWith('Tools') || path.startsWith('CIPP')
      )
      expect(otherPages).toEqual([])
    })

    it('shows only the dashboard to a role that can merely sign in', () => {
      const result = filterMenuItems(nativeMenuItems, {
        permissions: ['CIPP.Core.Read'],
      })
      expect(pagePaths(result)).toEqual(['Dashboard'])
    })

    it.each([
      ['Logbook', 'CIPP.Logs.Read', 'CIPP > Logbook'],
      ['Report Builder', 'CIPP.ReportBuilder.Read', 'Tools > Report Builder'],
      [
        'Template Library',
        'CIPP.TemplateLibrary.Read',
        'Tools > Template Library',
      ],
      ['Catalog', 'CIPP.TemplateLibrary.Read', 'Tools > Catalog'],
      [
        'IP Database',
        'CIPP.IPDatabase.Read',
        'Tools > Tenant Tools > IP Database',
      ],
      [
        'Breach Lookup',
        'CIPP.BreachLookup.Read',
        'Tools > Dark Web Tools > Breach Lookup',
      ],
    ])(
      'opens %s with its own permission on top of sign-in',
      (_title, permission, path) => {
        const result = filterMenuItems(nativeMenuItems, {
          permissions: ['CIPP.Core.Read', permission],
        })
        expect(pagePaths(result)).toContain(path)
      }
    )
  })
})

// redanthrax/CIPP#4: pages the selected tenant's cloud does not support are hidden.
describe('filterMenuItems cloudEnvironment', () => {
  const cloudMenu = [
    {
      title: 'Security',
      type: 'header',
      items: [
        {
          title: 'Compliance',
          items: [
            {
              title: 'DLP',
              path: '/security/compliance/dlp',
              permissions: ['Security.*'],
              unsupportedClouds: ['USGovHigh', 'USGovDoD'],
            },
            {
              title: 'DLP Templates',
              path: '/security/compliance/dlp-templates',
              permissions: ['Security.*'],
            },
          ],
        },
        {
          title: 'Voice',
          items: [
            {
              title: 'Business Voice',
              path: '/teams-share/teams/business-voice',
              permissions: ['Security.*'],
              unsupportedClouds: ['USGovHigh'],
            },
          ],
        },
      ],
    },
  ]
  const permissions = ['Security.Read']

  it('hides nothing for Commercial, no cloud or AllTenants (undefined)', () => {
    const all = filterMenuItems(cloudMenu, { permissions })
    expect(filterMenuItems(cloudMenu, { permissions, cloudEnvironment: 'Commercial' })).toEqual(all)
    expect(filterMenuItems(cloudMenu, { permissions, cloudEnvironment: undefined })).toEqual(all)
    expect(pagePaths(all)).toHaveLength(3)
  })

  it('hides pages listing the cloud and drops groups left empty', () => {
    expect(pagePaths(filterMenuItems(cloudMenu, { permissions, cloudEnvironment: 'USGovHigh' }))).toEqual([
      'Security > Compliance > DLP Templates',
    ])
    expect(pagePaths(filterMenuItems(cloudMenu, { permissions, cloudEnvironment: 'USGovDoD' }))).toEqual([
      'Security > Compliance > DLP Templates',
      'Security > Voice > Business Voice',
    ])
  })

  it('still applies permissions and hiddenPages with a cloud', () => {
    expect(filterMenuItems(cloudMenu, { permissions: ['Other.Read'], cloudEnvironment: 'USGovHigh' })).toEqual([])
    expect(
      filterMenuItems(cloudMenu, {
        permissions,
        cloudEnvironment: 'USGovDoD',
        hiddenPages: ['/security/compliance/dlp-templates'],
      }).map((item) => item.title)
    ).toEqual(['Security'])
  })

  describe('against the real navigation config', () => {
    const everyPermission = [
      ...new Set(
        leafPages(nativeMenuItems).flatMap((page) =>
          (page.permissions ?? []).flatMap((perm) => [perm.replace('*', 'Read'), perm.replace('*', 'ReadWrite')])
        )
      ),
    ]

    it('shows a Commercial tenant exactly the menu it shows without a cloud', () => {
      expect(
        filterMenuItems(nativeMenuItems, { permissions: everyPermission, cloudEnvironment: 'Commercial' })
      ).toEqual(filterMenuItems(nativeMenuItems, { permissions: everyPermission }))
    })

    it('hides the matrix pages for a GCC High tenant and keeps everything else', () => {
      const all = leafPages(filterMenuItems(nativeMenuItems, { permissions: everyPermission })).map((p) => p.path)
      const gov = leafPages(
        filterMenuItems(nativeMenuItems, { permissions: everyPermission, cloudEnvironment: 'USGovHigh' })
      ).map((p) => p.path)
      const hidden = all.filter((path) => !gov.includes(path))
      expect(hidden.sort()).toEqual(
        [
          '/copilot/agent365/packages',
          '/copilot/settings',
          '/copilot/reports/copilot-adoption',
          '/copilot/reports/copilot-trend',
          '/copilot/reports/copilot-usage',
          '/identity/administration/jit-admin',
          '/security/compliance/dlp',
          '/security/compliance/labels',
          '/security/compliance/retention',
          '/security/compliance/sit',
          '/teams-share/teams/business-voice',
          '/tenant/gsa/filtering-policies',
          '/tenant/gsa/security-profiles',
          '/tenant/gsa/traffic-forwarding',
          '/tenant/reports/graph-office-reports',
        ].sort()
      )
      expect(gov).toContain('/security/compliance/dlp-templates')
    })

    const jitItem = (cloudEnvironment) =>
      leafPages(filterMenuItems(nativeMenuItems, { permissions: everyPermission, cloudEnvironment })).find(
        (page) => page.title === 'JIT Admin'
      )

    it('links JIT Admin to its Requests page for a government tenant, keeping its title and permissions', () => {
      for (const cloud of ['USGovHigh', 'USGovDoD']) {
        const item = jitItem(cloud)
        expect(item.path).toBe('/identity/administration/jit-admin/requests')
        expect(item.permissions).toEqual(['Identity.Role.*'])
      }
      expect(jitItem('USGovHigh')).not.toBe(jitItem(undefined))
      expect(filterMenuItems(nativeMenuItems, { permissions: ['Other.Read'], cloudEnvironment: 'USGovHigh' })).toEqual([])
    })

    it('gives Commercial and AllTenants the unchanged JIT Admin item, the same object as the config', () => {
      const configItem = leafPages(nativeMenuItems).find((page) => page.title === 'JIT Admin')
      expect(configItem.path).toBe('/identity/administration/jit-admin')
      expect(jitItem('Commercial')).toBe(configItem)
      expect(jitItem(undefined)).toBe(configItem)
      // every Commercial page is the config's own object, so nothing about the menu changed
      const configPages = leafPages(nativeMenuItems)
      for (const page of leafPages(
        filterMenuItems(nativeMenuItems, { permissions: everyPermission, cloudEnvironment: 'Commercial' })
      )) {
        expect(configPages).toContain(page)
      }
    })
  })
})
