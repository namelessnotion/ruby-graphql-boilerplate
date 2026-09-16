import { ApolloClient, InMemoryCache } from '@apollo/client'
import { MockLink } from '@apollo/client/testing'
import { DefaultApolloClient } from '@vue/apollo-composable'
import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'

import { ArchiveNoteDocument, CompleteNoteDocument, NotesDocument, WillnotdoNoteDocument } from '@/gql/graphql'

import NoteList from '../NoteList.vue'

function mountWithMocks(mocks: ConstructorParameters<typeof MockLink>[0]) {
  const client = new ApolloClient({
    link: new MockLink(mocks, { defaultOptions: { delay: 0 } }),
    cache: new InMemoryCache(),
  })

  return mount(NoteList, {
    global: {
      provide: {
        [DefaultApolloClient]: client,
      },
    },
  })
}

function notesResult(nodes: Array<Record<string, unknown>>) {
  return { data: { notes: { edges: nodes.map((node) => ({ node })) } } }
}

describe('NoteList', () => {
  it('renders notes returned by the query', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
          { id: '2', note: 'buy groceries', state: 'pending', createdAt: '2026-01-02T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.text()).toContain('buy groceries')
  })

  it('shows an empty state when there are no notes', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: { data: { notes: { edges: [] } } },
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('No notes yet.'))
  })

  it('shows an error message when the query fails', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        error: new Error('network down'),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('Failed to load notes'))
  })

  it('displays the due date when present', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          {
            id: '1',
            note: 'remember the milk',
            state: 'pending',
            dueAt: '2099-01-01T00:00:00.000Z',
            createdAt: '2026-01-01T00:00:00Z',
          },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain(new Date('2099-01-01T00:00:00.000Z').toLocaleString()))
  })

  it('does not highlight a note whose due date is in the future', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          {
            id: '1',
            note: 'remember the milk',
            state: 'pending',
            dueAt: '2099-01-01T00:00:00.000Z',
            createdAt: '2026-01-01T00:00:00Z',
          },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.get('li').classes()).not.toContain('bg-red-500/20')
  })

  it('highlights a note whose due date is in the past', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          {
            id: '1',
            note: 'remember the milk',
            state: 'pending',
            dueAt: '2020-01-01T00:00:00.000Z',
            createdAt: '2026-01-01T00:00:00Z',
          },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.get('li').classes()).toContain('bg-red-500/20')
  })

  it('does not display a due date when absent', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', dueAt: null, createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.text()).not.toContain('Due:')
  })

  it('shows the current state of a pending note', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.text()).toContain('Status: Pending')
  })

  it('shows the current state of a completed note', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'completed', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.text()).toContain('Status: Completed')
  })

  it('shows a readable label for the will-not-do state', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'willnotdo', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    expect(wrapper.text()).toContain('Status: Will not do')
  })

  it('shows Complete, Will not do, and Archive buttons for a pending note', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    const buttonLabels = wrapper.findAll('button').map((button) => button.text())
    expect(buttonLabels).toContain('Complete')
    expect(buttonLabels).toContain('Will not do')
    expect(buttonLabels).toContain('Archive')
  })

  it('only shows the Archive button for a completed note', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'completed', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    const buttonLabels = wrapper.findAll('button').map((button) => button.text())
    expect(buttonLabels).not.toContain('Complete')
    expect(buttonLabels).not.toContain('Will not do')
    expect(buttonLabels).toContain('Archive')
  })

  it('completes a pending note when Complete is clicked', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
      {
        request: { query: CompleteNoteDocument, variables: { id: '1' } },
        result: { data: { completeNote: { note: { id: '1', state: 'completed' } } } },
      },
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'completed', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('button[data-action="complete"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.findAll('button').map((b) => b.text())).not.toContain('Complete'))
    expect(wrapper.text()).not.toContain('Failed')
  })

  it('marks a pending note as will-not-do when Will not do is clicked', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
      {
        request: { query: WillnotdoNoteDocument, variables: { id: '1' } },
        result: { data: { willnotdoNote: { note: { id: '1', state: 'willnotdo' } } } },
      },
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'willnotdo', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('button[data-action="willnotdo"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.findAll('button').map((b) => b.text())).not.toContain('Will not do'))
    expect(wrapper.text()).not.toContain('Failed')
  })

  it('archives a note when Archive is clicked, removing it from the list', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
      {
        request: { query: ArchiveNoteDocument, variables: { id: '1' } },
        result: { data: { archiveNote: { note: { id: '1', state: 'archived' } } } },
      },
      {
        request: { query: NotesDocument },
        result: notesResult([]),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('button[data-action="archive"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.text()).toContain('No notes yet.'))
  })

  it('shows an error message when an action fails', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
      {
        request: { query: CompleteNoteDocument, variables: { id: '1' } },
        error: new Error('note not found'),
      },
    ])

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('button[data-action="complete"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.text()).toContain('note not found'))
  })
})
