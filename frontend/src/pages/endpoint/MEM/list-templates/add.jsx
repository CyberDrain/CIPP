import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CardHeader,
  Chip,
  CircularProgress,
  Collapse,
  IconButton,
  List,
  ListItem,
  ListItemText,
  Stack,
  Tooltip,
  Typography,
} from '@mui/material'
import { Grid } from '@mui/system'
import {
  ChevronDownIcon,
  ChevronRightIcon,
  PlusIcon,
  TrashIcon,
} from '@heroicons/react/24/outline'
import { useForm } from 'react-hook-form'
import { useRouter } from 'next/router'
import { Layout as DashboardLayout } from '../../../../layouts/index.js'
import CippFormPage from '../../../../components/CippFormPages/CippFormPage'
import CippFormComponent from '../../../../components/CippComponents/CippFormComponent'
import CippIntuneSettingsEditor from '../../../../components/CippComponents/CippIntuneSettingsEditor'
import { CippApiResults } from '../../../../components/CippComponents/CippApiResults'
import { CippIntuneSettingPicker } from '../../../../components/CippComponents/CippIntuneSettingPicker'
import { ApiPostCall } from '../../../../api/ApiCall'
import { useIntunePolicyEditor } from '../../../../hooks/use-intune-policy-editor'
import {
  canAddCollectionEntry,
  canRemoveCollectionEntry,
  isGroupCollectionInstance,
} from '../../../../utils/intune-setting-builder'
import { defaultValueForLeaf } from '../../../../utils/intune-template-leaves'

// Creates a settings catalog template from nothing.
//
// Until now a template could only be captured from a policy already running in a tenant, so building
// one meant configuring it in Intune first and importing it afterwards.
//
// Settings are configured here, not just listed: a template whose settings all sit on their default
// values is rarely the template anyone wanted, and sending someone to a second screen to set them
// would make creating one a two-step job for no reason. The fields come from the same hook the edit
// screen uses, so a setting configured here and the same setting configured there produce identical
// JSON.

const PLATFORM_OPTIONS = [
  { label: 'Windows 10 and later', value: 'windows10' },
  { label: 'macOS', value: 'macOS' },
  { label: 'iOS/iPadOS', value: 'iOS' },
  { label: 'Android Enterprise', value: 'androidEnterprise' },
  { label: 'Android (AOSP)', value: 'aosp' },
  { label: 'Linux', value: 'linux' },
]

const TECHNOLOGY_OPTIONS = [
  { label: 'MDM', value: 'mdm' },
  { label: 'MDM + Security settings management', value: 'mdm,microsoftSense' },
  { label: 'Configuration Manager', value: 'configManager' },
  { label: 'Apple Remote Management', value: 'mdm,appleRemoteManagement' },
  { label: 'Linux MDM', value: 'linuxMdm' },
]

