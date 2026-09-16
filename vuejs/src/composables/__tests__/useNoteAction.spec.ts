import { ref } from 'vue'
import { describe, expect, it, vi } from 'vitest'

import { useNoteAction } from '../useNoteAction'

describe('useNoteAction', () => {
  it('does nothing when no id is given', async () => {
    const mutate = vi.fn()
    const error = ref('')
    const { run } = useNoteAction(mutate, error)

    await run(undefined)

    expect(mutate).not.toHaveBeenCalled()
  })

  it('calls mutate with the note id and clears a previous error', async () => {
    const mutate = vi.fn().mockResolvedValue({})
    const error = ref('previous failure')
    const { run } = useNoteAction(mutate, error)

    await run('1')

    expect(mutate).toHaveBeenCalledWith({ variables: { id: '1' } })
    expect(error.value).toBe('')
  })

  it('sets the error message when mutate throws an Error', async () => {
    const mutate = vi.fn().mockRejectedValue(new Error('note not found'))
    const error = ref('')
    const { run } = useNoteAction(mutate, error)

    await run('1')

    expect(error.value).toBe('note not found')
  })

  it('sets a generic error message when mutate throws a non-Error', async () => {
    const mutate = vi.fn().mockRejectedValue('boom')
    const error = ref('')
    const { run } = useNoteAction(mutate, error)

    await run('1')

    expect(error.value).toBe('Failed to update note.')
  })
})
