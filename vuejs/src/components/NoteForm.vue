<script setup lang="ts">
import { useMutation } from '@vue/apollo-composable'
import { useRegle } from '@regle/core'
import { dateAfter, required, withMessage } from '@regle/rules'

import { graphql } from '@/gql'

const SaveNoteDocument = graphql(`
  mutation SaveNote($note: String!, $dueAt: ISO8601DateTime) {
    saveNote(note: $note, dueAt: $dueAt) {
      note {
        id
        note
        dueAt
        createdAt
      }
    }
  }
`)

interface NoteFormValues {
  note?: string
  dueAt?: string
}

const { r$ } = useRegle({} as NoteFormValues, {
  note: { required: withMessage(required, 'Note text is required.') },
  dueAt: {
    dateAfter: withMessage(
      dateAfter(() => new Date(), { allowEqual: false }),
      'Due date must be in the future.',
    ),
  },
})

const { mutate: saveNote, loading, error } = useMutation(SaveNoteDocument, {
  refetchQueries: ['Notes'],
})

async function onSubmit() {
  const { valid, data } = await r$.$validate()
  if (!valid) return

  try {
    await saveNote({
      variables: {
        note: data.note.trim(),
        dueAt: data.dueAt ? new Date(data.dueAt).toISOString() : undefined,
      },
    })
    r$.$reset({ toOriginalState: true })
  } catch {
    // Surfaced to the template via the reactive `error` ref from useMutation.
  }
}
</script>

<template>
  <div>
    <form
      class="flex flex-wrap items-start gap-2"
      @submit.prevent="onSubmit"
    >
      <div class="min-w-0 flex-1">
        <input
          v-model="r$.$value.note"
          type="text"
          placeholder="Add a note…"
          class="w-full rounded border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
        <p
          v-if="r$.note.$error"
          class="mt-1 text-xs text-red-600"
        >
          {{ r$.note.$errors[0] }}
        </p>
      </div>
      <div>
        <input
          v-model="r$.$value.dueAt"
          type="datetime-local"
          aria-label="Due date"
          class="rounded border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
        <p
          v-if="r$.dueAt.$error"
          class="mt-1 text-xs text-red-600"
        >
          {{ r$.dueAt.$errors[0] }}
        </p>
      </div>
      <button
        type="submit"
        :disabled="loading || r$.$invalid"
        class="rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-50"
      >
        {{ loading ? 'Saving…' : 'Add note' }}
      </button>
    </form>
    <p
      v-if="error"
      class="mt-2 text-sm text-red-600"
    >
      {{ error.message }}
    </p>
  </div>
</template>
