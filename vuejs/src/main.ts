import { createApp } from 'vue'

import App from './App.vue'
import { apolloClient } from './lib/apollo-client'
import { DefaultApolloClient } from '@vue/apollo-composable'
import './style.css'

const app = createApp(App)
app.provide(DefaultApolloClient, apolloClient)
app.mount('#app')
