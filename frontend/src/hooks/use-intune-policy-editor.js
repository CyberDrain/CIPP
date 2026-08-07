import { useCallback, useMemo, useState } from 'react'
import { useIntuneDefinitionResolver } from '../components/CippComponents/CippIntuneSettingsEditor'
import {
  applyIntuneSettingEdits,
  buildIntunePropertyLeaves,
  buildIntuneSettingLeaves,
} from '../utils/intune-template-leaves'
import { getCippTranslation } from '../utils/get-cipp-translation'
import { fetchIntuneDefinition } from './use-intune-collection'
import {
  buildGroupCollectionEntry,
  buildSetting,
  canAddCollectionEntry,
  childDefinitionIds,
  clearGroupRowValues,
  isGroupCollectionInstance,
  policyHasSetting,
} from '../utils/intune-setting-builder'

// Everything both the add and the edit screen need to work on a policy: the fields to render, and
// the operations that change the policy's shape.
//
// It lives here rather than on either page because the two screens have to behave identically. A
// setting added while creating a template and a setting added while editing one must produce the
// same JSON, or a template would deploy differently depending on which screen made it.
//
// The split between structure and values is the important part. Values live in form state and are
// addressed by their position in the leaf list; structure lives in the policy object. Adding or
// removing a setting moves every field after it, so every structural change folds the current form
// values back into the policy first - otherwise the values would be reapplied to the wrong fields.
export const useIntunePolicyEditor = ({ policy, setPolicy, formControl }) => {
  // Counts structural edits, so the page can tell the form something changed.
  //
  // Adding or removing a setting changes the policy object, not any field, so react-hook-form sees
  // nothing - and the submit button is gated on the form being dirty. Worse, rebuilding the fields
  // afterwards calls reset(), which marks the form clean, so adding a setting actively cleared any
  // dirtiness there had been. The page mirrors this into a form field to make the change visible.
  const [structureRevision, setStructureRevision] = useState(0)
  const noteStructuralChange = useCallback(
    () => setStructureRevision((n) => n + 1),
    []
  )

  const {
    getDefinition,
    isLoading: definitionsLoading,
    isError: definitionsError,
  } = useIntuneDefinitionResolver(policy)

  // Administrative templates carry their settings as definition references resolved against a
  // tenant, which cannot be presented as fields.
  const isAdminTemplate =
    Array.isArray(policy?.added) || Array.isArray(policy?.definitionValues)
  const isSettingTree =
    Array.isArray(policy?.settings) || Array.isArray(policy?.omaSettings)

  // Only a settings catalog policy has a settings array to add to or remove from. A classic device
  // configuration is a fixed set of properties, so there is nothing there to add.
  const supportsStructuralEdits = Array.isArray(policy?.settings)

  const leaves = useMemo(() => {
    if (!policy || isAdminTemplate || definitionsLoading) return []
    return isSettingTree
      ? buildIntuneSettingLeaves(policy, getDefinition)
      : buildIntunePropertyLeaves(policy, getCippTranslation)
  }, [
    policy,
    getDefinition,
    isAdminTemplate,
    isSettingTree,
    definitionsLoading,
  ])

  const foldValuesIntoPolicy = useCallback(() => {
    if (!policy || leaves.length === 0) return policy
    return applyIntuneSettingEdits(
      policy,
      leaves,
      formControl.getValues().settingValues
    )
  }, [policy, leaves, formControl])

  const addSetting = useCallback(
    (definition, childDefinitionsById = {}) => {
      const setting = buildSetting(definition, childDefinitionsById)
      if (!setting) return false

      const folded = foldValuesIntoPolicy()
      if (policyHasSetting(folded, definition.id)) return false

      setPolicy({ ...folded, settings: [...(folded.settings ?? []), setting] })
      noteStructuralChange()
      return true
    },
    [foldValuesIntoPolicy, setPolicy, noteStructuralChange]
  )

  const removeSetting = useCallback(
    (settingIndex) => {
      const folded = foldValuesIntoPolicy()
      setPolicy({
        ...folded,
        settings: (folded.settings ?? []).filter(
          (_, index) => index !== settingIndex
        ),
      })
      noteStructuralChange()
    },
    [foldValuesIntoPolicy, setPolicy, noteStructuralChange]
  )

  // Group collections are the repeating blocks Intune shows as a table. They produce no leaf of
  // their own, so the field editor can change what is in a row but cannot add or remove one.
  const addGroupRow = useCallback(
    async (settingIndex) => {
      const folded = foldValuesIntoPolicy()
      const instance = folded?.settings?.[settingIndex]?.settingInstance
      if (!isGroupCollectionInstance(instance)) return

      const rows = instance.groupSettingCollectionValue ?? []
      const groupDefinition = await fetchIntuneDefinition(
        instance.settingDefinitionId
      )

      // Intune rejects the whole policy when a collection exceeds its bound, naming only the group,
      // so the row is refused here rather than written and discovered on deploy.
      if (!canAddCollectionEntry(groupDefinition, rows.length)) return

      let newRow = null
      const childIds = childDefinitionIds(groupDefinition)
      if (childIds.length > 0) {
        const childDefinitions = (
          await Promise.all(
            childIds.map((childId) => fetchIntuneDefinition(childId))
          )
        ).filter(Boolean)
        const built = buildGroupCollectionEntry(childDefinitions)
        if (built.children.length > 0) newRow = built
      }
      if (!newRow) {
        newRow =
          rows.length > 0 ? clearGroupRowValues(rows[0]) : { children: [] }
      }

      setPolicy({
        ...folded,
        settings: folded.settings.map((setting, index) =>
          index === settingIndex
            ? {
                ...setting,
                settingInstance: {
                  ...setting.settingInstance,
                  groupSettingCollectionValue: [...rows, newRow],
                },
              }
            : setting
        ),
      })
      noteStructuralChange()
    },
    [foldValuesIntoPolicy, setPolicy, noteStructuralChange]
  )

  const removeGroupRow = useCallback(
    (settingIndex, rowIndex) => {
      const folded = foldValuesIntoPolicy()
      const instance = folded?.settings?.[settingIndex]?.settingInstance
      if (!isGroupCollectionInstance(instance)) return

      setPolicy({
        ...folded,
        settings: folded.settings.map((setting, index) =>
          index === settingIndex
            ? {
                ...setting,
                settingInstance: {
                  ...setting.settingInstance,
                  groupSettingCollectionValue: (
                    setting.settingInstance.groupSettingCollectionValue ?? []
                  ).filter((_, i) => i !== rowIndex),
                },
              }
            : setting
        ),
      })
      noteStructuralChange()
    },
    [foldValuesIntoPolicy, setPolicy, noteStructuralChange]
  )

  return {
    structureRevision,
    getDefinition,
    definitionsLoading,
    definitionsError,
    leaves,
    isAdminTemplate,
    isSettingTree,
    supportsStructuralEdits,
    foldValuesIntoPolicy,
    addSetting,
    removeSetting,
    addGroupRow,
    removeGroupRow,
  }
}
