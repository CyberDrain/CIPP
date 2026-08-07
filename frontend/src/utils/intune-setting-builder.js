// Builds a settings catalog settingInstance from a setting definition.
//
// Reading a policy only needs a definition's display name, which is all the catalog used to carry.
// Creating a setting needs to know what kind of instance to emit and what shape its value takes, so
// build/tools/Update-IntuneCollection.ps1 now keeps the definition's own @odata.type, its
// valueDefinition, its defaultOptionId and its applicability. Everything here reads those.
//
// A setting built without the right @odata.type is the exact failure Test-CIPPIntuneTemplate exists
// to catch: Intune rejects a policy whose settings do not declare their type. So the discriminators
// are written explicitly rather than inferred from the value, and anything this cannot build
// returns null instead of guessing.

const PREFIX = '#microsoft.graph.deviceManagementConfiguration'

export const SETTING_WRAPPER_TYPE = `${PREFIX}Setting`

// Definition type -> the instance type that configures it.
const INSTANCE_TYPE_BY_DEFINITION = {
  [`${PREFIX}ChoiceSettingDefinition`]: `${PREFIX}ChoiceSettingInstance`,
  [`${PREFIX}SimpleSettingDefinition`]: `${PREFIX}SimpleSettingInstance`,
  [`${PREFIX}ChoiceSettingCollectionDefinition`]: `${PREFIX}ChoiceSettingCollectionInstance`,
  [`${PREFIX}SimpleSettingCollectionDefinition`]: `${PREFIX}SimpleSettingCollectionInstance`,
  [`${PREFIX}SettingGroupDefinition`]: `${PREFIX}GroupSettingInstance`,
  [`${PREFIX}SettingGroupCollectionDefinition`]: `${PREFIX}GroupSettingCollectionInstance`,
}

// Value-definition type -> the value type a simple setting writes, and what an empty one holds.
// Intune distinguishes these by @odata.type alone; the JSON value of an integer and a string
// setting are otherwise indistinguishable once serialised.
const SIMPLE_VALUE_BY_DEFINITION = {
  [`${PREFIX}IntegerSettingValueDefinition`]: {
    type: `${PREFIX}IntegerSettingValue`,
    empty: 0,
  },
  [`${PREFIX}StringSettingValueDefinition`]: {
    type: `${PREFIX}StringSettingValue`,
    empty: '',
  },
  [`${PREFIX}SecretSettingValueDefinition`]: {
    type: `${PREFIX}SecretSettingValue`,
    empty: '',
  },
}

export const definitionInstanceType = (definition) =>
  INSTANCE_TYPE_BY_DEFINITION[definition?.['@odata.type']] ?? null

// True when this definition is something the editor can add on its own.
//
// Deliberately does not look at accessTypes. That field describes the access semantics of the
// underlying CSP, not whether Intune will accept the setting in a policy, and it reads 'none' for
// roughly three quarters of the catalog - including settings that are plainly configurable, such as
// every macOS global preference. Filtering on it hid most of Intune. visibility is the field that
// actually says whether the settings catalog surfaces a setting.
export const isAddableDefinition = (definition) => {
  if (!definitionInstanceType(definition)) return false
  if (definition.visibility && !/settingsCatalog/i.test(definition.visibility))
    return false
  return true
}

const simpleValueFor = (definition) => {
  const valueDefinitionType = definition?.valueDefinition?.['@odata.type']
  const spec = SIMPLE_VALUE_BY_DEFINITION[valueDefinitionType]

  // An unrecognised value definition is not guessable: writing a string where Intune wants an
  // integer is rejected at deploy time, which is precisely the surprise being designed out.
  if (!spec) return null

  // An integer setting whose range starts above zero is invalid at zero, so it starts at the bottom
  // of its own range rather than at a value Intune would reject the moment it was saved.
  const minimum = definition?.valueDefinition?.minimumValue
  const empty =
    spec.type === `${PREFIX}IntegerSettingValue` && typeof minimum === 'number'
      ? minimum
      : spec.empty

  // A string setting can demand a format - a PLMNID is /^[0-9]{5,6}$/ - and Intune rejects the whole
  // policy when the value does not match. There is no correct empty value for those, so the setting
  // is refused rather than seeded with one that cannot deploy. A group whose child is refused is
  // refused in turn, which keeps it out of the picker entirely.
  const definitionSchema = definition?.valueDefinition?.inputValidationSchema
  const minimumLength = definition?.valueDefinition?.minimumLength
  if (typeof empty === 'string') {
    if (typeof minimumLength === 'number' && empty.length < minimumLength) return null
    if (definitionSchema) {
      try {
        if (!new RegExp(definitionSchema).test(empty)) return null
      } catch {
        // An unparseable schema is not grounds to refuse a setting that may be perfectly valid.
      }
    }
  }

  const value = { '@odata.type': spec.type, value: empty }
  if (spec.type === `${PREFIX}SecretSettingValue`) {
    value.valueState = 'notEncrypted'
  }
  return value
}

