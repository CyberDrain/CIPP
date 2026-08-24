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
