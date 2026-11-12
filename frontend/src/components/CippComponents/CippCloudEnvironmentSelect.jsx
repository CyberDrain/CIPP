import { ToggleButton, ToggleButtonGroup, Typography, Stack } from "@mui/material";
import { cloudEnvironmentOptions, getCloudEnvironment } from "../../utils/cloud-environments";

// Picks the Microsoft cloud a direct tenant is signed in to (redanthrax/CIPP#2).
export const CippCloudEnvironmentSelect = ({ value = "Commercial", onChange, disabled = false }) => {
  const selected = getCloudEnvironment(value);
  return (
    <Stack spacing={1}>
      <Typography variant="subtitle2">Tenant cloud</Typography>
      <ToggleButtonGroup
        exclusive
        size="small"
        color="primary"
        value={value}
        disabled={disabled}
        aria-label="Tenant cloud"
        onChange={(_event, next) => {
          if (next && onChange) onChange(next);
        }}
      >
        {cloudEnvironmentOptions.map((option) => (
          <ToggleButton key={option.value} value={option.value}>
            {option.label}
          </ToggleButton>
        ))}
      </ToggleButtonGroup>
      {selected && (
        <Typography variant="body2" sx={{ color: "text.secondary" }}>
          {selected.description}
        </Typography>
      )}
    </Stack>
  );
};

export default CippCloudEnvironmentSelect;
