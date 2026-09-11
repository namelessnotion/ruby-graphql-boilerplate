import { ApolloClient, InMemoryCache } from '@apollo/client'
import { MockLink } from '@apollo/client/testing'
import { DefaultApolloClient } from '@vue/apollo-composable'
import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'

import { NotesDocument } from '@/gql/graphql'

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

describe('NoteList', () => {
  it('renders notes returned by the query', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: NotesDocument },
        result: {
          data: {
            notes: {
              edges: [
                { node: { id: '1', note: 'remember the milk', createdAt: '2026-01-01T00:00:00Z' } },
                { node: { id: '2', note: 'buy groceries', createdAt: '2026-01-02T00:00:00Z' } },
              ],
            },
          },
        },
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
})
