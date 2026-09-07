import { BEC_GROUPS } from '../../src/utils/bec-objectives'

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