// The option a new choice setting starts on: the one Intune marks as default, else the first.
const defaultOptionFor = (definition) => {
  const options = Array.isArray(definition?.options) ? definition.options : []
  if (options.length === 0) return null
  const preferred = options.find(
    (option) => option.id === definition.defaultOptionId
  )
  return preferred ?? options[0]
}

/**
 * Builds the settingInstance for a definition, or null when it cannot be built faithfully.
 * The caller wraps it with wrapSettingInstance to place it in a policy's settings array.
 */
export const requiredChildIds = (definition, optionId) => {
  // options is not always an array in the catalog, so it is checked rather than defaulted - a bare
  // ?? leaves a non-array in place and .find throws, which would take the picker down.
  const options = Array.isArray(definition?.options) ? definition.options : []
  const option = options.find((candidate) => candidate.id === optionId)
  return (option?.dependedOnBy ?? [])
    .filter((link) => link?.required)
    .map((link) => link?.dependedOnBy)
    .filter(Boolean)
}

const buildChildInstances = (definition, childDefinitionsById) =>
  childDefinitionIds(definition)
    .map((childId) =>
      buildSettingInstance(childDefinitionsById[childId], childDefinitionsById)
    )
    .filter(Boolean)

export const buildSettingInstance = (definition, childDefinitionsById = {}) => {
  const instanceType = definitionInstanceType(definition)
  if (!instanceType || !definition?.id) return null

  const instance = {
    '@odata.type': instanceType,
    settingDefinitionId: definition.id,
  }

  switch (instanceType) {
    case `${PREFIX}ChoiceSettingInstance`: {
      const option = defaultOptionFor(definition)
      if (!option) return null
      // children is always present, even when empty: Intune treats a missing children array on a
      // choice as malformed rather than as "no children".
      //
      // An option can also require settings of its own, and Intune rejects the policy if they are
      // absent. Nothing on those settings says they have a parent - the requirement is recorded
      // only here - so they are built from this side or not at all.
      instance.choiceSettingValue = {
        value: option.id,
        children: requiredChildIds(definition, option.id)
          .map((childId) =>
            buildSettingInstance(childDefinitionsById[childId], childDefinitionsById)
          )
          .filter(Boolean),
      }
      return instance
    }

    case `${PREFIX}SimpleSettingInstance`: {
      const value = simpleValueFor(definition)
      if (!value) return null
      instance.simpleSettingValue = value
      return instance
    }

    case `${PREFIX}ChoiceSettingCollectionInstance`: {
      const option = defaultOptionFor(definition)
      if (!option) return null
      instance.choiceSettingCollectionValue = [
        { value: option.id, children: [] },
      ]
      return instance
    }

    case `${PREFIX}SimpleSettingCollectionInstance`: {
      const value = simpleValueFor(definition)
      if (!value) return null
      // Starts with one entry so the collection is visible and editable rather than an empty box
      // with nothing to type into.
      instance.simpleSettingCollectionValue = [value]
      return instance
    }

    // Intune rejects a group with nothing in it - "SettingGroupValue should not be empty" - so a
    // group is only built when its children can be built too. Returning null instead of an empty
    // group is deliberate: a setting that cannot be constructed correctly must not reach the policy
    // at all, because the alternative is a template that saves cleanly and fails on deployment.
    case `${PREFIX}GroupSettingInstance`: {
      const children = buildChildInstances(definition, childDefinitionsById)
      if (children.length === 0) return null
      instance.groupSettingValue = { children }
      return instance
    }

    case `${PREFIX}GroupSettingCollectionInstance`: {
      const children = buildChildInstances(definition, childDefinitionsById)
      if (children.length === 0) return null
      instance.groupSettingCollectionValue = [{ children }]
      return instance
    }

    default:
      return null
  }
}

/** Wraps an instance as an entry in a policy's settings array. */
export const wrapSettingInstance = (instance) =>
  instance
    ? { '@odata.type': SETTING_WRAPPER_TYPE, settingInstance: instance }
    : null

/** Builds a complete settings array entry for a definition. Null when it cannot be built. */
export const buildSetting = (definition, childDefinitionsById = {}) =>
  wrapSettingInstance(buildSettingInstance(definition, childDefinitionsById))

