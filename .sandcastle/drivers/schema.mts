// A Standard Schema validator, hand-rolled, so that `.sandcastle` keeps exactly
// two dependencies.
//
// **There is no zod.** The interface Sandcastle asks for is one method behind
// one key, and both schemas that use it are two fields — so a validator costs
// less to write than a dependency costs to carry in a package deliberately kept
// this small. One validator, two uses: `<plan>` and `<merge>`.
//
// What `Output.object({ schema, maxRetries })` does with this: it extracts the
// tag from the agent's stdout, JSON-parses it fence-aware, and calls `validate`.
// On `issues` it resumes that agent's own session with a token-efficient
// description and asks for a corrected tag. So a reader below is not just a type
// guard — **its message is what the agent is told to fix**, which is why every
// one of them names the field it refused.
//
// And what it deliberately cannot do: **a schema here never knows the ready
// set.** The runner composes the plan schema once per wave, so a schema that
// closed over that wave's ready items would get semantic retries free from
// `maxRetries` — and "an invalid plan falls back with no semantic retry" would
// quietly become aspirational. Shape is this module's; semantics are
// `planner.mts`'s, applied after the dispatch returns.

/** One reason a value was refused, in the shape Standard Schema names. */
export interface ValidationIssue {
  readonly message: string;
}

export type Validation<T> =
  | { readonly value: T }
  | { readonly issues: readonly ValidationIssue[] };

/**
 * The subset of `StandardSchemaV1` Sandcastle actually calls. Structural, so it
 * satisfies the library's own generic without importing its types — which keeps
 * this module a leaf and keeps a Sandcastle type out of one more file.
 */
export interface Validator<T> {
  readonly "~standard": {
    readonly version: 1;
    readonly vendor: string;
    readonly validate: (value: unknown) => Validation<T>;
  };
}

/**
 * Wrap a reader as a validator.
 *
 * The reader throws to refuse, which is what lets the readers below compose as
 * plain expressions rather than threading a result type through every field.
 * The throw stops here: Sandcastle needs `issues` to resume the agent, and an
 * exception at this point would end the run instead of asking for a fix.
 */
export function validator<T>(vendor: string, read: (value: unknown) => T): Validator<T> {
  return {
    "~standard": {
      version: 1,
      vendor,
      validate: (value) => {
        try {
          return { value: read(value) };
        } catch (error) {
          return { issues: [{ message: error instanceof Error ? error.message : String(error) }] };
        }
      },
    },
  };
}

function refuse(field: string, wanted: string, value: unknown): never {
  throw new Error(`\`${field}\` must be ${wanted}, and was ${JSON.stringify(value) ?? "undefined"}`);
}

/** The whole block, before any field is read. */
export function fields(value: unknown, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    refuse(field, "an object", value);
  }
  return value as Record<string, unknown>;
}

export function readString(value: unknown, field: string): string {
  if (typeof value !== "string") refuse(field, "a string", value);
  return value;
}

export function readBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") refuse(field, "true or false", value);
  return value;
}

/**
 * An issue number. Integers only: every number crossing this seam is an issue
 * number, and `12.5` is not one — it is a model rounding something it should
 * have copied.
 */
export function readIssueNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) refuse(field, "an issue number", value);
  return value;
}

export function readArray<T>(
  value: unknown,
  field: string,
  item: (element: unknown, field: string) => T,
): readonly T[] {
  if (!Array.isArray(value)) refuse(field, "an array", value);
  return value.map((element, index) => item(element, `${field}[${index}]`));
}
