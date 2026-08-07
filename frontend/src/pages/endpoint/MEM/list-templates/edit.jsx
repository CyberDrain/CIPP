import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
} from "@mui/material";
import { ChevronDownIcon, ChevronRightIcon, PlusIcon, TrashIcon } from "@heroicons/react/24/outline";
import { Grid } from "@mui/system";
import { useForm } from "react-hook-form";
import { useRouter } from "next/router";
import { Layout as DashboardLayout } from "../../../../layouts/index.js";
import CippFormPage from "../../../../components/CippFormPages/CippFormPage";
import CippFormSkeleton from "../../../../components/CippFormPages/CippFormSkeleton";
import { ApiGetCall, ApiPostCall } from "../../../../api/ApiCall";
import { CippApiResults } from "../../../../components/CippComponents/CippApiResults";
import CippFormComponent from "../../../../components/CippComponents/CippFormComponent";
import CippIntuneSettingsEditor from "../../../../components/CippComponents/CippIntuneSettingsEditor";
import { defaultValueForLeaf } from "../../../../utils/intune-template-leaves";
import { CippIntuneSettingPicker } from "../../../../components/CippComponents/CippIntuneSettingPicker";
import {
  canAddCollectionEntry,
  canRemoveCollectionEntry,
  isGroupCollectionInstance,
} from "../../../../utils/intune-setting-builder";
import { useIntunePolicyEditor } from "../../../../hooks/use-intune-policy-editor";

