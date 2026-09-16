import { ApolloClient, ApolloLink, InMemoryCache } from '@apollo/client'
import { MockLink } from '@apollo/client/testing'
import { DefaultApolloClient } from '@vue/apollo-composable'
import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'

import { SaveNoteDocument } from '@/gql/graphql'
import { errorLink } from '@/lib/apollo-client'
import { Log } from '@/lib/observability'

import NoteForm from '../NoteForm.vue'

function mountWithMocks(mocks: ConstructorParameters<typeof MockLink>[0]) {
  const client = new ApolloClient({
    link: ApolloLink.from([errorLink, new MockLink(mocks, { defaultOptions: { delay: 0 } })]),
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

    const input = wrapper.get('input[type="text"]')
    await input.setValue('remember the milk')
    await wrapper.get('form').trigger('submit')

    await vi.waitFor(() => expect((input.element as HTMLInputElement).value).toBe(''))
    expect(wrapper.text()).not.toContain('Failed')
    expect(wrapper.text()).not.toContain('Note text is required.')
  })

  it('does not submit a blank note', () => {
    const wrapper = mountWithMocks([])

    const button = wrapper.get('button')
    expect(button.attributes('disabled')).toBeDefined()
  })

  it('does not submit a whitespace-only note, and shows a validation error', async () => {
    // No mocks registered: if onSubmit's validation guard ever failed,
    // MockLink would throw on the unexpected request and fail this test.
    const wrapper = mountWithMocks([])

    await wrapper.get('input[type="text"]').setValue('   ')
    await wrapper.get('form').trigger('submit')

    expect(wrapper.text()).not.toContain('Failed')
    await vi.waitFor(() => expect(wrapper.text()).toContain('Note text is required.'))
  })

  it('shows an error message when the mutation fails, and records it structurally', async () => {
    const errorSpy = vi.spyOn(Log, 'error').mockImplementation(() => {})

    const wrapper = mountWithMocks([
      {
        request: { query: SaveNoteDocument, variables: { note: 'bad note' } },
        error: new Error('note is not present'),
      },
    ])

    await wrapper.get('input[type="text"]').setValue('bad note')
    await wrapper.get('form').trigger('submit')

    await vi.waitFor(() => expect(wrapper.text()).toContain('note is not present'))
    expect(errorSpy).toHaveBeenCalledWith(
      'graphql operation failed',
      expect.objectContaining({
        'graphql.operation.name': 'SaveNote',
        'error.type': 'network',
        'error.message': 'note is not present',
      }),
    )

    errorSpy.mockRestore()
  })

  it('submits the note with a due date when provided', async () => {
    const dueAtLocal = '2099-06-01T10:00'
    const dueAtIso = new Date(dueAtLocal).toISOString()

    const wrapper = mountWithMocks([
      {
        request: {
          query: SaveNoteDocument,
          variables: { note: 'remember the milk', dueAt: dueAtIso },
        },
        result: {
          data: {
            saveNote: {
              note: { id: '1', note: 'remember the milk', dueAt: dueAtIso, createdAt: '2026-01-01T00:00:00Z' },
            },
          },
        },
      },
    ])

    await wrapper.get('input[type="text"]').setValue('remember the milk')
    await wrapper.get('input[type="datetime-local"]').setValue(dueAtLocal)
    await wrapper.get('form').trigger('submit')

    await vi.waitFor(() => expect((wrapper.get('input[type="text"]').element as HTMLInputElement).value).toBe(''))
    expect((wrapper.get('input[type="datetime-local"]').element as HTMLInputElement).value).toBe('')
    expect(wrapper.text()).not.toContain('Failed')
    expect(wrapper.text()).not.toContain('Note text is required.')
    expect(wrapper.text()).not.toContain('Due date must be in the future.')
  })

  it('submits the note without a due date when none is provided', async () => {
    const wrapper = mountWithMocks([
      {
        request: { query: SaveNoteDocument, variables: { note: 'remember the milk' } },
        result: {
          data: {
            saveNote: {
              note: { id: '1', note: 'remember the milk', dueAt: null, createdAt: '2026-01-01T00:00:00Z' },
            },
          },
        },
      },
    ])

    await wrapper.get('input[type="text"]').setValue('remember the milk')
    await wrapper.get('form').trigger('submit')

    await vi.waitFor(() => expect((wrapper.get('input[type="text"]').element as HTMLInputElement).value).toBe(''))
    expect(wrapper.text()).not.toContain('Failed')
  })

  it('does not submit and shows a validation error when the due date is in the past', async () => {
    // No mocks registered: if onSubmit's validation guard ever failed,
    // MockLink would throw on the unexpected request and fail this test.
    const wrapper = mountWithMocks([])

    await wrapper.get('input[type="text"]').setValue('remember the milk')
    await wrapper.get('input[type="datetime-local"]').setValue('2020-01-01T10:00')
    await wrapper.get('form').trigger('submit')

    expect(wrapper.text()).not.toContain('Failed')
    await vi.waitFor(() => expect(wrapper.text()).toContain('Due date must be in the future.'))
  })
})
