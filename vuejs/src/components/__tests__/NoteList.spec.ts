import { ApolloClient, ApolloLink, InMemoryCache } from '@apollo/client'
import { MockLink } from '@apollo/client/testing'
import { DefaultApolloClient } from '@vue/apollo-composable'
import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'

import { ArchiveNoteDocument, CompleteNoteDocument, NotesDocument, WillnotdoNoteDocument } from '@/gql/graphql'

import NoteList from '../NoteList.vue'

function mountWithMocks(mocks: ConstructorParameters<typeof MockLink>[0], operations: string[] = []) {
  const recordOperations = new ApolloLink((operation, forward) => {
    operations.push(operation.operationName ?? 'anonymous')
    return forward(operation)
  })

  const client = new ApolloClient({
    link: ApolloLink.from([recordOperations, new MockLink(mocks, { defaultOptions: { delay: 0 } })]),
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

// Mocked responses have to look like the server's: every field the document selects,
// plus __typename. A missing field makes Apollo serve the raw network response instead
// of the cached one, and a missing __typename stops the note being normalized, so a
// mutation writing the same note cannot update the list.
function notesResult(nodes: Array<Record<string, unknown>>) {
  return {
    data: {
      notes: {
        __typename: 'NoteConnection',
        edges: nodes.map((node) => ({
          __typename: 'NoteEdge',
          node: { __typename: 'Note', dueAt: null, ...node },
        })),
      },
    },
  }
}

function notePayload(typename: string, field: string, note: Record<string, unknown>) {
  return { data: { [field]: { __typename: typename, note: { __typename: 'Note', ...note } } } }
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

  it('completes a pending note when Complete is clicked, without refetching the list', async () => {
    const operations: string[] = []
    const wrapper = mountWithMocks(
      [
        {
          request: { query: NotesDocument },
          result: notesResult([
            { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
          ]),
        },
        {
          request: { query: CompleteNoteDocument, variables: { id: '1' } },
          result: notePayload('CompleteNotePayload', 'completeNote', { id: '1', state: 'completed' }),
        },
      ],
      operations,
    )

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('button[data-action="complete"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.text()).toContain('Status: Completed'))
    expect(wrapper.findAll('button').map((b) => b.text())).not.toContain('Complete')
    expect(wrapper.text()).not.toContain('Failed')
    expect(operations).toEqual(['Notes', 'CompleteNote'])
  })

  it('marks a pending note as will-not-do when Will not do is clicked, without refetching the list', async () => {
    const operations: string[] = []
    const wrapper = mountWithMocks(
      [
        {
          request: { query: NotesDocument },
          result: notesResult([
            { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
          ]),
        },
        {
          request: { query: WillnotdoNoteDocument, variables: { id: '1' } },
          result: notePayload('WillnotdoNotePayload', 'willnotdoNote', { id: '1', state: 'willnotdo' }),
        },
      ],
      operations,
    )

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('button[data-action="willnotdo"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.text()).toContain('Status: Will not do'))
    expect(wrapper.text()).not.toContain('Failed')
    expect(operations).toEqual(['Notes', 'WillnotdoNote'])
  })

  it('archives a note when Archive is clicked, removing it from the list without refetching', async () => {
    const operations: string[] = []
    const wrapper = mountWithMocks(
      [
        {
          request: { query: NotesDocument },
          result: notesResult([
            { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
            { id: '2', note: 'buy groceries', state: 'pending', createdAt: '2026-01-02T00:00:00Z' },
          ]),
        },
        {
          request: { query: ArchiveNoteDocument, variables: { id: '1' } },
          result: notePayload('ArchiveNotePayload', 'archiveNote', { id: '1', state: 'archived' }),
        },
      ],
      operations,
    )

    await vi.waitFor(() => expect(wrapper.text()).toContain('remember the milk'))
    await wrapper.get('li button[data-action="archive"]').trigger('click')

    await vi.waitFor(() => expect(wrapper.text()).not.toContain('remember the milk'))
    expect(wrapper.text()).toContain('buy groceries')
    expect(wrapper.text()).not.toContain('Failed')
    expect(operations).toEqual(['Notes', 'ArchiveNote'])
  })

  it('shows the empty state after archiving the only note', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: notesResult([
          { id: '1', note: 'remember the milk', state: 'pending', createdAt: '2026-01-01T00:00:00Z' },
        ]),
      },
      {
        request: { query: ArchiveNoteDocument, variables: { id: '1' } },
        result: notePayload('ArchiveNotePayload', 'archiveNote', { id: '1', state: 'archived' }),
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
