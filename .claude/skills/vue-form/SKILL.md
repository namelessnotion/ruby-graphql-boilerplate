---
name: vue-form
description: Add or change a form field in `vuejs/` with Regle client-side validation — state shape, rule declaration, error display, submit gating, and returning the form to pristine. Use when adding a field to an existing form, building a new form component, or adding or changing a validation rule on an existing field.
---

# Vue form field

`src/components/NoteForm.vue` is the working reference for every pattern below.
Read it first and follow its shape; this file carries the reasons behind that
shape, which the component itself cannot show you.

One distinction drives the whole document: a **pristine** field shows no error,
a **dirty** field shows its first error. Regle runs `autoDirty` by default, so
a field goes dirty the moment `v-model` changes it — no `$touch()` wiring, and
no blur handlers.

## Step 1 — shape the state

Declare an interface with one **optional** property per field, and hand
`useRegle` an empty object cast to it:

```ts
interface NoteFormValues {
  note?: string
  dueAt?: string
}

const { r$ } = useRegle({} as NoteFormValues, { /* rules */ })
```

Optional properties are what let `$validate()` hand back `data.note` as a
plain `string` for the fields carrying `required`, while fields without it stay
possibly-undefined. Seeding concrete `''` values instead costs that inference.

Done when the interface has one optional property per field, every one a
`string` (an `<input>` binds a string even when `type` is `number` or
`datetime-local`).

## Step 2 — declare the rules

Every rule is wrapped in `withMessage` so the copy is yours rather than the
library's default:

```ts
note: { required: withMessage(required, 'Note text is required.') },
dueAt: {
  dateAfter: withMessage(
    dateAfter(() => new Date(), { allowEqual: false }),
    'Due date must be in the future.',
  ),
},
```

Three behaviours of the rule set that the call site does not reveal:

- **`required` trims before testing.** It alone rejects `'   '`, so content
  validation is one rule, not two.
- **Every other rule passes on an empty value.** An optional field carries just
  its own rule and stays optional; `required` is the only thing that makes a
  field mandatory.
- **A rule parameter takes a getter.** `dateAfter(() => new Date())` re-reads
  the clock on each run, where `dateAfter(new Date())` freezes the comparison at
  component setup. Pass the getter for anything derived from now.

For the built-in rule names, read the export list rather than guessing:
`grep -n "^export " node_modules/@regle/rules/dist/regle-rules.d.ts`. Each rule
has a JSDoc block above its `declare const` in that file carrying its
parameters and an example. When nothing fits, an inline
`withMessage((value) => boolean, 'message')` is a complete rule.

Done when each field's rules are declared and every one carries a message.

## Step 3 — wire the template

Bind `v-model` to `r$.$value.<field>`, and give each field its own error line
driven by `$error`, the dirty-aware flag:

```vue
<input v-model="r$.$value.note" type="text">
<p v-if="r$.note.$error">{{ r$.note.$errors[0] }}</p>
```

`$error` is `$dirty && !$pending && $invalid` — it keeps a pristine form silent.
The submit button takes the form-wide `$invalid` instead, so it is disabled from
first paint:

```vue
<button type="submit" :disabled="loading || r$.$invalid">
```

Done when every field renders its own message and the button is bound to
`r$.$invalid`.

## Step 4 — gate the submit, then return to pristine

```ts
async function onSubmit() {
  const { valid, data } = await r$.$validate()
  if (!valid) return

  try {
    await saveNote({ variables: { note: data.note.trim() } })
    r$.$reset({ toOriginalState: true })
  } catch {
    // Surfaced to the template via the reactive `error` ref from useMutation.
  }
}
```

`$validate()` is async and destructures to `{ valid, data }`. It also marks
every field dirty, which is what surfaces the messages on a rejected submit.

That dirty-marking is why success ends on `$reset({ toOriginalState: true })`.
Assigning `r$.$value.note = ''` clears the input but leaves the field dirty, so
`required` re-fails against the now-empty value and the error appears under a
form the user just submitted successfully. `$reset` restores the values **and**
the pristine flags in one call; `toOriginalState` returns them to the object
passed to `useRegle` rather than to whatever was last typed.

Done when an invalid submit returns early with messages visible, and a
successful one leaves the form pristine.

## Step 5 — test the rules

Mount with `MockLink` as the sibling specs do, and register **no mock** for the
cases that must never reach the network — an unexpected request then fails the
test by itself. Drive inputs by type selector (`input[type="text"]`,
`input[type="datetime-local"]`).

Cover, per rule, the failing case asserting the message text, plus one success
path asserting the form came back pristine:

```ts
expect(wrapper.text()).toContain('Due date must be in the future.')
expect(wrapper.text()).not.toContain('Note text is required.') // after success
```

`datetime-local` carries no timezone, so `new Date('2099-06-01T10:00')` resolves
against the runner's local clock. Compute the expected ISO from the same string
the test types, keeping the assertion true in every timezone:

```ts
const dueAtLocal = '2099-06-01T10:00'
const dueAtIso = new Date(dueAtLocal).toISOString()
```

Date-only strings parse as UTC instead, so this only bites the fields carrying a
time. Keep fixture dates far future (`2099`) or far past (`2020`) so a rule
comparing against now stays decided.

Done when every rule has a failing-case test naming its message, and the
success path asserts pristine.

## Step 6 — verify

Follow `CLAUDE.md`'s TDD and required-checks rules for the Vue app — that file
is the source of truth and is already loaded.
