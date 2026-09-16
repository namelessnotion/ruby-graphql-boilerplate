import { createApp } from 'vue'

import App from './App.vue'
import { apolloClient } from './lib/apollo-client'
import { Log } from './lib/observability'
import { DefaultApolloClient } from '@vue/apollo-composable'
import './style.css'

const app = createApp(App)
app.provide(DefaultApolloClient, apolloClient)

// Catches what a component's own try/catch never got a chance to: a render
// error, an error thrown outside an event handler, or a rejected promise
// nothing downstream awaited.
app.config.errorHandler = (error, _instance, info) => {
  Log.error('unhandled vue error', {
    'error.message': error instanceof Error ? error.message : String(error),
    'vue.error_info': info,
  })
}

window.addEventListener('unhandledrejection', (event) => {
  Log.error('unhandled promise rejection', {
    'error.message': event.reason instanceof Error ? event.reason.message : String(event.reason),
  })
})

app.mount('#app')
