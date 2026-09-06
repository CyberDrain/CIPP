// The figures the branding editor's cover mock quotes for each report. They are the headline
// values of the server-side samples (backend/Config/ReportSamples/<type>.json) the live preview
// renders, copied here because the static frontend build cannot read the backend tree; keep the two
// in step so the mock and the rendered preview describe the same report.

export const SAMPLE_TENANT_NAME = 'Contoso (sample data)'

export const SAMPLE_BEC = {
  userData: {
    displayName: 'Sample User',
    userPrincipalName: 'sample.user@example.com',
  },
  becData: {
    ExtractedAt: '2026-08-05T09:00:00Z',
  },
}

export const SAMPLE_SHARING = {
  summary: {
    totalLinks: 24,
    itemsShared: 18,
    externalRecipients: 6,
  },
}

export const SAMPLE_PERMISSIONS = {
  summary: {
    totalAssignments: 156,
    sitesScanned: 12,
    librariesScanned: 34,
  },
}

export const SAMPLE_MAIL_FLOW = {
  days: 14,
  totals: {
    GoodMail: 48210,
    TransportRules: 1340,
    SpamDetections: 6120,
    EdgeBlockSpam: 3980,
    EmailPhish: 412,
    EmailMalware: 37,
  },
}