const AddIntuneTemplate = () => {
  const router = useRouter()
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: {
      displayName: '',
      description: '',
      platform: PLATFORM_OPTIONS[0],
      technology: TECHNOLOGY_OPTIONS[0],
    },
  })

  const [policy, setPolicy] = useState({ settings: [] })
  const [pickerOpen, setPickerOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)

  const platform = formControl.watch('platform')
  const technology = formControl.watch('technology')
  const platformValue = platform?.value ?? platform
  const technologyValue = technology?.value ?? technology

  const {
    structureRevision,
    getDefinition,
    definitionsLoading,
    definitionsError,
    leaves,
    foldValuesIntoPolicy,
    addSetting,
    removeSetting,
    addGroupRow,
    removeGroupRow,
  } = useIntunePolicyEditor({ policy, setPolicy, formControl })

  // Rebuilt whenever the settings change, the same way the edit screen does it. The template's own
  // fields are carried across rather than reset, or adding a setting would blank the name.
  useEffect(() => {
    if (definitionsLoading) return
    const current = formControl.getValues()
    formControl.reset({
      displayName: current.displayName ?? '',
      description: current.description ?? '',
      platform: current.platform ?? PLATFORM_OPTIONS[0],
      technology: current.technology ?? TECHNOLOGY_OPTIONS[0],
      settingValues: leaves.map(defaultValueForLeaf),
    })
  }, [leaves, definitionsLoading]) // eslint-disable-line react-hooks/exhaustive-deps

  const handleAddSetting = useCallback(
    (definition) => {
      if (addSetting(definition)) setPickerOpen(false)
    },
    [addSetting]
  )

  const existingIds = useMemo(
    () =>
      (policy.settings ?? [])
        .map((setting) => setting?.settingInstance?.settingDefinitionId)
        .filter(Boolean),
    [policy.settings]
  )

  // The policy exactly as it will be stored and later deployed, with the values currently on screen
  // folded in.
  const buildPolicy = useCallback(() => {
    const values = formControl.getValues()
    return {
      ...foldValuesIntoPolicy(),
      name: values.displayName,
      description: values.description ?? '',
      platforms: platformValue,
      technologies: technologyValue,
    }
  }, [formControl, foldValuesIntoPolicy, platformValue, technologyValue])

  const validateCall = ApiPostCall({})

  const handleValidate = () => {
    validateCall.mutate({
      url: '/api/ExecValidateIntuneTemplate',
      data: {
        RAWJson: JSON.stringify(buildPolicy()),
        TemplateType: 'Catalog',
        displayName: formControl.getValues().displayName,
      },
    })
  }

  const customDataFormatter = (values) => ({
    displayName: values.displayName,
    description: values.description,
    TemplateType: 'Catalog',
    RawJSON: JSON.stringify(buildPolicy()),
  })

  // AddIntuneTemplate returns the GUID it stored, so the template just created can be opened rather
  // than hunted for in the list.
  const handleSubmitResult = (result) => {
    const guid = result?.GUID ?? result?.guid
    if (guid) {
      router.push(`/endpoint/MEM/list-templates/edit?id=${guid}`)
    }
  }

  const settings = policy.settings ?? []

  return (
    <CippFormPage
      title="New Endpoint Manager Template"
      formControl={formControl}
      queryKey={['IntuneTemplates', 'Available Endpoint Manager']}
      backButtonTitle="Intune Templates"
      postUrl="/api/AddIntuneTemplate"
      // Adding a setting changes the policy object rather than any field, so the form would
      // otherwise stay pristine and leave Submit disabled.
      allowResubmit={structureRevision > 0}
      customDataformatter={customDataFormatter}
      onSubmitResult={handleSubmitResult}
      formPageType="Add"
    >
      <Stack spacing={3} sx={{ my: 2 }}>
        <Card variant="outlined">
          <CardHeader
            title="Template details"
            titleTypographyProps={{ variant: 'h6' }}
          />
          <CardContent>
            <Grid container spacing={2}>
              <Grid size={{ xs: 12, md: 6 }}>
                <CippFormComponent
                  type="textField"
                  label="Template Name"
                  name="displayName"
                  formControl={formControl}
                  validators={{
                    required: {
                      value: true,
                      message: 'A template name is required',
                    },
                  }}
                />
              </Grid>
              <Grid size={{ xs: 12, md: 6 }}>
                <CippFormComponent
                  type="textField"
                  label="Description"
                  name="description"
                  formControl={formControl}
                />
              </Grid>
              <Grid size={{ xs: 12, md: 6 }}>
                <CippFormComponent
                  type="autoComplete"
                  label="Platform"
                  name="platform"
                  multiple={false}
                  creatable={false}
                  options={PLATFORM_OPTIONS}
                  formControl={formControl}
                  validators={{
                    validate: (value) =>
                      !!(value?.value ?? value) || 'Pick a platform',
                  }}
                />
              </Grid>
              <Grid size={{ xs: 12, md: 6 }}>
                <CippFormComponent
                  type="autoComplete"
                  label="Technology"
                  name="technology"
                  multiple={false}
                  creatable={false}
                  options={TECHNOLOGY_OPTIONS}
                  formControl={formControl}
                  validators={{
                    validate: (value) =>
                      !!(value?.value ?? value) || 'Pick a technology',
                  }}
                />
              </Grid>
            </Grid>

            <Stack spacing={1.5} sx={{ mt: 2 }}>
              <Box>
                <Button
                  variant="outlined"
                  size="small"
                  onClick={handleValidate}
                  disabled={validateCall.isPending || settings.length === 0}
                >
                  {validateCall.isPending ? 'Checking…' : 'Validate template'}
                </Button>
                <Typography
                  variant="caption"
                  color="text.secondary"
                  sx={{ ml: 2 }}
                >
                  Checks this template for anything that would stop it
                  deploying. Nothing is saved.
                </Typography>
              </Box>
              <CippApiResults apiObject={validateCall} />
            </Stack>
          </CardContent>
        </Card>

        <Card variant="outlined">
          <CardHeader
            title="Configured settings"
            subheader={`${settings.length} setting(s) in this template`}
            titleTypographyProps={{ variant: 'h6' }}
            // Collapsed by default, matching the edit screen: this list is for adding and removing
            // settings, not for reading, and a real policy runs to dozens of them.
            onClick={() => setSettingsOpen((open) => !open)}
            sx={{ cursor: 'pointer' }}
            avatar={
              settingsOpen ? (
                <ChevronDownIcon style={{ width: 18, height: 18 }} />
              ) : (
                <ChevronRightIcon style={{ width: 18, height: 18 }} />
              )
            }
            action={
              <Button
                variant="outlined"
                size="small"
                startIcon={<PlusIcon style={{ width: 16, height: 16 }} />}
                onClick={(event) => {
                  event.stopPropagation()
                  setPickerOpen(true)
                }}
                disabled={!platformValue}
              >
                Add setting
              </Button>
            }
          />
          <Collapse in={settingsOpen} unmountOnExit>
            <CardContent>
              {settings.length === 0 ? (
                <Alert severity="info">
                  No settings yet. Use “Add setting” to search the{' '}
                  {platformValue || 'Intune'} setting catalog. A template with
                  no settings deploys an empty policy.
                </Alert>
              ) : (
                <List dense disablePadding>
                  {settings.map((setting, index) => {
                    const definitionId =
                      setting?.settingInstance?.settingDefinitionId
                    const definition = getDefinition(definitionId)
                    const rows =
                      setting?.settingInstance?.groupSettingCollectionValue ??
                      []
                    return (
                      <ListItem
                        key={`${definitionId}-${index}`}
                        divider
                        secondaryAction={
                          <Tooltip title="Remove this setting">
                            <IconButton
                              edge="end"
                              size="small"
                              color="error"
                              onClick={() => removeSetting(index)}
                            >
                              <TrashIcon style={{ width: 18, height: 18 }} />
                            </IconButton>
                          </Tooltip>
                        }
                      >
                        <ListItemText
                          primary={definition?.displayName || definitionId}
                          secondary={
                            <Box component="span" sx={{ display: 'block' }}>
                              <Typography
                                variant="caption"
                                color="text.secondary"
                                component="span"
                                sx={{ wordBreak: 'break-all' }}
                              >
                                {definition?.categoryName || definitionId}
                              </Typography>
                              {isGroupCollectionInstance(
                                setting?.settingInstance
                              ) && (
                                <Box
                                  component="span"
                                  sx={{ display: 'block', mt: 0.5 }}
                                >
                                  <Stack
                                    direction="row"
                                    spacing={1}
                                    alignItems="center"
                                    component="span"
                                  >
                                    <Typography
                                      variant="caption"
                                      component="span"
                                    >
                                      {rows.length} row(s)
                                    </Typography>
                                    <Button
                                      size="small"
                                      disabled={
                                        !canAddCollectionEntry(
                                          definition,
                                          rows.length
                                        )
                                      }
                                      onClick={() => addGroupRow(index)}
                                    >
                                      Add row
                                    </Button>
                                    {rows.map((_, rowIndex) => (
                                      <Button
                                        key={rowIndex}
                                        size="small"
                                        color="error"
                                        disabled={
                                          !canRemoveCollectionEntry(
                                            definition,
                                            rows.length
                                          )
                                        }
                                        onClick={() =>
                                          removeGroupRow(index, rowIndex)
                                        }
                                      >
                                        Remove row {rowIndex + 1}
                                      </Button>
                                    ))}
                                  </Stack>
                                </Box>
                              )}
                            </Box>
                          }
                        />
                      </ListItem>
                    )
                  })}
                </List>
              )}
            </CardContent>
          </Collapse>
        </Card>

        {settings.length > 0 && (
          <Card variant="outlined">
            <CardHeader
              title="Setting values"
              titleTypographyProps={{ variant: 'h6' }}
            />
            <CardContent>
              {definitionsLoading ? (
                <Stack direction="row" spacing={1.5} alignItems="center">
                  <CircularProgress size={18} />
                  <Typography variant="body2" color="text.secondary">
                    Resolving setting names and available values…
                  </Typography>
                </Stack>
              ) : (
                <>
                  {definitionsError && (
                    <Alert severity="warning" sx={{ mb: 2 }}>
                      The Intune setting catalog could not be loaded, so
                      settings are shown by their definition ID and choices
                      cannot be picked from a list. Values you change are still
                      saved correctly.
                    </Alert>
                  )}
                  <CippIntuneSettingsEditor
                    leaves={leaves}
                    formControl={formControl}
                    fieldPrefix="settingValues"
                  />
                </>
              )}
            </CardContent>
          </Card>
        )}
      </Stack>

      <CippIntuneSettingPicker
        open={pickerOpen}
        onClose={() => setPickerOpen(false)}
        onAdd={handleAddSetting}
        platform={platformValue}
        technology={technologyValue}
        existingIds={existingIds}
      />
    </CippFormPage>
  )
}

AddIntuneTemplate.getLayout = (page) => (
  <DashboardLayout>{page}</DashboardLayout>
)

export default AddIntuneTemplate
