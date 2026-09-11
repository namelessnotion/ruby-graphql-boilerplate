import { ApolloClient, InMemoryCache } from '@apollo/client'
import { MockLink } from '@apollo/client/testing'
import { DefaultApolloClient } from '@vue/apollo-composable'
import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'

import { SaveNoteDocument } from '@/gql/graphql'

import NoteForm from '../NoteForm.vue'

function mountWithMocks(mocks: ConstructorParameters<typeof MockLink>[0]) {
  const client = new ApolloClient({
    link: new MockLink(mocks, { defaultOptions: { delay: 0 } }),
    cache: new InMemoryCache(),
  })

  return mount(NoteForm, {
    global: {
      provide: {
        [DefaultApolloClient]: client,
      },
    },
  })
}

describe('NoteForm', () => {
  it('submits the note and clears the input on success', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: SaveNoteDocument, variables: { note: 'remember the milk' } },
        result: {
          data: {
            saveNote: {
              note: { id: '1', note: 'remember the milk', createdAt: '2026-01-01T00:00:00Z' },
            },
          },
        },
      },
    ])

    const input = wrapper.get('input')
    await input.setValue('remember the milk')
    await wrapper.get('form').trigger('submit')

    await vi.waitFor(() => expect((input.element as HTMLInputElement).value).toBe(''))
    expect(wrapper.text()).not.toContain('Failed')
  })

  it('does not submit a blank note', () => {
    const wrapper = mountWithMocks([])

    const button = wrapper.get('button')
    expect(button.attributes('disabled')).toBeDefined()
  })

  it('does not submit a whitespace-only note', async () => {
    // No mocks registered: if onSubmit's trim-and-bail guard ever failed,
    // MockLink would throw on the unexpected request and fail this test.
    const wrapper = mountWithMocks([])

    await wrapper.get('input').setValue('   ')
    await wrapper.get('form').trigger('submit')

    expect(wrapper.text()).not.toContain('Failed')
  })

  it('shows an error message when the mutation fails', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: SaveNoteDocument, variables: { note: 'bad note' } },
        error: new Error('note is not present'),
      },
    ])

    await wrapper.get('input').setValue('bad note')
    await wrapper.get('form').trigger('submit')

    await vi.waitFor(() => expect(wrapper.text()).toContain('note is not present'))
  })
})
