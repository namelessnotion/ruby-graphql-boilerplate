import { ref } from 'vue'
import { describe, expect, it, vi } from 'vitest'

import { useNoteAction } from '../useNoteAction'

describe('useNoteAction', () => {
  it('does nothing when no id is given', async () => {
    const mutate = vi.fn()
    const errors = ref({})
    const { run } = useNoteAction(mutate, errors)

    await run(undefined)

    expect(mutate).not.toHaveBeenCalled()
  })

  it('calls mutate with the note id and clears a previous error for that id', async () => {
    const mutate = vi.fn().mockResolvedValue({})
    const errors = ref({ '1': 'previous failure' })
    const { run } = useNoteAction(mutate, errors)

    await run('1')

    expect(mutate).toHaveBeenCalledWith({ variables: { id: '1' } })
    expect(errors.value['1']).toBe('')
  })

  it('sets the error message for the given id when mutate throws an Error', async () => {
    const mutate = vi.fn().mockRejectedValue(new Error('note not found'))
    const errors = ref({})
    const { run } = useNoteAction(mutate, errors)

    await run('1')

    expect(errors.value['1']).toBe('note not found')
  })

  it('sets a generic error message for the given id when mutate throws a non-Error', async () => {
    const mutate = vi.fn().mockRejectedValue('boom')
    const errors = ref({})
    const { run } = useNoteAction(mutate, errors)

    await run('1')

    expect(errors.value['1']).toBe('Failed to update note.')
  })

  it('does not touch other ids when one action fails', async () => {
    const mutate = vi.fn().mockRejectedValue(new Error('note not found'))
    const errors = ref({ '2': 'unrelated failure' })
    const { run } = useNoteAction(mutate, errors)

    await run('1')

    expect(errors.value['1']).toBe('note not found')
    expect(errors.value['2']).toBe('unrelated failure')
  })
})
