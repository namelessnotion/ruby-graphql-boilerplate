<script setup lang="ts">
import NoteForm from '@/components/NoteForm.vue'
import NoteList from '@/components/NoteList.vue'
</script>

<template>
  <main class="mx-auto max-w-xl p-6">
    <h1 class="mb-4 text-2xl font-bold">Notes</h1>
    <NoteForm class="mb-6" />
    <NoteList />
  </main>
</template>
