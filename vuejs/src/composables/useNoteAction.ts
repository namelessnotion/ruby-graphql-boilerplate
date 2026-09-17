import type { Ref } from 'vue'

import type { useMutation } from '@vue/apollo-composable'

// `completeNote`, `willnotdoNote`, and `archiveNote` differ only in which
// mutate function they call — one id-keyed action, reset-on-run, writing into
// the caller's error map under its own id so each note's failure is shown
// independently of any other note's.
export function useNoteAction<TData>(
  mutate: useMutation.MutateFunction<TData, { id: string | number }>,
  errors: Ref<Record<string, string>>,
) {
  async function run(id?: string) {
    if (!id) return

    errors.value = { ...errors.value, [id]: '' }
    try {
      await mutate({ variables: { id } })
    } catch (e) {
      errors.value = { ...errors.value, [id]: e instanceof Error ? e.message : 'Failed to update note.' }
    }
  }

  return { run }
}