/** True when the policy already configures this setting, so it is not offered or added twice. */
export const policyHasSetting = (policy, definitionId) =>
  (policy?.settings ?? []).some(
    (setting) => setting?.settingInstance?.settingDefinitionId === definitionId
  )

/**
 * An empty entry for a group collection, built from the group's child definitions so the row has
 * the fields Intune expects rather than being an empty object the editor cannot render.
 */
export const buildGroupCollectionEntry = (childDefinitions = []) => ({
  children: childDefinitions.map(buildSettingInstance).filter(Boolean),
})

/**
 * The settings a group definition contains, taken from the dependency links the catalog carries.
 * Intune models "this group holds these settings" as "these settings depend on this group", so the
 * children are read off dependedOnBy rather than from a child list, which does not exist.
 */
export const childDefinitionIds = (definition) => {
  // childIds states the membership directly. dependedOnBy describes the same relationship from the
  // other end and is the fallback for definitions that carry only the links.
  if (Array.isArray(definition?.childIds) && definition.childIds.length > 0) {
    return definition.childIds
  }
  const links = Array.isArray(definition?.dependedOnBy)
    ? definition.dependedOnBy
    : []
  return links.map((link) => link?.dependedOnBy).filter(Boolean)
}

/**
 * How many entries a collection may hold.
 *
 * Intune enforces these and rejects the entire policy when they are exceeded - the ASR rules group
 * allows exactly one row, and adding a second fails the deploy with a bounds error rather than
 * anything that names the setting helpfully. Returns Infinity for a maximum that is not stated, so
 * callers can compare without special-casing.
 */
export const collectionCountBounds = (definition) => ({
  minimum:
    typeof definition?.minimumCount === 'number' ? definition.minimumCount : 0,
  maximum:
    typeof definition?.maximumCount === 'number'
      ? definition.maximumCount
      : Infinity,
})

/** True when another row would exceed what Intune accepts for this collection. */
export const canAddCollectionEntry = (definition, currentCount) =>
  currentCount < collectionCountBounds(definition).maximum

/** True when removing a row would leave fewer entries than Intune requires. */
export const canRemoveCollectionEntry = (definition, currentCount) =>
  currentCount > collectionCountBounds(definition).minimum

/**
 * A copy of an existing group collection row with its values cleared.
 *
 * Used when a row has to be added and the group's children cannot be resolved from the catalog -
 * a template captured from a tenant always has a populated first row, and its shape is a more
 * reliable description of what Intune expects than anything that could be reconstructed. Structure,
 * @odata.types and settingDefinitionIds are kept exactly; only the values are reset.
 */
export const clearGroupRowValues = (row) => {
  const clearInstance = (instance) => {
    if (!instance || typeof instance !== 'object') return instance
    const copy = { ...instance }

    if (copy.simpleSettingValue) {
      copy.simpleSettingValue = {
        ...copy.simpleSettingValue,
        value:
          copy.simpleSettingValue['@odata.type'] ===
          `${PREFIX}IntegerSettingValue`
            ? 0
            : '',
      }
    }
    if (copy.simpleSettingCollectionValue) {
      copy.simpleSettingCollectionValue = (
        copy.simpleSettingCollectionValue ?? []
      ).map((entry) => ({
        ...entry,
        value:
          entry?.['@odata.type'] === `${PREFIX}IntegerSettingValue` ? 0 : '',
      }))
    }
    // A choice keeps its selected option: there is no such thing as an unset choice, and blanking it
    // would produce a value Intune does not recognise.
    if (copy.choiceSettingValue) {
      copy.choiceSettingValue = {
        ...copy.choiceSettingValue,
        children: (copy.choiceSettingValue.children ?? []).map(clearInstance),
      }
    }
    if (copy.groupSettingCollectionValue) {
      copy.groupSettingCollectionValue = (
        copy.groupSettingCollectionValue ?? []
      ).map((entry) => ({
        ...entry,
        children: (entry?.children ?? []).map(clearInstance),
      }))
    }
    return copy
  }

  return { ...row, children: (row?.children ?? []).map(clearInstance) }
}

/** True when this instance is a group collection, which is the only kind that has rows. */
export const isGroupCollectionInstance = (instance) =>
  instance?.['@odata.type'] === `${PREFIX}GroupSettingCollectionInstance`

/**
 * The name a policy's settings array is held under. Settings catalog policies use `settings`;
 * this exists so callers do not hard-code it in three places.
 */
export const SETTINGS_KEY = 'settings'
