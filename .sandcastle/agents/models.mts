// The model catalog Sandcastle offers — every model an agent may be pointed at,
// with the reasoning efforts that model accepts and the minimum provider CLI
// version it needs.

export type RunEffort = "low" | "medium" | "high" | "xhigh" | "max";
export type Provider = "claude-code" | "codex";
export type VersionComponents = readonly [number, number, number];
export type ModelID =
  | "claude-opus-5"
  | "claude-fable-5"
  | "claude-opus-4-8"
  | "claude-sonnet-4-6"
  | "gpt-5.6-sol"
  | "gpt-5.5";

export interface MinimumVersion {
  components: VersionComponents;
  label: string;
}

export interface RunModel {
  id: ModelID;
  label: string;
  provider: Provider;
  providerLabel: string;
  description: string;
  efforts: readonly RunEffort[];
  minimumCliVersion?: MinimumVersion;
}

const COMMON_EFFORTS = ["low", "medium", "high", "xhigh"] as const;

export const RUN_MODELS: readonly RunModel[] = [
  {
    id: "claude-opus-5",
    label: "Claude Opus 5",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Current default · deepest reasoning available",
    efforts: [...COMMON_EFFORTS, "max"],
  },
  {
    id: "claude-fable-5",
    label: "Claude Fable 5",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Strong general-purpose coding",
    efforts: COMMON_EFFORTS,
  },
  {
    id: "claude-opus-4-8",
    label: "Claude Opus 4.8",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Deep reasoning for demanding changes",
    efforts: [...COMMON_EFFORTS, "max"],
  },
  {
    id: "claude-sonnet-4-6",
    label: "Claude Sonnet 4.6",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Fast, capable everyday engineering",
    efforts: COMMON_EFFORTS,
  },
  {
    id: "gpt-5.6-sol",
    label: "GPT-5.6 Sol",
    provider: "codex",
    providerLabel: "OpenAI · Codex",
    description: "OpenAI flagship · preview access may be required",
    efforts: COMMON_EFFORTS,
    minimumCliVersion: { components: [0, 144, 0], label: "0.144.0" },
  },
  {
    id: "gpt-5.5",
    label: "GPT-5.5",
    provider: "codex",
    providerLabel: "OpenAI · Codex",
    description: "Frontier coding with broad availability",
    efforts: COMMON_EFFORTS,
  },
];

/** Preferred effort when nothing is remembered. */
export const DEFAULT_EFFORT: RunEffort = "high";

export function findModel(id: string): RunModel | undefined {
  return RUN_MODELS.find((model) => model.id === id);
}
