<script setup lang="ts">
import { useQuery } from '@vue/apollo-composable'

import { graphql } from '@/gql'

const NotesDocument = graphql(`
  query Notes {
    notes {
      edges {
        node {
          id
          note
          createdAt
        }
      }
    }
  }
`)

const { result, loading, error } = useQuery(NotesDocument)
</script>

<template>
  <div>
    <h2 class="mb-2 text-lg font-semibold">Notes</h2>

    <p v-if="loading" class="text-gray-500">Loading notes…</p>
    <p v-else-if="error" class="text-red-600">Failed to load notes: {{ error.message }}</p>
    <p v-else-if="!result?.notes.edges?.length" class="text-gray-500">No notes yet.</p>
    <ul v-else class="space-y-2">
      <li
        v-for="edge in result.notes.edges"
        :key="edge?.node?.id"
        class="rounded border border-gray-200 p-3"
      >
        <p>{{ edge?.node?.note }}</p>
        <p class="text-xs text-gray-400">{{ edge?.node?.createdAt }}</p>
      </li>
    </ul>
  </div>
</template>
