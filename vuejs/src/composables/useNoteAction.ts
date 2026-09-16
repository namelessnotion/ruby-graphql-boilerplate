import type { Ref } from 'vue'

import type { useMutation } from '@vue/apollo-composable'

// `completeNote`, `willnotdoNote`, and `archiveNote` differ only in which
// mutate function they call — one id-keyed action, reset-on-run, sharing the
// caller's error ref so only the most recent action's failure is ever shown.
export function useNoteAction<TData>(
  mutate: useMutation.MutateFunction<TData, { id: string | number }>,
  error: Ref<string>,
) {
  async function run(id?: string) {
    if (!id) return

    error.value = ''
    try {
      await mutate({ variables: { id } })
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Failed to update note.'
    }
  }

  return { run }
}
