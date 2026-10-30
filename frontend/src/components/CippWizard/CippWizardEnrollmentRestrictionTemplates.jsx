import { Alert, Stack } from '@mui/material'
import { Grid } from '@mui/system'
import { useWatch } from 'react-hook-form'
import CippWizardStepButtons from './CippWizardStepButtons'
import CippFormComponent from '../CippComponents/CippFormComponent'

const platformLabels = { android: 'Android', ios: 'iOS/iPadOS', macOS: 'macOS', windows: 'Windows' }

// Picks the saved template to deploy. AddEnrollmentRestriction loads the template itself, so
// the wizard sends only the selection and the tenants.
export const CippWizardEnrollmentRestrictionTemplates = (props) => {
  const { postUrl, formControl, onPreviousStep, onNextStep, currentStep } = props
  const selected = useWatch({ control: formControl.control, name: 'TemplateList' })
  const template = selected?.addedFields

  return (
    <Stack spacing={3}>
      <Grid container spacing={3}>
        <Grid size={12}>
          <CippFormComponent
            type="autoComplete"
            name="TemplateList"
            label="Choose a template"
            formControl={formControl}
            creatable={false}
            multiple={false}
            validators={{ required: 'Choose a template' }}
            api={{
              excludeTenantFilter: true,
              url: '/api/ListEnrollmentRestrictionTemplates',
              queryKey: 'ListEnrollmentRestrictionTemplates',
              labelField: (option) =>
                `${option.displayName} (${platformLabels[option.platform] ?? option.platform})`,
              valueField: 'GUID',
              addedField: {
                platform: 'platform',
                priority: 'priority',
                AssignTo: 'AssignTo',
                customGroup: 'customGroup',
              },
              showRefresh: true,
            }}
          />
        </Grid>
        {template && (
          <Grid size={12}>
            <Alert severity="info">
              {template.priority
                ? `Created restrictions get priority ${template.priority}. `
                : 'Created restrictions are added below each tenant’s existing ones. '}
              {template.AssignTo === 'customGroup'
                ? `Assigned to groups matching: ${template.customGroup}. In a tenant with no matching group the restriction is created but not assigned, and the result says so.`
                : template.AssignTo === 'allLicensedUsers'
                  ? 'Assigned to all users.'
                  : 'Not assigned.'}{' '}
              An existing restriction with the same name and platform is updated.
            </Alert>
          </Grid>
        )}
      </Grid>
      <CippWizardStepButtons
        postUrl={postUrl}
        currentStep={currentStep}
        onPreviousStep={onPreviousStep}
        onNextStep={onNextStep}
        formControl={formControl}
      />
    </Stack>
  )
}
