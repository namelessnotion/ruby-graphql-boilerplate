<script setup lang="ts">
import { useMutation } from '@vue/apollo-composable'
import { ref } from 'vue'

import { graphql } from '@/gql'

const SaveNoteDocument = graphql(`
  mutation SaveNote($note: String!) {
    saveNote(note: $note) {
      note {
        id
        note
        createdAt
      }
    }
  }
`)

const noteText = ref('')
const { mutate: saveNote, loading, error } = useMutation(SaveNoteDocument, {
  refetchQueries: ['Notes'],
})

async function onSubmit() {
  const text = noteText.value.trim()
  if (!text) return

  try {
    await saveNote({ variables: { note: text } })
    noteText.value = ''
  } catch {
    // Surfaced to the template via the reactive `error` ref from useMutation.
  }
}
</script>

<template>
  <div>
    <form class="flex gap-2" @submit.prevent="onSubmit">
      <input
        v-model="noteText"
        type="text"
        placeholder="Add a note…"
        class="flex-1 rounded border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
      />
      <button
        type="submit"
        :disabled="loading || !noteText.trim()"
        class="rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-50"
      >
        {{ loading ? 'Saving…' : 'Add note' }}
      </button>
    </form>
    <p v-if="error" class="mt-2 text-sm text-red-600">{{ error.message }}</p>
  </div>
</template>
