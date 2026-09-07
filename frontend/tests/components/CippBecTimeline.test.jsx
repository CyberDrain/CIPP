import {
  buildBecTimeline,
  buildBecCorrelationGraph,
} from '../../src/utils/bec-timeline'
import { CippBecTimelineCustom } from '../../src/components/CippComponents/CippBecTimelineCustom'
import { CippBecCorrelationGraph } from '../../src/components/CippComponents/CippBecCorrelationGraph'
import { SAMPLE_BEC } from '../../src/components/CippPdf/previewSampleData'
import { renderWithProviders } from '../test-utils'

describe('buildBecTimeline', () => {
  it('correlates events from the sample case, sorted ascending, with a start of compromise', () => {
    const { events, startOfCompromise } = buildBecTimeline(
      SAMPLE_BEC.becData,
      7
    )
    expect(events.length).toBeGreaterThan(0)
    expect(events.every((event) => event.date instanceof Date)).toBe(true)
    for (let i = 1; i < events.length; i += 1) {
      expect(events[i].ts).toBeGreaterThanOrEqual(events[i - 1].ts)
    }
    expect(startOfCompromise).toBeTruthy()
    // every event is classified into one of the five objectives
    const objectives = new Set([
      'access',
      'persistence',
      'mailflow',
      'exfil',
      'blast',
    ])
    expect(events.every((event) => objectives.has(event.objective))).toBe(true)
  })

  it('returns an empty result for empty or missing data', () => {
    expect(buildBecTimeline({}, 7)).toEqual({
      events: [],
      startOfCompromise: null,
    })
    expect(buildBecTimeline(null)).toEqual({
      events: [],
      startOfCompromise: null,
    })
  })

  const sentRow = (i, hour) => ({
    MessageTraceId: `m${i}`,
    // uneven split so the top subject is unambiguous (26 of 40 rows in the first hour)
    Subject: i % 3 ? 'Invoice attached' : 'Urgent',
    RecipientAddress: `r${i}@example.org`,
    Received: `2026-08-20T${String(hour).padStart(2, '0')}:${String(i % 60).padStart(2, '0')}:00Z`,
    FromIP: '203.0.113.10',
  })

  it('keeps one event per sent message up to the compaction threshold', () => {
    const rows = Array.from({ length: 25 }, (_, i) => sentRow(i, 10))
    const { events } = buildBecTimeline(
      { SentMessages: rows },
      7,
      'v@contoso.com'
    )
    const sent = events.filter((e) => e.category === 'sent')
    expect(sent).toHaveLength(25)
    expect(sent[0].label).toBe('Sent mail')
    expect(sent[0].affects).toBe('r0@example.org')
  })

  it('folds a mass mailing into one event per hour and source with message and recipient counts', () => {
    const rows = [
      ...Array.from({ length: 40 }, (_, i) => sentRow(i, 10)),
      ...Array.from({ length: 20 }, (_, i) => sentRow(100 + i, 11)),
    ]
    const { events } = buildBecTimeline(
      { SentMessages: rows },
      7,
      'v@contoso.com'
    )
    const sent = events.filter((e) => e.category === 'sent')
    expect(sent).toHaveLength(2)
    expect(sent[0].label).toBe('40 emails sent')
    expect(sent[0].ip).toBe('203.0.113.10')
    expect(sent[0].target).toContain('to 40 recipients')
    expect(sent[0].target).toContain('"Invoice attached"')
    expect(sent[0].date.toISOString()).toBe('2026-08-20T10:00:00.000Z')
    expect(sent[1].label).toBe('20 emails sent')
    expect(sent[1].affects).toBeUndefined()
  })
})

describe('buildBecCorrelationGraph', () => {
  it('groups events by source IP and ties in the other accounts the victim acted on', () => {
    const graph = buildBecCorrelationGraph(
      SAMPLE_BEC.becData,
      7,
      SAMPLE_BEC.userData.userPrincipalName
    )
    expect(graph.hubs.length).toBeGreaterThan(0)
    // every event under a hub actually shares that hub's source IP
    graph.hubs.forEach((hub) => {
      hub.events.forEach((event) => expect(event.ip).toBe(hub.ip))
    })
    // the sample's sent mail reaches an outside recipient, so at least one affected account is tied in
    expect(graph.targets.length).toBeGreaterThan(0)
    // and never a self-referential edge back to the investigated user
    expect(
      graph.targets.some(
        (target) =>
          target.account.toLowerCase() ===
          SAMPLE_BEC.userData.userPrincipalName.toLowerCase()
      )
    ).toBe(false)
  })
})

describe('CippBecTimelineCustom', () => {
  it('renders the correlated timeline without crashing', () => {
    const { container } = renderWithProviders(
      <CippBecTimelineCustom becData={SAMPLE_BEC.becData} windowDays={7} />
    )
    expect(container.querySelectorAll('li').length).toBeGreaterThan(0)
  })
})

describe('CippBecCorrelationGraph', () => {
  it('renders the native correlation graph (svg edges + labelled account) without crashing', () => {
    const { container } = renderWithProviders(
      <CippBecCorrelationGraph
        becData={SAMPLE_BEC.becData}
        windowDays={7}
        userData={SAMPLE_BEC.userData}
      />
    )
    // native SVG, not a graph library canvas
    expect(container.querySelector('svg')).not.toBeNull()
    // edges are drawn as paths
    expect(container.querySelectorAll('path').length).toBeGreaterThan(0)
    // the investigated account is labelled on its node
    expect(
      container.textContent.includes(SAMPLE_BEC.userData.userPrincipalName)
    ).toBe(true)
  })
})