const EditIntuneTemplate = () => {
  const router = useRouter();
  const { id } = router.query;
  const formControl = useForm({ mode: "onChange" });

  const templateQuery = ApiGetCall({
    url: `/api/ListIntuneTemplates?id=${id}`,
    queryKey: `IntuneTemplate-${id}`,
    enabled: !!id,
  });

  const templateData = Array.isArray(templateQuery.data)
    ? templateQuery.data.find((t) => t.id === id || t.GUID === id)
    : templateQuery.data;

  // The stored policy, parsed once and never rebuilt. Everything the editor does is expressed as a
  // patch against this object, so properties no field is bound to survive the round-trip untouched.
  const originalPolicy = useMemo(() => {
    if (!templateData?.RAWJson) return null;
    try {
      return JSON.parse(templateData.RAWJson);
    } catch {
      return null;
    }
  }, [templateData?.RAWJson]);

  // The policy as it currently stands, which is the stored one until a setting is added or removed.
  // Structural edits change it; scalar edits stay in form state and are folded in on save. Keeping
  // the two separate is what lets a field keep its value while the settings around it move.
  const [workingPolicy, setWorkingPolicy] = useState(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);

  useEffect(() => {
    setWorkingPolicy(originalPolicy);
  }, [originalPolicy]);

  const policy = workingPolicy ?? originalPolicy;

  // The fields to render and the operations that change the policy's shape, shared with the add
  // screen so a setting configured while creating a template and the same setting configured here
  // produce identical JSON.
  const {
    structureRevision,
    getDefinition,
    definitionsLoading,
    definitionsError,
    leaves,
    isAdminTemplate,
    supportsStructuralEdits,
    foldValuesIntoPolicy,
    addSetting,
    removeSetting: handleRemoveSetting,
    addGroupRow: handleAddGroupRow,
    removeGroupRow: handleRemoveGroupRow,
  } = useIntunePolicyEditor({ policy, setPolicy: setWorkingPolicy, formControl });

  // Whether the stored name and description have been put on screen yet.
  //
  // This is tracked rather than inferred from the field being empty, because an empty field and an
  // unpopulated one look identical: react-hook-form reports a registered text input as '' , not
  // undefined, so falling back with ?? kept the empty string and the template opened with its name
  // blank. Reading the flag says which pass this is instead of guessing from the value.
  const populatedFromTemplate = useRef(false);

  useEffect(() => {
    // Deferred until the leaves are final. Resetting once the catalog arrives would otherwise
    // discard anything typed while it was still downloading.
    if (!templateData || definitionsLoading) return;

    // Adding or removing a setting rebuilds the leaves and runs this again. The name and description
    // are not part of that rebuild, so after the first pass they are carried across from the form -
    // otherwise renaming a template and then adding a setting would silently undo the rename.
    const current = formControl.getValues();
    const firstPass = !populatedFromTemplate.current;
    populatedFromTemplate.current = true;

    formControl.reset({
      displayName: firstPass
        ? templateData.Displayname ?? templateData.displayName ?? ""
        : current.displayName,
      description: firstPass
        ? templateData.Description ?? templateData.description ?? ""
        : current.description,
      settingValues: leaves.map(defaultValueForLeaf),
    });
  }, [templateData, leaves, definitionsLoading]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleAddSetting = useCallback(
    (definition) => {
      if (addSetting(definition)) setPickerOpen(false);
    },
    [addSetting]
  );


  const customDataFormatter = (values) => {
    const payload = {
      id,
      displayName: values.displayName,
      description: values.description,
    };

    // Omitted for policy shapes with no editable fields, which makes the backend keep the stored
    // RAWJson as-is rather than accept a body this editor cannot faithfully reproduce. A structural
    // change is sent even with no leaves, because removing the last setting is still an edit.
    const structurallyChanged = workingPolicy && workingPolicy !== originalPolicy;
    if (policy && (leaves.length > 0 || structurallyChanged)) {
      payload.parsedRAWJson = foldValuesIntoPolicy();
    }

    return payload;
  };

  const validateCall = ApiPostCall({});

  // Checks the edit as it currently stands, not the stored template, because the point is to find
  // out before saving whether what is about to be written still deploys. Sent as a JSON string so
  // the backend sees exactly the shape a stored template has.
  const handleValidate = () => {
    const values = formControl.getValues();
    validateCall.mutate({
      url: "/api/ExecValidateIntuneTemplate",
      data: {
        ID: id,
        RAWJson: JSON.stringify(foldValuesIntoPolicy()),
        TemplateType: templateData?.Type,
        displayName: values.displayName,
      },
    });
  };

  return (
    <CippFormPage
      title={templateData?.Displayname || templateData?.displayName || "Intune Template"}
      formControl={formControl}
      queryKey={[`IntuneTemplate-${id}`, "IntuneTemplates", "Available Endpoint Manager"]}
      backButtonTitle="Intune Templates"
      postUrl="/api/ExecEditTemplate?type=IntuneTemplate"
      // Adding or removing a setting changes the policy object rather than any field, so the form
      // stays pristine and Submit would stay disabled - and rebuilding the fields afterwards calls
      // reset(), which clears any dirtiness there had been. This says outright that there is
      // something to save.
      allowResubmit={structureRevision > 0}
      customDataformatter={customDataFormatter}
      formPageType="Edit"
    >
      <Stack spacing={3} sx={{ my: 2 }}>
        {templateQuery.isLoading ? (
          <CippFormSkeleton layout={[2, 1, 2, 2]} />
        ) : templateQuery.isError || !templateData ? (
          <Alert severity="error">Error loading template or template not found.</Alert>
        ) : (
          <>
            <Card variant="outlined">
              <CardHeader
                title="Template details"
                action={templateData.Type ? <Chip label={templateData.Type} size="small" /> : null}
                titleTypographyProps={{ variant: "h6" }}
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
                        required: { value: true, message: "A template name is required" },
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
                </Grid>
                <Stack spacing={1.5} sx={{ mt: 2 }}>
                  <Box>
                    <Button
                      variant="outlined"
                      size="small"
                      onClick={handleValidate}
                      disabled={validateCall.isPending || !originalPolicy}
                    >
                      {validateCall.isPending ? "Checking…" : "Validate template"}
                    </Button>
                    <Typography variant="caption" color="text.secondary" sx={{ ml: 2 }}>
                      Checks these changes for anything that would stop the template deploying.
                      Nothing is saved.
                    </Typography>
                  </Box>
                  <CippApiResults apiObject={validateCall} />
                </Stack>
              </CardContent>
            </Card>

            {supportsStructuralEdits && (
              <Card variant="outlined">
                <CardHeader
                  title="Configured settings"
                  subheader={`${(policy.settings ?? []).length} setting(s) in this policy`}
                  titleTypographyProps={{ variant: "h6" }}
                  // Collapsed by default: a real policy runs to dozens of settings, and this list
                  // exists to add and remove them rather than to be read top to bottom. Leaving it
                  // open pushed the fields people actually came to edit off the screen.
                  onClick={() => setSettingsOpen((open) => !open)}
                  sx={{ cursor: "pointer" }}
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
                        event.stopPropagation();
                        setPickerOpen(true);
                      }}
                    >
                      Add setting
                    </Button>
                  }
                />
                <Collapse in={settingsOpen} unmountOnExit>
                <CardContent>
                  {(policy.settings ?? []).length === 0 ? (
                    <Alert severity="warning">
                      This policy has no settings. It would deploy as an empty policy.
                    </Alert>
                  ) : (
                    <List dense disablePadding>
                      {(policy.settings ?? []).map((setting, index) => {
                        const definitionId = setting?.settingInstance?.settingDefinitionId;
                        const definition = getDefinition(definitionId);
                        return (
                          <ListItem
                            key={`${definitionId}-${index}`}
                            divider
                            secondaryAction={
                              <Tooltip title="Remove this setting from the policy">
                                <IconButton
                                  edge="end"
                                  size="small"
                                  color="error"
                                  onClick={() => handleRemoveSetting(index)}
                                >
                                  <TrashIcon style={{ width: 18, height: 18 }} />
                                </IconButton>
                              </Tooltip>
                            }
                          >
                            <ListItemText
                              primary={definition?.displayName || definitionId}
                              secondary={
                                <Box component="span" sx={{ display: "block" }}>
                                  <Typography
                                    variant="caption"
                                    color="text.secondary"
                                    component="span"
                                    sx={{ wordBreak: "break-all" }}
                                  >
                                    {definition?.categoryName || definitionId}
                                  </Typography>
                                  {isGroupCollectionInstance(setting?.settingInstance) && (
                                    <Box component="span" sx={{ display: "block", mt: 0.5 }}>
                                      <Stack
                                        direction="row"
                                        spacing={1}
                                        alignItems="center"
                                        component="span"
                                      >
                                        <Typography variant="caption" component="span">
                                          {
                                            (
                                              setting.settingInstance
                                                .groupSettingCollectionValue ?? []
                                            ).length
                                          }{" "}
                                          row(s)
                                        </Typography>
                                        <Button
                                          size="small"
                                          disabled={
                                            !canAddCollectionEntry(
                                              definition,
                                              (
                                                setting.settingInstance
                                                  .groupSettingCollectionValue ?? []
                                              ).length
                                            )
                                          }
                                          onClick={() => handleAddGroupRow(index)}
                                        >
                                          Add row
                                        </Button>
                                        {(
                                          setting.settingInstance.groupSettingCollectionValue ?? []
                                        ).map((_, rowIndex, allRows) => (
                                          <Button
                                            key={rowIndex}
                                            size="small"
                                            color="error"
                                            disabled={
                                              !canRemoveCollectionEntry(definition, allRows.length)
                                            }
                                            onClick={() => handleRemoveGroupRow(index, rowIndex)}
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
                        );
                      })}
                    </List>
                  )}
                </CardContent>
                </Collapse>
              </Card>
            )}

            <Card variant="outlined">
              <CardHeader title="Policy settings" titleTypographyProps={{ variant: "h6" }} />
              <CardContent>
                {!originalPolicy ? (
                  <Alert severity="error">
                    The stored policy for this template is not valid JSON and cannot be edited.
                  </Alert>
                ) : isAdminTemplate ? (
                  <Alert severity="info">
                    Administrative template settings are resolved against a tenant and cannot be
                    edited here. The name and description above can still be changed.
                  </Alert>
                ) : definitionsLoading ? (
                  <Box>
                    <Stack direction="row" spacing={1.5} alignItems="center">
                      <CircularProgress size={18} />
                      <Typography variant="body2" color="text.secondary">
                        Resolving setting names and available values…
                      </Typography>
                    </Stack>
                    <CippFormSkeleton layout={[2, 2, 2]} />
                  </Box>
                ) : (
                  <>
                    {definitionsError && (
                      <Alert severity="warning" sx={{ mb: 2 }}>
                        The Intune setting catalog could not be loaded, so settings are shown by
                        their definition ID and choices cannot be picked from a list. Values you
                        change are still saved correctly.
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
          </>
        )}
      </Stack>

      {supportsStructuralEdits && (
        <CippIntuneSettingPicker
          open={pickerOpen}
          onClose={() => setPickerOpen(false)}
          onAdd={handleAddSetting}
          platform={policy?.platforms}
          technology={policy?.technologies}
          existingIds={(policy?.settings ?? [])
            .map((setting) => setting?.settingInstance?.settingDefinitionId)
            .filter(Boolean)}
        />
      )}
    </CippFormPage>
  );
};

EditIntuneTemplate.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;

export default EditIntuneTemplate;
