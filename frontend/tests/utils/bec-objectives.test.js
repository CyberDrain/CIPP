import { BEC_GROUPS, becPartnerActions } from '../../src/utils/bec-objectives'

const finding = (key) =>
  BEC_GROUPS.flatMap((group) => group.findings).find((f) => f.key === key)

describe('bec-objectives inbox rules', () => {
  it('folds the latest audited change into each rule and keeps the rule detail for More Info', () => {
    const rows = finding('NewRules').rows(
      {
        NewRules: [
          {
            Name: 'Exfil',
            Risk: 'High',
            RiskReasons: ['Forwards or redirects mail to an external address'],
            Description: 'If the message... forward it to x@example.org',
            ForwardTo: ['x@example.org'],
            SubjectContainsWords: [],
            DistinguishedName: 'CN=Exfil,CN=...',
            Enabled: true,
            RecentlyChanged: true,
          },
        ],
        InboxRuleChanges: [
          {
            Operation: 'New-InboxRule',
            RuleName: 'mailbox\\Exfil',
            Date: '2026-08-19T01:00:00Z',
            ClientIP: '203.0.113.10',
            Country: 'NG',
          },
          {
            Operation: 'Set-InboxRule',
            RuleName: 'exfil',
            Date: '2026-08-20T01:00:00Z',
            ClientIP: '198.51.100.7',
            Country: 'US',
            AuditData: { Operation: 'Set-InboxRule' },
          },
          {
            Operation: 'Set-InboxRule',
            RuleName: 'Other',
            Date: '2026-08-21T01:00:00Z',
            ClientIP: '198.51.100.8',
            Country: 'US',
          },
        ],
      },
      { windowDays: 7 }
    )
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({
      Name: 'Exfil',
      Risk: 'High',
      RiskReasons: 'Forwards or redirects mail to an external address',
      LastChange: 'Set-InboxRule',
      ChangeDate: '2026-08-20T01:00:00Z',
      ChangedFrom: '198.51.100.7',
      Country: 'US',
      ForwardTo: ['x@example.org'],
      Enabled: true,
      ChangeAuditData: { Operation: 'Set-InboxRule' },
    })
    // Exchange plumbing and empty conditions are dropped, so More Info reads as the rule's behaviour
    expect(rows[0]).not.toHaveProperty('DistinguishedName')
    expect(rows[0]).not.toHaveProperty('SubjectContainsWords')
  })

  it('leaves the change columns empty for a rule with no audited change in the window', () => {
    const rows = finding('NewRules').rows(
      {
        NewRules: [{ Name: 'Old rule', Risk: 'Review', RiskReasons: [] }],
        InboxRuleChanges: [],
      },
      { windowDays: 7 }
    )
    expect(rows[0]).toMatchObject({
      Name: 'Old rule',
      LastChange: '',
      ChangeDate: '',
      ChangedFrom: '',
    })
  })
})

describe('becPartnerActions', () => {
  it('gathers the rows a partner or CIPP identity acted on from every source, newest first', () => {
    const rows = becPartnerActions({
      DirectoryAudits: [
        {
          ActivityDateTime: '2026-08-19T03:00:00Z',
          Activity: 'Reset user password',
          InitiatedBy: 'CIPP-SAM',
          ActorKind: 'CIPP',
          ActorResolved: 'CIPP (service principal)',
          Targets: 'victim@contoso.com',
        },
        {
          ActivityDateTime: '2026-08-19T04:00:00Z',
          Activity: 'Update user',
          InitiatedBy: 'admin@contoso.com',
          ActorKind: 'User',
        },
      ],
      InboxRuleChanges: [
        {
          Date: '2026-08-19T02:00:00Z',
          Operation: 'New-InboxRule',
          RuleName: 'Partner rule',
          UserKey: 'user_0123@contoso.onmicrosoft.com',
          ActorKind: 'Partner',
          ActorResolved: 'tech@msp.example',
          ClientIP: '198.51.100.7',
          Country: 'GB',
        },
      ],
      MailboxPermissionChanges: [
        {
          Date: '2026-08-19T05:00:00Z',
          Operation: 'Add-MailboxPermission',
          Permissions: ['FullAccess'],
          Trustee: 'helper@contoso.com',
          TargetsSuspect: true,
          UserId: 'x',
          ActorKind: 'OtherPartner',
        },
        {
          Date: '2026-08-19T06:00:00Z',
          Operation: 'Add-MailboxPermission',
          Permissions: ['FullAccess'],
          TargetsSuspect: false,
          ActorKind: 'Partner',
        },
      ],
    })
    expect(rows.map((r) => r.Source)).toEqual([
      'Mailbox permission',
      'Directory audit',
      'Inbox rule',
    ])
    expect(rows[0]).toMatchObject({
      ActorKind: 'OtherPartner',
      Detail: 'FullAccess to helper@contoso.com',
    })
    expect(rows[1]).toMatchObject({
      Actor: 'CIPP (service principal)',
      ActorKind: 'CIPP',
      Operation: 'Reset user password',
    })
    expect(rows[2]).toMatchObject({
      Actor: 'tech@msp.example',
      ActorKind: 'Partner',
      Detail: 'Partner rule',
      Country: 'GB',
    })
  })
})
