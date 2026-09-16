<script setup lang="ts">
import { useMutation, useQuery } from '@vue/apollo-composable'
import { ref } from 'vue'

import { graphql } from '@/gql'

const NotesDocument = graphql(`
  query Notes {
    notes {
      edges {
        node {
          id
          note
          state
          dueAt
          createdAt
        }
      }
    }
  }
`)

const CompleteNoteDocument = graphql(`
  mutation CompleteNote($id: ID!) {
    completeNote(id: $id) {
      note {
        id
        state
      }
    }
  }
`)

const WillnotdoNoteDocument = graphql(`
  mutation WillnotdoNote($id: ID!) {
    willnotdoNote(id: $id) {
      note {
        id
        state
      }
    }
  }
`)

const ArchiveNoteDocument = graphql(`
  mutation ArchiveNote($id: ID!) {
    archiveNote(id: $id) {
      note {
        id
        state
      }
    }
  }
`)

const { result, loading, error } = useQuery(NotesDocument)

// `completeNote` and `willnotdoNote` need no cache handling: both return the note's
// id and state, so Apollo merges the new state into the normalized Note entity and
// every query holding a reference to it re-renders.
const { mutate: completeNote } = useMutation(CompleteNoteDocument)
const { mutate: willnotdoNote } = useMutation(WillnotdoNoteDocument)

// Archiving soft-deletes the note, so it drops out of the Notes query. Normalization
// cannot infer that, so drop its edge from the cached list and evict the entity.
const { mutate: archiveNote } = useMutation(ArchiveNoteDocument, {
  update(cache, { data }) {
    const archivedId = data?.archiveNote?.note.id
    if (!archivedId) return

    cache.updateQuery({ query: NotesDocument }, (cached) => {
      if (!cached) return cached

      const edges = cached.notes.edges?.filter((edge) => edge?.node?.id !== archivedId) ?? null

      return { notes: { ...cached.notes, edges } }
    })

    const cacheId = cache.identify({ __typename: 'Note', id: archivedId })
    if (cacheId) cache.evict({ id: cacheId })
    cache.gc()
  },
})

const actionError = ref('')

function isOverdue(dueAt?: string | null): boolean {
  return !!dueAt && new Date(dueAt).getTime() < Date.now()
}

function formatDueAt(dueAt: string): string {
  return new Date(dueAt).toLocaleString()
}

function formatState(state?: string | null): string {
  if (!state) return ''
  if (state === 'willnotdo') return 'Will not do'
  return state.charAt(0).toUpperCase() + state.slice(1)
}

async function onComplete(id?: string) {
  if (!id) return
  actionError.value = ''
  try {
    await completeNote({ variables: { id } })
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : 'Failed to update note.'
  }
}

async function onWillnotdo(id?: string) {
  if (!id) return
  actionError.value = ''
  try {
    await willnotdoNote({ variables: { id } })
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : 'Failed to update note.'
  }
}

async function onArchive(id?: string) {
  if (!id) return
  actionError.value = ''
  try {
    await archiveNote({ variables: { id } })
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : 'Failed to update note.'
  }
}
</script>

<template>
  <div>
    <h2 class="mb-2 text-lg font-semibold">
      Notes
    </h2>

    <p
      v-if="loading"
      class="text-gray-500"
    >
      Loading notes…
    </p>
    <p
      v-else-if="error"
      class="text-red-600"
    >
      Failed to load notes: {{ error.message }}
    </p>
    <p
      v-else-if="!result?.notes.edges?.length"
      class="text-gray-500"
    >
      No notes yet.
    </p>
    <ul
      v-else
      class="space-y-2"
    >
      <li
        v-for="edge in result.notes.edges"
        :key="edge?.node?.id"
        class="rounded border border-gray-200 p-3"
        :class="{ 'bg-red-500/20': isOverdue(edge?.node?.dueAt) }"
      >
        <p>{{ edge?.node?.note }}</p>
        <p class="text-xs font-medium text-gray-600">
          Status: {{ formatState(edge?.node?.state) }}
        </p>
        <p
          v-if="edge?.node?.dueAt"
          class="text-xs text-gray-500"
        >
          Due: {{ formatDueAt(edge.node.dueAt) }}
        </p>
        <p class="text-xs text-gray-400">
          {{ edge?.node?.createdAt }}
        </p>
        <div class="mt-2 flex gap-2">
          <button
            v-if="edge?.node?.state === 'pending'"
            type="button"
            data-action="complete"
            class="rounded bg-green-600 px-2 py-1 text-xs text-white"
            @click="onComplete(edge?.node?.id)"
          >
            Complete
          </button>
          <button
            v-if="edge?.node?.state === 'pending'"
            type="button"
            data-action="willnotdo"
            class="rounded bg-gray-500 px-2 py-1 text-xs text-white"
            @click="onWillnotdo(edge?.node?.id)"
          >
            Will not do
          </button>
          <button
            type="button"
            data-action="archive"
            class="rounded bg-red-700 px-2 py-1 text-xs text-white"
            @click="onArchive(edge?.node?.id)"
          >
            Archive
          </button>
        </div>
      </li>
    </ul>
    <p
      v-if="actionError"
      class="mt-2 text-sm text-red-600"
    >
      {{ actionError }}
    </p>
  </div>
</template>
