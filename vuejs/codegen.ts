import type { CodegenConfig } from '@graphql-codegen/cli'

const config: CodegenConfig = {
  schema: '../ruby/app/graphql/schemas/app_schema.graphql',
  documents: ['src/**/*.{ts,vue}'],
  ignoreNoDocuments: true,
  generates: {
    './src/gql/': {
      preset: 'client',
      config: {
        useTypeImports: true,
        scalars: {
          ISO8601DateTime: 'string',
        },
      },
    },
  },
}

export default config
